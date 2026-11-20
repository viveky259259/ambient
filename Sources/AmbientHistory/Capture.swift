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

    public init(git: GitFacts = GitFacts(), home: String) {
        self.git = git
        self.home = home
    }

    /// Where a chat's repository is, and what it's called.
    public struct Place: Equatable, Sendable {
        /// The checkout the chat started in; nil when its folder is gone or was never a repository.
        public var root: String?
        public var repo: String
    }

    public func place(of chat: RawChat) -> Place {
        let folder = chat.folder ?? home
        guard let root = git.root(of: folder) else {
            return Place(root: nil, repo: Self.folderName(folder))
        }
        return Place(root: root, repo: git.slug(of: root) ?? Self.folderName(root))
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
        var dirty = Set<String>()
        // When each file was last committed, by anyone, since the chat began.
        var lastCommitted: [String: Date] = [:]
        var nearby: [ChatCommit] = []
        var merges = Set<String>()
        if let root = place.root {
            roots = [root] + worktrees(of: root)
            tracked = git.trackedFiles(in: root)
            nearby = git.commits(in: root, from: started.addingTimeInterval(-2), to: now.addingTimeInterval(2))
            merges = git.merges(in: root, from: started.addingTimeInterval(-2), to: ended.addingTimeInterval(180))
            for commit in nearby {
                for file in commit.files where (lastCommitted[file] ?? .distantPast) < commit.at { lastCommitted[file] = commit.at }
            }
            dirty = dirtyFiles(in: root)
            tracked.formUnion(lastCommitted.keys)
            tracked.formUnion(dirty)
        }
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
        for raw in chat.events {
            let n = events.count + 1
            var event = ChatEvent(n: n, at: raw.at, kind: raw.kind, actor: raw.actor, text: raw.text, tool: raw.tool,
                                  label: raw.label, diff: raw.diff)
            var touches: [FileTouch] = []
            var limit = limits.said
            switch raw.kind {
            case .tool:
                limit = limits.command
                if let id = raw.callID, numberOfCall[id] == nil { numberOfCall[id] = n }
                let failed = raw.callID.map(failedCalls.contains) ?? false
                touches = raw.paths.map {
                    FileTouch(path: finder.relative($0.path, from: raw.folder), how: failed && $0.how.changes ? .read : $0.how)
                }
                if let first = touches.first, raw.paths.count == 1, raw.text == raw.paths[0].path {
                    event.text = first.path
                } else if raw.tool == "Bash" {
                    let writes = PathFinder.writes(raw.text)
                    for path in finder.paths(in: raw.text, from: raw.folder) {
                        // A command that writes files and names this one changed it only if git agrees: the file
                        // was committed after the command ran, or still differs from HEAD. Without a repository to
                        // ask, the command's word is all there is.
                        let after = (raw.at ?? started).addingTimeInterval(-2)
                        let changed = writes && (place.root == nil || dirty.contains(path)
                            || (lastCommitted[path] ?? .distantPast) >= after)
                        touches.append(FileTouch(path: path, how: changed ? .shell : .read))
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
        let named = Set(events.flatMap { $0.touches ?? [] }.map(\.path))
        for (index, raw) in chat.events.enumerated() where raw.kind == .tool && raw.tool == "Bash"
            && PathFinder.commits(raw.text) {
            guard let at = raw.at else { continue }
            let end = raw.callID.flatMap { resultTime[$0] } ?? at.addingTimeInterval(120)
            // Git keeps whole seconds; the transcript keeps milliseconds.
            let window = at.addingTimeInterval(-1.5)...max(end, at).addingTimeInterval(1.5)
            for commit in nearby where window.contains(commit.at) {
                // The time alone isn't proof: a command that runs the tests and then commits stays open for
                // minutes, and another chat in the same checkout may commit meanwhile. So the commit must also
                // look like this chat's: its message is in the command, or it holds a file this chat named, or it
                // is a merge and the command merges. A commit with no files has nothing to compare, and is taken
                // on the time.
                let merging = merges.contains(commit.sha) && PathFinder.merges(raw.text)
                let mine = (!commit.subject.isEmpty && raw.text.contains(commit.subject)) || merging
                    || commit.files.isEmpty || !named.isDisjoint(with: commit.files)
                guard mine, taken.insert(commit.sha).inserted else { continue }
                var commit = commit
                commit.event = index + 1
                commit.subject = redactor.clean(commit.subject)
                commits.append(commit)
            }
        }

        var uncommitted: String?
        if let root = place.root {
            let changed = Set(events.flatMap { $0.touches ?? [] }.filter { $0.how.changes }.map(\.path))
                .filter { !$0.hasPrefix("/") && !$0.hasPrefix("~") }
            // Only this chat's files: another chat may be working in the same checkout.
            let diff = git.uncommitted(changed.sorted(), in: root)
            if !diff.isEmpty { uncommitted = redactor.clean(diff) }
        }

        let firstRequest = events.first { $0.kind == .user }?.text
        let title = chat.title ?? firstRequest.map { String($0.split(separator: "\n").first ?? "").prefix(80) }.map(String.init)
        let session = ChatSession(id: chat.sessionID, agent: chat.agent, repo: place.repo,
                                  branch: chat.branch ?? place.root.flatMap(git.branch),
                                  developer: place.root.flatMap(git.developer), title: redactor.clean(title),
                                  startedAt: started, endedAt: ended)
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
