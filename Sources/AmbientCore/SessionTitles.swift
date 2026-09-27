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
        case .gemini: raw = nil
        }
        guard let raw else { return nil }
        let title = Trim.truncate(raw, max: Self.maxLength)
        return title.isEmpty ? nil : title
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
