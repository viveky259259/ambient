import Foundation

/// Turns the ways a chat names a file (absolute, relative to wherever the agent was, inside another worktree, a bare
/// file name) into one path relative to the repository's root, so every chat indexes the same file under one name.
public struct PathFinder: Sendable {
    /// The roots of the repository's checkouts, longest first: the chat's own, then its other worktrees.
    let roots: [String]
    let home: String
    /// Tracked files, relative to the root. Empty when there is no repository to ask.
    let known: Set<String>
    private let byName: [String: [String]]

    public init(roots: [String], home: String, known: Set<String>) {
        self.roots = roots.map(Self.standard).sorted { $0.count > $1.count }
        self.home = Self.standard(home)
        self.known = known
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
        var full = path
        if full == "~" || full.hasPrefix("~/") {
            full = home + full.dropFirst(1)
        } else if !full.hasPrefix("/") {
            full = (folder ?? roots.last ?? "/") + "/" + full
        }
        full = Self.standard(full)
        for root in roots where full.hasPrefix(root + "/") {
            return String(full.dropFirst(root.count + 1))
        }
        // A checkout that's gone, or a sibling clone: the longest tail that is a tracked file names the same file.
        if let tail = knownTail(of: full) { return tail }
        if full.hasPrefix(home + "/") { return "~/" + full.dropFirst(home.count + 1) }
        return full
    }

    private func knownTail(of path: String) -> String? {
        guard !known.isEmpty else { return nil }
        var parts = path.split(separator: "/").map(String.init)
        while parts.count > 1 {
            parts.removeFirst()
            let tail = parts.joined(separator: "/")
            if known.contains(tail) { return tail }
        }
        return nil
    }

    private static let token = try? NSRegularExpression(pattern: "[A-Za-z0-9_@+~./-]{3,300}")

    /// The repository files named in free text or a shell command, in the order they first appear.
    public func paths(in text: String, from folder: String?) -> [String] {
        guard let token = Self.token, !text.isEmpty else { return [] }
        // Scanning megabytes of pasted output buys nothing: what names files comes early.
        let scanned = text.count > 200_000 ? String(text.prefix(200_000)) : text
        var found: [String] = []
        var seen = Set<String>()
        let range = NSRange(scanned.startIndex..., in: scanned)
        for match in token.matches(in: scanned, range: range) {
            guard let r = Range(match.range, in: scanned) else { continue }
            var candidate = String(scanned[r])
            while let last = candidate.last, ".,-/".contains(last) { candidate.removeLast() }
            // "Sources/A.swift:42" and a trailing "." from a sentence.
            guard candidate.count >= 3, candidate.contains(".") || candidate.contains("/"),
                  candidate.contains(where: \.isLetter), let path = resolve(candidate, from: folder),
                  seen.insert(path).inserted else { continue }
            found.append(path)
        }
        return found
    }

    private func resolve(_ candidate: String, from folder: String?) -> String? {
        if known.isEmpty {
            // No repository to check against: take only what looks unmistakably like a file in a folder.
            guard candidate.range(of: "^~?/?[A-Za-z0-9_@+.-]+(/[A-Za-z0-9_@+.-]+)+\\.[A-Za-z0-9]{1,8}$",
                                  options: .regularExpression) != nil else { return nil }
            return relative(candidate, from: folder)
        }
        if candidate.contains("/") {
            let direct = relative(candidate, from: folder)
            if known.contains(direct) { return direct }
            // "a/Sources/X.swift" from a diff header, or a path given from the repository's root while elsewhere.
            return knownTail(of: "/" + candidate) ?? (known.contains(candidate) ? candidate : nil)
        }
        // A bare file name counts when exactly one tracked file has it.
        guard candidate.count >= 5, (candidate as NSString).pathExtension.count > 0,
              let matches = byName[candidate], matches.count == 1 else { return nil }
        return matches[0]
    }

    private static let harmlessRedirects = try? NSRegularExpression(
        pattern: "[0-9]?>&[0-9-]|&?[0-9]?>>?\\s*/dev/null|2>>?\\s*\\S+")
    private static let writeSigns: [NSRegularExpression] = [
        "(^|[\\s;&|(])sed\\s+(-[A-Za-z]+\\s+)*-[A-Za-z]*i",
        "(^|[\\s;&|(])perl\\s+(-[A-Za-z]+\\s+)*-[A-Za-z]*i",
        "(^|[\\s;&|(])(tee|mv|cp|rm|touch|patch|truncate|install|rsync|swift-format|swiftformat)\\s",
        "(^|[\\s;&|(])git\\s+(apply|restore|checkout\\s+(--|\\.)|mv|rm|stash\\s+(pop|apply)|merge|cherry-pick|revert|am|reset\\s+--hard)",
        "\\.write\\(|write_text\\(|writeFileSync|\\.replace\\(",
        "(?<![-=<>0-9&|])>>?\\s*[A-Za-z0-9_./~\"'$]",
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }

    /// True when a shell command looks like it changes files, not only reads them.
    public static func writes(_ command: String) -> Bool {
        var text = command
        if let harmlessRedirects {
            text = harmlessRedirects.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                              withTemplate: " ")
        }
        let range = NSRange(text.startIndex..., in: text)
        return writeSigns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    private static let commitSign = try? NSRegularExpression(
        pattern: "(^|[\\s;&|(])git\\s+(-[A-Za-z]\\s+\\S+\\s+)*(commit|merge|cherry-pick|revert|am|rebase)\\b",
        options: [.anchorsMatchLines])

    /// True when a shell command could have made a commit.
    public static func commits(_ command: String) -> Bool {
        commitSign?.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil
    }
}
