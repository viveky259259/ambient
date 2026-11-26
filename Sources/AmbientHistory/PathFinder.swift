import Foundation

/// Turns the ways a chat names a file (absolute, relative to wherever the agent was, inside another worktree, a bare
/// file name) into one path relative to the repository's root, so every chat indexes the same file under one name.
public struct PathFinder: Sendable {
    /// A file as a chat named it, placed: which checkout it is in, and its one name.
    public struct Located: Equatable, Sendable {
        /// The checkout the file is in, when it is in one that still exists.
        public var root: String?
        /// Relative to the repository's root; a path outside it starts with `~/` or `/`.
        public var path: String
    }

    /// The roots of the repository's checkouts, longest first: the chat's own, then its other worktrees.
    let roots: [String]
    let home: String
    /// Tracked files, relative to the root. Empty when there is no repository to ask.
    let known: Set<String>
    private let byName: [String: [String]]
    private let exists: @Sendable (String) -> Bool

    /// - Parameter exists: whether a folder is on disk. Tests replace it.
    public init(roots: [String], home: String, known: Set<String>,
                exists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.roots = roots.map(Self.standard).sorted { $0.count > $1.count }
        self.home = Self.standard(home)
        self.known = known
        self.exists = exists
        var names: [String: [String]] = [:]
        for path in known { names[(path as NSString).lastPathComponent, default: []].append(path) }
        byName = names
    }

    /// A path with `.`, `..` and doubled slashes worked out, by its text alone. Nothing is looked up on disk: a chat
    /// names files that have since been deleted, and those must come out the same way as ones that still exist.
    static func standard(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(part)
        }
        // macOS keeps /var, /tmp and /etc under /private, and tools report either spelling.
        if parts.count >= 2, parts[0] == "private", ["var", "tmp", "etc"].contains(parts[1]) { parts.removeFirst() }
        return (path.hasPrefix("/") ? "/" : "") + parts.joined(separator: "/")
    }

    /// The one name for a path as an agent wrote it. `folder` is where the agent was working.
    public func relative(_ path: String, from folder: String?) -> String {
        locate(path, from: folder).path
    }

    /// Where a path as an agent wrote it is, and its one name.
    public func locate(_ path: String, from folder: String?) -> Located {
        var full = path
        if full == "~" || full.hasPrefix("~/") {
            full = home + full.dropFirst(1)
        } else if !full.hasPrefix("/") {
            full = (folder ?? roots.last ?? "/") + "/" + full
        }
        full = Self.standard(full)
        for root in roots where full.hasPrefix(root + "/") {
            let inside = String(full.dropFirst(root.count + 1))
            // A worktree that was removed sat inside this checkout's folder: its files are the repository's own,
            // not files of this checkout called ".claude/worktrees/x/Sources/…".
            if !known.isEmpty, !known.contains(inside), let tail = goneCheckoutTail(of: full) {
                return Located(root: nil, path: tail)
            }
            return Located(root: root, path: inside)
        }
        if let tail = goneCheckoutTail(of: full) { return Located(root: nil, path: tail) }
        if full.hasPrefix(home + "/") { return Located(root: nil, path: "~/" + full.dropFirst(home.count + 1)) }
        return Located(root: nil, path: full)
    }

    /// The tracked file a path names when it points into a checkout of this repository that is gone: a folder that
    /// no longer exists, inside one of the repository's checkouts or beside one, where worktrees are made. A folder
    /// that still exists and isn't one of the repository's checkouts is another project, and a file in it is never
    /// taken for this repository's file of the same name.
    private func goneCheckoutTail(of path: String) -> String? {
        guard !known.isEmpty else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return nil }
        for split in 1..<parts.count {
            let tail = parts[split...].joined(separator: "/")
            guard known.contains(tail) else { continue }
            let prefix = "/" + parts[..<split].joined(separator: "/")
            let parent = (prefix as NSString).deletingLastPathComponent
            let placed = roots.contains { prefix.hasPrefix($0 + "/") || ($0 as NSString).deletingLastPathComponent == parent }
            if placed, !exists(prefix) { return tail }
        }
        return nil
    }

    private static let token = try? NSRegularExpression(pattern: "[A-Za-z0-9_@+~./-]{3,300}")

    /// The repository files named in free text or a shell command, in the order they first appear.
    public func paths(in text: String, from folder: String?) -> [String] {
        located(in: text, from: folder).map(\.path)
    }

    /// The same, each with the checkout it was named in.
    public func located(in text: String, from folder: String?) -> [Located] {
        guard let token = Self.token, !text.isEmpty else { return [] }
        // Scanning megabytes of pasted output buys nothing: what names files comes early.
        let scanned = text.count > 200_000 ? String(text.prefix(200_000)) : text
        var found: [Located] = []
        var seen = Set<String>()
        let range = NSRange(scanned.startIndex..., in: scanned)
        for match in token.matches(in: scanned, range: range) {
            guard let r = Range(match.range, in: scanned) else { continue }
            var candidate = String(scanned[r])
            // A trailing "." from a sentence.
            while let last = candidate.last, ".,-/".contains(last) { candidate.removeLast() }
            guard candidate.count >= 3, candidate.contains(".") || candidate.contains("/"),
                  candidate.contains(where: \.isLetter), let place = resolve(candidate, from: folder),
                  seen.insert(place.path).inserted else { continue }
            found.append(place)
        }
        return found
    }

    private func resolve(_ candidate: String, from folder: String?) -> Located? {
        if known.isEmpty {
            // No repository to check against: take only what looks unmistakably like a file in a folder.
            guard candidate.range(of: "^~?/?[A-Za-z0-9_@+.-]+(/[A-Za-z0-9_@+.-]+)+\\.[A-Za-z0-9]{1,8}$",
                                  options: .regularExpression) != nil else { return nil }
            return locate(candidate, from: folder)
        }
        if candidate.contains("/") {
            let direct = locate(candidate, from: folder)
            if known.contains(direct.path) { return direct }
            guard !candidate.hasPrefix("/"), !candidate.hasPrefix("~") else { return nil }
            // Given from the repository's root while working in a subfolder, or with a diff header's "a/" or "b/".
            let fromRoot = folder.map { locate($0 + "/x", from: nil).root } ?? nil
            if known.contains(candidate) { return Located(root: fromRoot, path: candidate) }
            if candidate.hasPrefix("a/") || candidate.hasPrefix("b/"), known.contains(String(candidate.dropFirst(2))) {
                return Located(root: fromRoot, path: String(candidate.dropFirst(2)))
            }
            return nil
        }
        // A bare file name counts when exactly one tracked file has it.
        guard candidate.count >= 5, (candidate as NSString).pathExtension.count > 0,
              let matches = byName[candidate], matches.count == 1 else { return nil }
        return Located(root: folder.map { locate($0 + "/x", from: nil).root } ?? nil, path: matches[0])
    }

    private static let harmlessRedirects = try? NSRegularExpression(
        pattern: "[0-9]?>&[0-9-]|&?[0-9]?>>?\\s*/dev/null|2>>?\\s*\\S+")
    /// Commands that change files in place, wherever in the command the files are named.
    private static let rewriteSigns: [NSRegularExpression] = [
        "(^|[\\s;&|(])sed\\s+(-[A-Za-z]+\\s+)*-[A-Za-z]*i",
        "(^|[\\s;&|(])perl\\s+(-[A-Za-z]+\\s+)*-[A-Za-z]*i",
        "(^|[\\s;&|(])(tee|mv|cp|rm|touch|patch|truncate|install|rsync|swift-format|swiftformat)\\s",
        "(^|[\\s;&|(])git\\s+(apply|restore|checkout\\s+(--|\\.)|mv|rm|stash\\s+(pop|apply)|merge|cherry-pick|revert|am|reset\\s+--hard)",
        "\\.write\\(|write_text\\(|writeFileSync|\\.replace\\(",
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }
    private static let redirect = try? NSRegularExpression(
        pattern: "(?<![-=<>0-9&|])>>?\\s*(\"[^\"\\n]+\"|'[^'\\n]+'|[A-Za-z0-9_./~$][^\\s;&|)<>]*)")

    /// What a shell command writes to.
    public enum Writing: Equatable, Sendable {
        /// It only reads.
        case nothing
        /// It changes files in place (`sed -i`, a script that writes, `mv`…): any file it names may be one of them.
        case anything
        /// It writes only what it redirects its output to. Everything else it names, it reads.
        case only([String])
    }

    public static func writing(_ command: String) -> Writing {
        var text = command
        if let harmlessRedirects {
            text = harmlessRedirects.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                              withTemplate: " ")
        }
        let range = NSRange(text.startIndex..., in: text)
        if rewriteSigns.contains(where: { $0.firstMatch(in: text, range: range) != nil }) { return .anything }
        let targets = (redirect?.matches(in: text, range: range) ?? []).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            return text[r].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return targets.isEmpty ? .nothing : .only(targets)
    }

    /// True when a shell command looks like it changes files, not only reads them.
    public static func writes(_ command: String) -> Bool {
        writing(command) != .nothing
    }

    private static let commitSign = try? NSRegularExpression(
        pattern: "(^|[\\s;&|(])git\\s+(-[A-Za-z]\\s+\\S+\\s+)*(commit|merge|pull|cherry-pick|revert|am|rebase)\\b",
        options: [.anchorsMatchLines])

    private static let mergeSign = try? NSRegularExpression(
        pattern: "(^|[\\s;&|(])git\\s+(-[A-Za-z]\\s+\\S+\\s+)*(merge|pull)\\b", options: [.anchorsMatchLines])

    /// True when a shell command merges one branch into another.
    public static func merges(_ command: String) -> Bool {
        mergeSign?.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil
    }

    /// True when a shell command could have made a commit.
    public static func commits(_ command: String) -> Bool {
        commitSign?.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil
    }
}
