import Foundation

/// The name a session has in its agent's own UI: the chat title in Claude's desktop app or the latest
/// custom title in a Claude Code transcript, or the thread name in Codex. Reads only; ids from hooks are
/// validated before they become part of a path.
public struct SessionTitles: Sendable {
    public static let maxLength = 60

    let userHome: URL

    public init(userHome: URL) {
        self.userHome = userHome
    }

    public func title(for s: Session) -> String? {
        let raw: String?
        switch s.agent {
        case .claude: raw = desktopTitle(s.host?.hostSessionId) ?? transcriptTitle(s.sessionId)
        case .codex: raw = codexThreadName(s.sessionId)
        case .gemini, .antigravity, .cursor, .copilot, .opencode, .custom: raw = nil
        }
        guard let raw else { return nil }
        let title = Trim.truncate(raw, max: Self.maxLength)
        return title.isEmpty ? nil : title
    }

    /// Optional short excerpt from a local transcript store for LLM summarization.
    /// Only called when the user opts into transcript reading. Truncated; never uploads.
    public func excerpt(for s: Session, maxChars: Int = 1800) -> String? {
        switch s.agent {
        case .claude:
            return claudeExcerpt(s.sessionId, maxChars: maxChars)
        case .codex:
            // Codex thread name is metadata-only; full rolls stay out unless Ambient gains a safe reader.
            return codexThreadName(s.sessionId).map { "thread_name: \($0)" }
        default:
            return nil
        }
    }

    private func claudeExcerpt(_ id: String, maxChars: Int) -> String? {
        guard Self.matches(id, "^[A-Za-z0-9-]{1,64}$") else { return nil }
        for project in Self.directories(in: userHome.appendingPathComponent(".claude/projects", isDirectory: true)) {
            let file = project.appendingPathComponent(id + ".jsonl")
            guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { continue }
            var snippets: [String] = []
            var from = data.startIndex
            let needle = Data(#""type":"assistant""#.utf8)
            let userNeedle = Data(#""type":"user""#.utf8)
            while from < data.endIndex, snippets.count < 6 {
                let nextAssistant = data.range(of: needle, in: from..<data.endIndex)
                let nextUser = data.range(of: userNeedle, in: from..<data.endIndex)
                let hit: Range<Data.Index>?
                if let a = nextAssistant, let u = nextUser {
                    hit = a.lowerBound < u.lowerBound ? a : u
                } else {
                    hit = nextAssistant ?? nextUser
                }
                guard let hit else { break }
                let start = data[..<hit.lowerBound].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
                let end = data[hit.upperBound...].firstIndex(of: 0x0A) ?? data.endIndex
                if let object = try? JSONSerialization.jsonObject(with: data[start..<end]) as? [String: Any] {
                    if let text = Self.messageText(object) {
                        snippets.append(Trim.truncate(text, max: 280))
                    }
                }
                from = end
            }
            if !snippets.isEmpty {
                return Trim.truncate(snippets.suffix(4).joined(separator: "\n---\n"), max: maxChars)
            }
        }
        return nil
    }

    private static func messageText(_ object: [String: Any]) -> String? {
        if let message = object["message"] as? [String: Any] {
            if let content = message["content"] as? String { return content }
            if let parts = message["content"] as? [[String: Any]] {
                let texts = parts.compactMap { $0["text"] as? String }
                if !texts.isEmpty { return texts.joined(separator: " ") }
            }
        }
        return object["text"] as? String
    }

    /// Claude's desktop app keeps a file per Code session: claude-code-sessions/<account>/<org>/<local_id>.json.
    func desktopTitle(_ id: String?) -> String? {
        guard let id, Self.matches(id, "^local_[A-Za-z0-9-]{1,64}$") else { return nil }
        let root = userHome.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
        for account in Self.directories(in: root) {
            for org in Self.directories(in: account) {
                guard let data = try? Data(contentsOf: org.appendingPathComponent(id + ".json")),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                return object["title"] as? String
            }
        }
        return nil
    }

    /// Claude Code transcripts: ~/.claude/projects/<project>/<session id>.jsonl, named by their latest custom title.
    func transcriptTitle(_ id: String) -> String? {
        guard Self.matches(id, "^[A-Za-z0-9-]{1,64}$") else { return nil }
        for project in Self.directories(in: userHome.appendingPathComponent(".claude/projects", isDirectory: true)) {
            let file = project.appendingPathComponent(id + ".jsonl")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            return Self.lastValue(in: file, marker: #""type":"custom-title""#, key: "customTitle") {
                $0["type"] as? String == "custom-title"
            }
        }
        return nil
    }

    /// Codex appends a line to ~/.codex/session_index.jsonl whenever a thread is named or renamed.
    func codexThreadName(_ id: String) -> String? {
        guard Self.matches(id, "^[A-Za-z0-9-]{1,64}$") else { return nil }
        let file = userHome.appendingPathComponent(".codex/session_index.jsonl")
        return Self.lastValue(in: file, marker: "\"\(id)\"", key: "thread_name") { $0["id"] as? String == id }
    }

    /// The value of `key` in the last JSON line that contains `marker` and passes `accept`. The file is mapped,
    /// not read, and only lines containing the marker are parsed, so large transcripts stay cheap.
    static func lastValue(in file: URL, marker: String, key: String, accept: ([String: Any]) -> Bool) -> String? {
        guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else { return nil }
        let needle = Data(marker.utf8)
        var found: String?
        var from = data.startIndex
        while from < data.endIndex, let hit = data.range(of: needle, in: from..<data.endIndex) {
            let start = data[..<hit.lowerBound].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
            let end = data[hit.upperBound...].firstIndex(of: 0x0A) ?? data.endIndex
            if let object = try? JSONSerialization.jsonObject(with: data[start..<end]) as? [String: Any],
               accept(object), let value = object[key] as? String {
                found = value
            }
            from = end
        }
        return found
    }

    private static func directories(in url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }
}
