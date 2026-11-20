import Foundation

/// Turns a finished chat into the record Ambient stores: events numbered, paths made relative to the repository,
/// secrets blanked, long output cut, and the commits it made found in git.
public struct Capture: Sendable {
    /// How much of each kind of text is kept. What's dropped is counted in the event's `cut`.
    public struct Limits: Sendable {
        public var said = 20_000
        public var thinking = 6_000
        public var command = 12_000
        public var diff = 30_000
        /// Kept from each end of a tool's output.
        public var resultEnd = 1_500

        public init() {}
    }

    public var git: GitFacts
    public var home: String
    public var limits = Limits()
    /// How long after a chat's last event a commit can still be counted as carrying one of its shell edits: time
    /// for the person to commit by hand what the agent left.
    public var commitGrace: TimeInterval = 600

    public init(git: GitFacts = GitFacts(), home: String) {
        self.git = git
        self.home = home
    }

    /// Where a chat's repository is, and what it's called.
    public struct Place: Equatable, Sendable {
        /// A checkout of the repository that git can be asked in: the chat's own, or, when that was a worktree
        /// that has been removed, the checkout it sat inside. Nil when there is none.
        public var root: String?
        public var repo: String
        /// False when the chat's own folder is gone.
        public var ownCheckout: Bool

        public init(root: String?, repo: String, ownCheckout: Bool = true) {
            self.root = root
            self.repo = repo
            self.ownCheckout = ownCheckout
        }
    }

    public func place(of chat: RawChat) -> Place {
        let folder = chat.folder ?? home
        if let root = git.root(of: folder) {
            return Place(root: root, repo: git.slug(of: root) ?? Self.folderName(root))
        }
        // The folder is gone. If it was a worktree made inside another checkout of the repository, that checkout
        // still knows the repository. The chat's branch must exist there and be a branch of its own (two worktrees
        // can't share one), or the folder may have been some other project that only sat inside.
        var ancestor = PathFinder.standard(folder)
        while ancestor.count > 1, !FileManager.default.fileExists(atPath: ancestor) {
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        if ancestor.count > 1, let root = git.root(of: ancestor),
           PathFinder.standard(folder).hasPrefix(PathFinder.standard(root) + "/"),
           let branch = chat.branch, !["main", "master", "HEAD"].contains(branch), git.hasBranch(branch, in: root),
           let slug = git.slug(of: root) {
            return Place(root: root, repo: slug, ownCheckout: false)
        }
        return Place(root: nil, repo: Self.folderName(folder), ownCheckout: false)
    }

    static func folderName(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? "unknown" : name
    }

    public func record(from chat: RawChat, now: Date = Date()) -> ChatRecord {
        let place = place(of: chat)
        let redactor = Redactor(home: home)
        let started = chat.startedAt ?? now
        let ended = chat.endedAt ?? started

        var roots: [String] = []
        var tracked = Set<String>()
        var nearby: [ChatCommit] = []
        var merges = Set<String>()
        // When each file was committed, by anyone, from the chat's start until a little after its end.
        var committed: [String: [Date]] = [:]
        if let root = place.root {
            roots = [root] + worktrees(of: root)
            tracked = git.trackedFiles(in: root)
            let until = ended.addingTimeInterval(commitGrace)
            nearby = git.commits(in: root, from: started.addingTimeInterval(-2), to: until)
            merges = git.merges(in: root, from: started.addingTimeInterval(-2), to: until)
            for commit in nearby {
                for file in commit.files { committed[file, default: []].append(commit.at) }
            }
            tracked.formUnion(committed.keys)
        }
        // What differs from HEAD in each checkout, asked once per checkout and only for ones the chat worked in:
        // a chat can start in one worktree and edit in another, and each has its own uncommitted work.
        var dirtyByRoot: [String: Set<String>] = [:]
        func dirty(in root: String) -> Set<String> {
            if let known = dirtyByRoot[root] { return known }
            let files = dirtyFiles(in: root)
            dirtyByRoot[root] = files
            return files
        }
        if let root = place.root, place.ownCheckout { tracked.formUnion(dirty(in: root)) }
        let finder = PathFinder(roots: roots, home: home, known: tracked)

        var events: [ChatEvent] = []
        var numberOfCall: [String: Int] = [:]
        var resultTime: [String: Date] = [:]
        // Calls whose tool said they failed: an edit that didn't apply changed nothing.
        var failedCalls = Set<String>()
        for raw in chat.events where raw.kind == .result {
            if let id = raw.callID, let at = raw.at, resultTime[id] == nil { resultTime[id] = at }
            if raw.failed, let id = raw.callID { failedCalls.insert(id) }
        }
        // The files the chat changed, by the checkout it changed them in.
        var changedIn: [String: Set<String>] = [:]
        for raw in chat.events {
            let n = events.count + 1
            var event = ChatEvent(n: n, at: raw.at, kind: raw.kind, actor: redactor.clean(raw.actor), text: raw.text,
                                  tool: raw.tool, label: raw.label, diff: raw.diff)
            var touches: [FileTouch] = []
            var limit = limits.said
            switch raw.kind {
            case .tool:
                limit = limits.command
                if let id = raw.callID, numberOfCall[id] == nil { numberOfCall[id] = n }
                let failed = raw.callID.map(failedCalls.contains) ?? false
                let placed = raw.paths.map { (location: finder.locate($0.path, from: raw.folder), how: $0.how) }
                for (location, how) in placed {
                    let kept: FileTouch.How = failed && how.changes ? .read : how
                    touches.append(FileTouch(path: location.path, how: kept))
                    if kept.changes, let root = location.root { changedIn[root, default: []].insert(location.path) }
                }
                if let first = placed.first, raw.paths.count == 1, raw.text == raw.paths[0].path {
                    event.text = first.location.path
                } else if raw.tool == "Bash" {
                    let writing = PathFinder.writing(raw.text)
                    var targets = Set<String>()
                    if case let .only(names) = writing {
                        targets = Set(names.map { finder.locate($0, from: raw.folder).path })
                    }
                    let after = (raw.at ?? started).addingTimeInterval(-2)
                    for location in finder.located(in: raw.text, from: raw.folder) {
                        // The command must be one that could have written this file: it changes files in place, or
                        // this file is where it sends its output.
                        var changed = writing == .anything || targets.contains(location.path)
                        // And git must agree: the file still differs from HEAD in the checkout it was named in, or
                        // it was committed after the command ran and before the chat was long over. Without a
                        // repository to ask, the command's word is all there is.
                        if changed, place.root != nil {
                            let stillDirty = location.root.map { dirty(in: $0).contains(location.path) } ?? false
                            let committedAfter = (committed[location.path] ?? []).contains { $0 >= after }
                            changed = stillDirty || committedAfter
                        }
                        touches.append(FileTouch(path: location.path, how: changed ? .shell : .read))
                        if changed, let root = location.root { changedIn[root, default: []].insert(location.path) }
                    }
                }
            case .result:
                if let id = raw.callID { event.of = numberOfCall[id] }
                if raw.failed { event.failed = true }
            case .user, .agent:
                touches = finder.paths(in: raw.text, from: raw.folder).map { FileTouch(path: $0, how: .mention) }
            case .system, .thinking:
                if raw.kind == .thinking { limit = limits.thinking }
            }

            event.text = redactor.clean(event.text)
            event.label = redactor.clean(event.label)
            event.diff = redactor.clean(event.diff)
            var cut = 0
            if raw.kind == .result {
                if event.text.count > limits.resultEnd * 2 {
                    cut += event.text.count - limits.resultEnd * 2
                    event.text = String(event.text.prefix(limits.resultEnd)) + "\n…\n" + String(event.text.suffix(limits.resultEnd))
                }
            } else if event.text.count > limit {
                cut += event.text.count - limit
                event.text = String(event.text.prefix(limit))
            }
            if let diff = event.diff, diff.count > limits.diff {
                cut += diff.count - limits.diff
                event.diff = String(diff.prefix(limits.diff))
            }
            if event.diff?.isEmpty == true { event.diff = nil }
            if cut > 0 { event.cut = cut }
            if !touches.isEmpty {
                var seen = Set<String>()
                // One line per file: the strongest thing the event did to it.
                event.touches = touches.sorted { Self.rank($0.how) < Self.rank($1.how) }
                    .filter { seen.insert($0.path).inserted }
                    .map { FileTouch(path: redactor.clean($0.path), how: $0.how) }
            }
            events.append(event)
        }

        var commits: [ChatCommit] = []
        var taken = Set<String>()
        let changedByChat = Set(events.flatMap { $0.touches ?? [] }.filter { $0.how.changes }.map(\.path))
        for (index, raw) in chat.events.enumerated() where raw.kind == .tool && raw.tool == "Bash"
            && PathFinder.commits(raw.text) {
            guard let at = raw.at else { continue }
            let end = raw.callID.flatMap { resultTime[$0] } ?? at.addingTimeInterval(120)
            // Git keeps whole seconds; the transcript keeps milliseconds.
            let window = at.addingTimeInterval(-1.5)...max(end, at).addingTimeInterval(1.5)
            for commit in nearby where window.contains(commit.at) {
                // The time alone isn't proof: a command that runs the tests and then commits stays open for
                // minutes, and another chat in the same repository may commit meanwhile. So the commit must also
                // look like this chat's: its message is in the command, or it holds a file this chat changed, or
                // it is a merge and the command merges. A commit with no files has nothing to compare, and is
                // taken on the time.
                let merging = merges.contains(commit.sha) && PathFinder.merges(raw.text)
                let mine = (!commit.subject.isEmpty && raw.text.contains(commit.subject)) || merging
                    || commit.files.isEmpty || !changedByChat.isDisjoint(with: commit.files)
                guard mine, taken.insert(commit.sha).inserted else { continue }
                var commit = commit
                commit.event = index + 1
                commit.subject = redactor.clean(commit.subject)
                commit.files = commit.files.map { (file: String) -> String in redactor.clean(file) }
                commits.append(commit)
            }
        }

        // Each checkout's own uncommitted work, for the files the chat changed there and no others: another chat
        // may be working in the same checkout.
        var uncommitted: String?
        let diffs = changedIn.keys.sorted().compactMap { root -> String? in
            let diff = git.uncommitted((changedIn[root] ?? []).sorted(), in: root)
            return diff.isEmpty ? nil : diff
        }
        if !diffs.isEmpty {
            let cleaned: String = redactor.clean(diffs.joined())
            uncommitted = cleaned
        }

        let firstRequest = events.first { $0.kind == .user }?.text
        let title = chat.title ?? firstRequest.map { String($0.split(separator: "\n").first ?? "").prefix(80) }.map(String.init)
        let branch = chat.branch ?? (place.ownCheckout ? place.root.flatMap(git.branch) : nil)
        let session = ChatSession(id: chat.sessionID, agent: chat.agent, repo: place.repo,
                                  branch: redactor.clean(branch), developer: place.root.flatMap(git.developer),
                                  title: redactor.clean(title), startedAt: started, endedAt: ended)
        return ChatRecord(session: session, commits: commits, uncommitted: uncommitted, events: events)
    }

    static func rank(_ how: FileTouch.How) -> Int {
        switch how {
        case .edit: 0
        case .write: 1
        case .shell: 2
        case .read: 3
        case .mention: 4
        }
    }

    /// The repository's other checkouts.
    private func worktrees(of root: String) -> [String] {
        let output = git.shell("git", ["worktree", "list", "--porcelain"], in: root)
        guard output.succeeded else { return [] }
        return output.stdout.split(separator: "\n").filter { $0.hasPrefix("worktree ") }
            .map { String($0.dropFirst("worktree ".count)) }.filter { $0 != root }
    }

    /// Files that differ from `HEAD` or aren't tracked yet.
    private func dirtyFiles(in root: String) -> Set<String> {
        let output = git.shell("git", ["status", "--porcelain", "-z", "--untracked-files=all"], in: root)
        guard output.succeeded else { return [] }
        var files = Set<String>()
        var entries = output.stdout.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let entry = entries.popFirst() {
            guard entry.count > 3 else { continue }
            files.insert(String(entry.dropFirst(3)))
            // A rename or copy is followed by the name it had.
            if let status = entry.first, status == "R" || status == "C", let old = entries.popFirst() { files.insert(old) }
        }
        return files
    }
}
