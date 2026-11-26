import Foundation

/// "Why did this file change?", answered without a model: git says which commits changed it, the index says which
/// chats those commits and those edits came from.
public struct WhyReport: Equatable, Sendable {
    public struct Change: Equatable, Sendable {
        public var hit: IndexHit
        /// The commits in the file's history that carry this request's work.
        public var commits: [FileCommit]
        /// True when the line asked about was last changed by one of them.
        public var blamed: Bool
    }

    public var path: String
    public var line: Int?
    /// Requests that changed the file, newest first.
    public var changes: [Change]
    /// Requests that only read or mentioned it.
    public var references: [IndexHit]
    /// Commits to the file that no recorded chat made: a person's own, or an agent whose chat wasn't captured.
    public var unexplained: [FileCommit]
    /// The commit that last changed the line asked about.
    public var blamedCommit: FileCommit?
}

public struct HistoryQuery {
    public let index: HistoryIndex
    public let git: GitFacts
    /// The checkout to ask git about; nil when asking from outside one.
    public let root: String?

    public init(index: HistoryIndex, git: GitFacts = GitFacts(), root: String?) {
        self.index = index
        self.git = git
        self.root = root
    }

    public func why(path: String, line: Int? = nil) throws -> WhyReport {
        let history = root.map { git.history(of: path, in: $0) } ?? []
        // The file's earlier names count too: chats before a rename indexed it under the old one.
        var names = [path]
        for commit in history where !names.contains(commit.path) { names.append(commit.path) }
        let hits = try index.requests(touching: names, changesOnly: false)
        var changes = hits.filter { $0.how?.changes == true }.map { WhyReport.Change(hit: $0, commits: [], blamed: false) }
        let references = hits.filter { $0.how?.changes != true }

        let blamedSHA = line.flatMap { line in root.flatMap { git.blame(path, line: line, in: $0) } }
        var unexplained: [FileCommit] = []
        var blamedCommit: FileCommit?
        for commit in history {
            let isBlamed = blamedSHA.map { commit.sha.hasPrefix($0) || $0.hasPrefix(commit.sha) } ?? false
            if isBlamed { blamedCommit = commit }
            let makers = try index.requests(makingCommit: commit.sha)
            if makers.isEmpty {
                unexplained.append(commit)
                continue
            }
            let chats = Set(makers.map(\.chat.key))
            var attached = false
            for position in changes.indices where chats.contains(changes[position].hit.chat.key) {
                let card = changes[position].hit.card
                // A card lists the commits that carry its work: made during the request, or later in the same chat
                // with one of the files it changed.
                guard card.commits.contains(commit.sha) else { continue }
                changes[position].commits.append(commit)
                if isBlamed { changes[position].blamed = true }
                attached = true
            }
            if !attached {
                // The chat committed the file without an edit Ambient could see (a script, a merge): show the request
                // the commit was made in.
                for maker in makers {
                    var hit = maker
                    hit.how = .shell
                    if let position = changes.firstIndex(where: { $0.hit.chat.key == hit.chat.key && $0.hit.card.episode == hit.card.episode }) {
                        changes[position].commits.append(commit)
                        if isBlamed { changes[position].blamed = true }
                    } else {
                        changes.append(.init(hit: hit, commits: [commit], blamed: isBlamed))
                    }
                }
            }
        }
        changes.sort { Self.date($0.hit) > Self.date($1.hit) }
        return WhyReport(path: path, line: line, changes: changes, references: references, unexplained: unexplained,
                         blamedCommit: blamedCommit)
    }

    static func date(_ hit: IndexHit) -> Date { hit.card.at ?? hit.chat.session.startedAt }

    /// Cards for a question, the likeliest first: requests that changed a file the question names, then cards whose
    /// words match it, then requests that only referred to those files.
    public func retrieve(_ question: String, files: [String] = [], limit: Int = 12) throws -> [IndexHit] {
        let known = try index.knownPaths()
        let finder = PathFinder(roots: root.map { [$0] } ?? [], home: NSHomeDirectory(), known: known)
        var named = files
        for path in finder.paths(in: question, from: root) where !named.contains(path) { named.append(path) }
        var result: [IndexHit] = []
        var seen = Set<String>()
        func add(_ hits: [IndexHit], upTo count: Int) {
            for hit in hits where result.count < count && seen.insert("\(hit.chat.key)#\(hit.card.episode)").inserted {
                result.append(hit)
            }
        }
        let touching = try index.requests(touching: named, changesOnly: false)
        add(touching.filter { $0.how?.changes == true }, upTo: max(1, limit * 2 / 3))
        add(try index.search(question, limit: limit), upTo: limit)
        add(touching.filter { $0.how?.changes != true }, upTo: limit)
        return result
    }
}
