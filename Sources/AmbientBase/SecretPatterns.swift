import Foundation

/// The shapes of credentials Ambient recognizes in text that is about to leave an agent's own session: shared memory
/// refuses text holding one, and a chat's history has them blanked before it is stored.
public enum SecretPatterns {
    public struct Pattern: Sendable {
        public let regex: String
        /// What it is, with its article: "a GitHub token".
        public let what: String

        public init(_ regex: String, _ what: String) {
            self.regex = regex
            self.what = what
        }
    }

    public static let known: [Pattern] = [
        Pattern("-----BEGIN [A-Z ]*PRIVATE KEY-----", "a private key"),
        Pattern("\\bAKIA[0-9A-Z]{16}\\b", "an AWS access key"),
        Pattern("\\bgh[pousr]_[A-Za-z0-9]{36,}", "a GitHub token"),
        Pattern("\\bgithub_pat_[A-Za-z0-9_]{40,}", "a GitHub token"),
        Pattern("\\bglpat-[A-Za-z0-9_-]{20,}", "a GitLab token"),
        Pattern("\\bsk-ant-[A-Za-z0-9_-]{20,}", "an Anthropic API key"),
        Pattern("\\bsk-(proj-)?[A-Za-z0-9_-]{32,}", "an OpenAI API key"),
        Pattern("\\bxox[abposr]-[A-Za-z0-9-]{10,}", "a Slack token"),
        Pattern("\\bAIza[0-9A-Za-z_-]{35}\\b", "a Google API key"),
        Pattern("\\bnpm_[A-Za-z0-9]{36}\\b", "an npm token"),
    ]

    /// The first kind of secret found in `text`, or nil.
    public static func firstMatch(in text: String) -> Pattern? {
        known.first { text.range(of: $0.regex, options: .regularExpression) != nil }
    }
}
