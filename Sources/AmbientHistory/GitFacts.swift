import Foundation

/// What git knows about the folder a chat worked in. Git is the record of what happened; the chat only explains it.
public struct GitFacts: Sendable {
    public let shell: Shell

    public init(shell: Shell = .system) {
        self.shell = shell
    }

    private func git(_ arguments: [String], in folder: String) -> String? {
        let output = shell("git", arguments, in: folder)
        return output.succeeded ? output.stdout : nil
    }

    /// The checkout's root for a folder inside it: a worktree's own root, not the main checkout's.
    public func root(of folder: String) -> String? {
        guard FileManager.default.fileExists(atPath: folder) else { return nil }
        return git(["rev-parse", "--show-toplevel"], in: folder).map(Self.trimmed).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// "owner/name" from the `origin` remote, for any host; nil without one.
    public func slug(of root: String) -> String? {
        git(["remote", "get-url", "origin"], in: root).flatMap { Self.slug(fromRemote: Self.trimmed($0)) }
    }

    /// `git@github.com:owner/name.git`, `https://github.com/owner/name`, `ssh://git@host:22/owner/name.git`.
    static func slug(fromRemote url: String) -> String? {
        var rest = url
        if let scheme = rest.range(of: "://") {
            rest = String(rest[scheme.upperBound...])
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            rest = String(rest[rest.index(after: slash)...])
        } else if let colon = rest.firstIndex(of: ":") {
            rest = String(rest[rest.index(after: colon)...])
        } else {
            return nil
        }
        if rest.hasSuffix(".git") { rest = String(rest.dropLast(4)) }
        let parts = rest.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let slug = parts.suffix(2).joined(separator: "/")
        return slug.range(of: "^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", options: .regularExpression) == nil ? nil : slug
    }

    public func branch(of root: String) -> String? {
        git(["branch", "--show-current"], in: root).map(Self.trimmed).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The name git would put on a commit made here now: `user.name`, or whatever git falls back to without one.
    public func developer(of root: String) -> String? {
        guard let ident = git(["var", "GIT_AUTHOR_IDENT"], in: root), let end = ident.range(of: " <") else { return nil }
        let name = Self.trimmed(String(ident[..<end.lowerBound]))
        return name.isEmpty ? nil : name
    }

    /// Every tracked file, relative to the root.
    public func trackedFiles(in root: String) -> Set<String> {
        guard let output = git(["ls-files", "-z"], in: root) else { return [] }
        return Set(output.split(separator: "\0").map(String.init))
    }

    /// Commits on any branch whose committer time is within the window, oldest first, each with the files it changed.
    /// A merge lists what it changed against its first parent.
    public func commits(in root: String, from: Date, to: Date) -> [ChatCommit] {
        guard let output = git(["-c", "core.quotePath=false", "log", "--all", "--diff-merges=first-parent",
                                "--name-only", "--since=@\(Int(from.timeIntervalSince1970.rounded(.down)))",
                                "--until=@\(Int(to.timeIntervalSince1970.rounded(.up)))",
                                "--format=%x1e%H%x1f%ct%x1f%s"], in: root) else { return [] }
        var commits: [ChatCommit] = []
        for record in output.split(separator: "\u{1e}") {
            let lines = record.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let header = lines.first else { continue }
            let fields = header.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, let seconds = TimeInterval(fields[1]), fields[0].count >= 40 else { continue }
            commits.append(ChatCommit(sha: fields[0], subject: fields[2], at: Date(timeIntervalSince1970: seconds),
                                      files: Array(lines.dropFirst())))
        }
        return commits.sorted { ($0.at, $0.sha) < ($1.at, $1.sha) }
    }

    /// The merge commits, on any branch, whose committer time is within the window.
    public func merges(in root: String, from: Date, to: Date) -> Set<String> {
        guard let output = git(["log", "--all", "--merges", "--since=@\(Int(from.timeIntervalSince1970.rounded(.down)))",
                                "--until=@\(Int(to.timeIntervalSince1970.rounded(.up)))", "--format=%H"], in: root)
        else { return [] }
        return Set(output.split(separator: "\n").map { Self.trimmed(String($0)) }.filter { !$0.isEmpty })
    }

    /// What `files` differ from `HEAD` by right now, including ones git doesn't track yet. Empty when nothing does.
    public func uncommitted(_ files: [String], in root: String, limit: Int = 200_000) -> String {
        guard !files.isEmpty else { return "" }
        var parts: [String] = []
        // Asked for in batches: a chat can touch more files than fit on one command line.
        for batch in stride(from: 0, to: files.count, by: 200).map({ Array(files[$0..<min($0 + 200, files.count)]) }) {
            if let diff = git(["diff", "HEAD", "--no-color", "--"] + batch, in: root), !diff.isEmpty {
                parts.append(diff)
            }
            let untracked = git(["ls-files", "-z", "--others", "--exclude-standard", "--"] + batch, in: root) ?? ""
            for file in untracked.split(separator: "\0").map(String.init) {
                // Exits 1 because the two differ, which is the point.
                let diff = shell("git", ["diff", "--no-color", "--no-index", "--", "/dev/null", file], in: root).stdout
                if !diff.isEmpty { parts.append(diff) }
            }
        }
        let joined = parts.map { $0.hasSuffix("\n") ? $0 : $0 + "\n" }.joined()
        guard joined.count > limit else { return joined }
        return String(joined.prefix(limit)) + "\n… [\(joined.count - limit) more characters cut]\n"
    }

    /// Commits that changed a file, newest first, following renames.
    public func history(of path: String, in root: String, limit: Int = 50) -> [FileCommit] {
        let format = "%x1e%H%x1f%ct%x1f%an%x1f%s"
        guard let output = git(["-c", "core.quotePath=false", "log", "--follow", "-n", "\(limit)", "--name-only",
                                "--format=\(format)", "--", path], in: root) else { return [] }
        var commits: [FileCommit] = []
        for record in output.split(separator: "\u{1e}") {
            let lines = record.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let header = lines.first else { continue }
            let fields = header.split(separator: "\u{1f}", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, let seconds = TimeInterval(fields[1]) else { continue }
            commits.append(FileCommit(sha: fields[0], at: Date(timeIntervalSince1970: seconds), author: fields[2],
                                      subject: fields[3], path: lines.dropFirst().first ?? path))
        }
        return commits
    }

    /// The commit that last changed a line, or nil when the line doesn't exist or isn't committed yet.
    public func blame(_ path: String, line: Int, in root: String) -> String? {
        guard line > 0, let output = git(["blame", "-L", "\(line),\(line)", "--porcelain", "--", path], in: root),
              let sha = output.split(separator: " ").first.map(String.init), sha.count >= 40,
              sha.contains(where: { $0 != "0" }) else { return nil }
        return sha
    }

    /// A commit's change to one file, for showing next to what the chat said about it.
    public func patch(of sha: String, path: String, in root: String, limit: Int = 12_000) -> String {
        let output = git(["show", "--diff-merges=first-parent", "--no-color", "--format=", sha, "--", path], in: root) ?? ""
        return output.count > limit ? String(output.prefix(limit)) + "\n… [cut]\n" : output
    }

    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A commit as one file's history shows it.
public struct FileCommit: Equatable, Sendable {
    public var sha: String
    public var at: Date
    public var author: String
    public var subject: String
    /// What the file was called in this commit.
    public var path: String

    public init(sha: String, at: Date, author: String, subject: String, path: String) {
        self.sha = sha
        self.at = at
        self.author = author
        self.subject = subject
        self.path = path
    }
}
