import AmbientBase
import Foundation

/// Blanks what shouldn't leave the machine a chat ran on: credentials, and the user's home folder in paths.
///
/// A stored chat is read by a whole team, and a private bucket only limits who that is. So this runs on every piece of
/// text before anything is written.
public struct Redactor: Sendable {
    /// Shapes beyond `SecretPatterns.known`, which is tuned to refuse a short memory entry: a chat also holds command
    /// output, where secrets turn up as headers and environment assignments. Each keeps its first group (the header's
    /// or the variable's name) and blanks the rest.
    static let named: [SecretPatterns.Pattern] = [
        .init("(Bearer )[A-Za-z0-9._~+/=-]{20,}", "a bearer token"),
        .init("\\b([A-Z0-9_]{0,40}(?:SECRET|TOKEN|PASSWORD|PASSWD|API_KEY|ACCESS_KEY|PRIVATE_KEY)[A-Z0-9_]{0,40}=)"
            + "[\"']?[^\\s\"']{12,}[\"']?", "a credential"),
        .init("(://[A-Za-z0-9._%+-]{1,64}:)[^@\\s/]{6,}(?=@)", "a password in a URL"),
    ]

    static let extra: [SecretPatterns.Pattern] = [
        .init("\\beyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}", "a JSON web token"),
    ]

    private let patterns: [(regex: NSRegularExpression, replacement: String)]
    private let home: NSRegularExpression?

    /// - Parameter home: the user's home folder, written as `~` wherever it appears. Nil leaves paths alone.
    public init(home: String?) {
        func compiled(_ pattern: SecretPatterns.Pattern, keepingName: Bool) -> (NSRegularExpression, String)? {
            guard let regex = try? NSRegularExpression(pattern: pattern.regex) else { return nil }
            // The article reads badly inside brackets: "[redacted: GitHub token]".
            let what = pattern.what.replacingOccurrences(of: "^an? ", with: "", options: .regularExpression)
            let blank = NSRegularExpression.escapedTemplate(for: "[redacted: \(what)]")
            return (regex, keepingName ? "$1" + blank : blank)
        }
        patterns = (SecretPatterns.known + Self.extra).compactMap { compiled($0, keepingName: false) }
            + Self.named.compactMap { compiled($0, keepingName: true) }
        let trimmed = home.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        // Only as a whole folder name: /Users/pat, not the start of /Users/patricia.
        self.home = trimmed.flatMap { $0.count > 1 ? $0 : nil }.flatMap {
            try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: $0) + "(?![A-Za-z0-9._-])")
        }
    }

    public func clean(_ text: String) -> String {
        var result = text
        if let home {
            result = home.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                   withTemplate: "~")
        }
        for (regex, replacement) in patterns {
            // A private key runs to its END line; without one, to the end of the text it was pasted in.
            if regex.pattern.contains("PRIVATE KEY") {
                result = Self.blankPrivateKeys(in: result)
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }

    public func clean(_ text: String?) -> String? { text.map(clean) }

    private static let privateKey = try? NSRegularExpression(
        pattern: "-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(-----END [A-Z ]*PRIVATE KEY-----|\\z)",
        options: [.dotMatchesLineSeparators])

    private static func blankPrivateKeys(in text: String) -> String {
        guard let privateKey else { return text }
        return privateKey.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                   withTemplate: "[redacted: private key]")
    }
}
