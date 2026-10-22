import Foundation

/// On-device few-shot pack that teaches the local board summarizer better titles/summaries.
///
/// Written once by `ambient task skill-bootstrap` (Anthropic), then loaded by the local LLM path only.
/// Lives at `~/.ambient/task-skill.json` (0600). Never contains API keys.
public struct TaskSkillPack: Equatable, Sendable, Codable {
    public var version: Int
    public var createdAt: Date
    /// Human-readable provenance, e.g. `anthropic-bootstrap` or `bundled-seed`.
    public var source: String
    /// Short style rules injected ahead of session facts.
    public var hints: [String]
    /// Labeled session → board examples for few-shot prompting.
    public var examples: [Example]

    public struct Example: Equatable, Sendable, Codable {
        public var facts: String
        public var title: String
        public var summary: String
        public var status: String

        public init(facts: String, title: String, summary: String, status: String) {
            self.facts = facts
            self.title = title
            self.summary = summary
            self.status = status
        }
    }

    public init(version: Int = 1,
                createdAt: Date = Date(),
                source: String,
                hints: [String] = [],
                examples: [Example] = []) {
        self.version = version
        self.createdAt = createdAt
        self.source = source
        self.hints = hints
        self.examples = examples
    }

    /// Tiny built-in seed so local summaries improve even before bootstrap.
    public static let bundledSeed = TaskSkillPack(
        version: 1,
        createdAt: Date(timeIntervalSince1970: 0),
        source: "bundled-seed",
        hints: [
            "Title: verb + object, ≤50 chars, no agent brand names.",
            "Summary: one plain sentence, ≤12 words, no quotes.",
            "status must be backlog|inProgress|blocked|done|cancelled.",
            "Prefer blocked when the agent waits on the user.",
        ],
        examples: [
            .init(
                facts: """
                agent: Codex
                project: ambient
                mood: Needs permission
                activity: Waiting — Approve shell?
                title: fix board race
                """,
                title: "Unblock board LLM race",
                summary: "Codex waits for shell approval to finish the fix.",
                status: "blocked"
            ),
            .init(
                facts: """
                agent: Claude
                project: ocean-platform
                mood: Working
                activity: Editing files
                transcript_excerpt:
                Implementing OAuth callback and refresh token rotation.
                """,
                title: "Ship OAuth refresh flow",
                summary: "Implementing callback and token rotation.",
                status: "inProgress"
            ),
            .init(
                facts: """
                agent: Cursor
                project: local-agents
                mood: Done
                activity: Idle
                title: docs for MCP
                """,
                title: "Document local MCP gateway",
                summary: "Finished the local-model MCP guide.",
                status: "done"
            ),
            .init(
                facts: """
                agent: Gemini
                project: site
                mood: Error
                activity: Failed — build
                """,
                title: "Fix site build failure",
                summary: "Build failed; needs a retry or fix.",
                status: "blocked"
            ),
        ]
    )

    /// Prompt fragment for the local summarizer (hints + a few examples).
    public func promptFragment(maxExamples: Int = 4) -> String {
        var parts: [String] = []
        if !hints.isEmpty {
            parts.append("Style rules:")
            for h in hints.prefix(6) {
                parts.append("- \(h)")
            }
        }
        let samples = Array(examples.prefix(maxExamples))
        if !samples.isEmpty {
            parts.append("Examples (match this shape; do not copy facts):")
            for (i, ex) in samples.enumerated() {
                parts.append("Example \(i + 1) facts:")
                parts.append(ex.facts)
                parts.append("Example \(i + 1) JSON:")
                parts.append(#"{"title":"\#(escapeJSON(ex.title))","summary":"\#(escapeJSON(ex.summary))","status":"\#(escapeJSON(ex.status))"}"#)
            }
        }
        return parts.joined(separator: "\n")
    }

    private func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

/// Load / save `task-skill.json` under Ambient home.
public enum TaskSkillStore {
    public static func url(paths: AmbientPaths = .current()) -> URL {
        paths.taskSkill
    }

    public static func load(paths: AmbientPaths = .current()) -> TaskSkillPack {
        let url = paths.taskSkill
        guard let data = try? Data(contentsOf: url),
              let pack = try? decoder.decode(TaskSkillPack.self, from: data),
              !pack.examples.isEmpty else {
            return .bundledSeed
        }
        return pack
    }

    public static func exists(paths: AmbientPaths = .current()) -> Bool {
        FileManager.default.fileExists(atPath: paths.taskSkill.path)
    }

    public static func save(_ pack: TaskSkillPack, paths: AmbientPaths = .current()) throws {
        try paths.ensureHome()
        let data = try encoder.encode(pack)
        let url = paths.taskSkill
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
