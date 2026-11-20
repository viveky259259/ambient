import Foundation

/// A chat as its agent left it on disk, before paths are made relative, secrets blanked or events numbered.
public struct RawChat: Sendable {
    public struct Event: Sendable {
        public var at: Date?
        public var kind: ChatEvent.Kind
        public var actor: String?
        public var text: String
        public var tool: String?
        public var label: String?
        public var diff: String?
        /// Files the tool was pointed at, as the agent wrote them: absolute, or relative to `folder`.
        public var paths: [FileTouch] = []
        /// The agent's id for a tool call, and for a result the call it answers.
        public var callID: String?
        public var failed = false
        /// The folder the agent was working in when this happened.
        public var folder: String?

        public init(at: Date? = nil, kind: ChatEvent.Kind, actor: String? = nil, text: String, tool: String? = nil,
                    label: String? = nil, diff: String? = nil, paths: [FileTouch] = [], callID: String? = nil,
                    failed: Bool = false, folder: String? = nil) {
            self.at = at
            self.kind = kind
            self.actor = actor
            self.text = text
            self.tool = tool
            self.label = label
            self.diff = diff
            self.paths = paths
            self.callID = callID
            self.failed = failed
            self.folder = folder
        }
    }

    public var sessionID: String
    public var agent: String
    public var title: String?
    /// The folder the chat started in.
    public var folder: String?
    public var branch: String?
    public var events: [Event]
    /// Pull requests the agent's harness recorded for the chat, as ("owner/name", number).
    public var pullRequests: [PullRequest]

    public struct PullRequest: Equatable, Hashable, Sendable {
        public var repo: String
        public var number: Int
    }

    public var startedAt: Date? { events.lazy.compactMap(\.at).first }
    public var endedAt: Date? { events.reversed().lazy.compactMap(\.at).first }
}

/// A transcript file found on disk.
public struct TranscriptFile: Equatable, Sendable {
    public var sessionID: String
    public var path: String
    public var modified: Date
    public var size: Int
}

/// Reads Claude Code's transcripts: one JSON object per line in `~/.claude/projects/<folder>/<session>.jsonl`, with
/// each subagent's own lines in `<session>/subagents/`.
public enum ClaudeTranscript {
    /// How much of one tool result is read at all, half from each end. Results are cut much shorter once secrets are
    /// blanked; reading this much first keeps a secret that the cut would split well inside what is thrown away.
    static let resultLimit = 12_000

    public static func projects(home: String) -> String { home + "/.claude/projects" }

    /// The transcript for a session, wherever its project folder is.
    public static func find(sessionID: String, home: String) -> String? {
        guard sessionID.range(of: "^[A-Za-z0-9_-]{6,80}$", options: .regularExpression) != nil else { return nil }
        let root = projects(home: home)
        guard let folders = try? FileManager.default.contentsOfDirectory(atPath: root) else { return nil }
        for folder in folders.sorted() {
            let path = "\(root)/\(folder)/\(sessionID).jsonl"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    /// Every session transcript on this machine.
    public static func all(home: String) -> [TranscriptFile] {
        let root = projects(home: home)
        let fm = FileManager.default
        var files: [TranscriptFile] = []
        for folder in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            for name in (try? fm.contentsOfDirectory(atPath: "\(root)/\(folder)")) ?? [] where name.hasSuffix(".jsonl") {
                let path = "\(root)/\(folder)/\(name)"
                guard let attributes = try? fm.attributesOfItem(atPath: path),
                      let modified = attributes[.modificationDate] as? Date,
                      let size = (attributes[.size] as? NSNumber)?.intValue else { continue }
                files.append(TranscriptFile(sessionID: String(name.dropLast(6)), path: path, modified: modified, size: size))
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    public static func read(path: String) throws -> RawChat {
        let sessionID = String((path as NSString).lastPathComponent.dropLast(6))
        var reader = Reader()
        var chat = RawChat(sessionID: sessionID, agent: "claude", title: nil, folder: nil, branch: nil, events: [],
                           pullRequests: [])
        let main = try reader.read(path: path, actor: nil)
        chat.title = main.title
        chat.folder = main.firstFolder
        chat.branch = main.branch
        chat.pullRequests = main.pullRequests
        chat.events = main.events

        // Each subagent's events go right after the call that started it, so they fall inside the same request.
        let folder = String(path.dropLast(6)) + "/subagents"
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            .filter { $0.hasSuffix(".jsonl") }.sorted()
        var parts: [(events: [RawChat.Event], callID: String?)] = []
        for name in names {
            let meta = Self.object(atPath: "\(folder)/\(name.dropLast(6)).meta.json")
            let actor = (meta?["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? String(name.dropLast(6))
            let sub = try reader.read(path: "\(folder)/\(name)", actor: actor)
            if !sub.events.isEmpty { parts.append((sub.events, meta?["toolUseId"] as? String)) }
        }
        // Later subagents are placed first, so two started by one message keep their order.
        for part in parts.sorted(by: { ($0.events.first?.at ?? .distantPast) > ($1.events.first?.at ?? .distantPast) }) {
            chat.events.insert(contentsOf: part.events, at: Self.place(part.events, callID: part.callID, in: chat.events))
        }
        return chat
    }

    /// Where a subagent's events belong among the main ones: after its call's result, or its call, or by time.
    private static func place(_ events: [RawChat.Event], callID: String?, in main: [RawChat.Event]) -> Int {
        if let callID {
            if let result = main.firstIndex(where: { $0.kind == .result && $0.callID == callID && $0.actor == nil }) {
                return result + 1
            }
            if let call = main.firstIndex(where: { $0.kind == .tool && $0.callID == callID && $0.actor == nil }) {
                return call + 1
            }
        }
        guard let start = events.first?.at else { return main.count }
        return main.firstIndex { ($0.at ?? .distantPast) > start && $0.actor == nil } ?? main.count
    }

    private static func object(atPath path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Text a harness puts in the user's turn. None of it is something the person typed.
    static let injectedPrefixes = [
        "<task-notification>", "<ci-monitor-event>", "<side-sessions-event>", "<system-reminder>", "<local-command",
        "<command-name>", "<command-message>", "<agent-message", "This session is being continued",
        "[Request interrupted", "Another Claude session sent", "Caveat: The messages below",
        "The app was quit while you were working",
    ]

    static func isInjected(_ text: String) -> Bool {
        let start = text.drop { $0 == " " || $0 == "\n" }
        return injectedPrefixes.contains { start.hasPrefix($0) }
    }

    struct Parsed {
        var events: [RawChat.Event] = []
        var title: String?
        var firstFolder: String?
        var branch: String?
        var pullRequests: [RawChat.PullRequest] = []
    }

    /// Keeps which lines it has seen across files: a forked subagent's file can repeat its parent's.
    struct Reader {
        private var seen = Set<String>()
        private let dates: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        private let plainDates = ISO8601DateFormatter()

        mutating func read(path: String, actor: String?) throws -> Parsed {
            guard let data = FileManager.default.contents(atPath: path) else {
                throw HistoryError.message("Can't read the transcript at \(path).")
            }
            var parsed = Parsed()
            var folder: String?
            // Edits carry their exact patch on the result line, keyed by the call it answers.
            var patches: [String: String] = [:]
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
                if let cwd = object["cwd"] as? String, !cwd.isEmpty {
                    folder = cwd
                    if parsed.firstFolder == nil { parsed.firstFolder = cwd }
                }
                if let branch = object["gitBranch"] as? String, !branch.isEmpty, branch != "HEAD" { parsed.branch = branch }
                switch object["type"] as? String {
                case "custom-title":
                    if let title = object["customTitle"] as? String, !title.isEmpty { parsed.title = title }
                case "pr-link":
                    if let repo = object["prRepository"] as? String, let number = object["prNumber"] as? Int {
                        let link = RawChat.PullRequest(repo: repo, number: number)
                        if !parsed.pullRequests.contains(link) { parsed.pullRequests.append(link) }
                    }
                case "user", "assistant":
                    // An older layout kept subagents' lines in the main file; they're read from their own files now.
                    if actor == nil, object["isSidechain"] as? Bool == true { continue }
                    if let uuid = object["uuid"] as? String, !seen.insert(uuid).inserted { continue }
                    guard let message = object["message"] as? [String: Any] else { continue }
                    let at = (object["timestamp"] as? String).flatMap { dates.date(from: $0) ?? plainDates.date(from: $0) }
                    if let result = object["toolUseResult"] as? [String: Any],
                       let hunks = result["structuredPatch"] as? [[String: Any]], !hunks.isEmpty,
                       let blocks = message["content"] as? [[String: Any]] {
                        for block in blocks where block["type"] as? String == "tool_result" {
                            if let id = block["tool_use_id"] as? String { patches[id] = Self.unified(hunks) }
                        }
                    }
                    let fromPerson = object["type"] as? String == "user" && actor == nil
                        && object["isMeta"] as? Bool != true && object["isCompactSummary"] as? Bool != true
                        && ((object["origin"] as? [String: Any])?["kind"] as? String ?? "human") == "human"
                    parsed.events += Self.events(in: message, role: object["type"] as? String ?? "", at: at,
                                                 actor: actor, folder: folder, fromPerson: fromPerson)
                default:
                    continue
                }
            }
            for index in parsed.events.indices where parsed.events[index].kind == .tool {
                if let id = parsed.events[index].callID, let patch = patches[id], parsed.events[index].tool != "Write" {
                    parsed.events[index].diff = patch
                }
            }
            return parsed
        }

        private static func events(in message: [String: Any], role: String, at: Date?, actor: String?,
                                   folder: String?, fromPerson: Bool) -> [RawChat.Event] {
            let blocks: [[String: Any]]
            if let text = message["content"] as? String {
                blocks = [["type": "text", "text": text]]
            } else {
                blocks = message["content"] as? [[String: Any]] ?? []
            }
            var events: [RawChat.Event] = []
            for block in blocks {
                switch block["type"] as? String {
                case "text":
                    guard let text = block["text"] as? String,
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    let kind: ChatEvent.Kind = role == "assistant" ? .agent
                        : (fromPerson && !ClaudeTranscript.isInjected(text) ? .user : .system)
                    events.append(.init(at: at, kind: kind, actor: actor, text: text, folder: folder))
                case "thinking":
                    guard let text = block["thinking"] as? String,
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    events.append(.init(at: at, kind: .thinking, actor: actor, text: text, folder: folder))
                case "tool_use":
                    var event = toolCall(name: block["name"] as? String ?? "tool",
                                         input: block["input"] as? [String: Any] ?? [:])
                    event.at = at
                    event.actor = actor
                    event.callID = block["id"] as? String
                    event.folder = folder
                    events.append(event)
                case "tool_result":
                    var text = resultText(block["content"])
                    if text.count > ClaudeTranscript.resultLimit {
                        let half = ClaudeTranscript.resultLimit / 2
                        text = String(text.prefix(half)) + "\n…\n" + String(text.suffix(half))
                    }
                    events.append(.init(at: at, kind: .result, actor: actor, text: text,
                                        callID: block["tool_use_id"] as? String,
                                        failed: block["is_error"] as? Bool == true, folder: folder))
                default:
                    continue
                }
            }
            return events
        }

        private static func resultText(_ content: Any?) -> String {
            if let text = content as? String { return text }
            guard let blocks = content as? [[String: Any]] else { return "" }
            return blocks.map { block in
                (block["text"] as? String) ?? "[\(block["type"] as? String ?? "content")]"
            }.joined(separator: "\n")
        }

        static func toolCall(name: String, input: [String: Any]) -> RawChat.Event {
            func string(_ key: String) -> String? { (input[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
            switch name {
            case "Bash":
                return .init(kind: .tool, text: string("command") ?? "", tool: name, label: string("description"))
            case "Edit":
                let path = string("file_path") ?? ""
                return .init(kind: .tool, text: path, tool: name,
                             diff: replaced(string("old_string") ?? "", with: string("new_string") ?? ""),
                             paths: path.isEmpty ? [] : [FileTouch(path: path, how: .edit)])
            case "MultiEdit":
                let path = string("file_path") ?? ""
                let edits = input["edits"] as? [[String: Any]] ?? []
                let diff = edits.map {
                    replaced($0["old_string"] as? String ?? "", with: $0["new_string"] as? String ?? "")
                }.joined(separator: "\n")
                return .init(kind: .tool, text: path, tool: name, diff: diff,
                             paths: path.isEmpty ? [] : [FileTouch(path: path, how: .edit)])
            case "Write":
                let path = string("file_path") ?? ""
                return .init(kind: .tool, text: path, tool: name, diff: added(string("content") ?? ""),
                             paths: path.isEmpty ? [] : [FileTouch(path: path, how: .write)])
            case "NotebookEdit":
                let path = string("notebook_path") ?? ""
                return .init(kind: .tool, text: path, tool: name, diff: added(string("new_source") ?? ""),
                             paths: path.isEmpty ? [] : [FileTouch(path: path, how: .edit)])
            case "Read":
                let path = string("file_path") ?? ""
                return .init(kind: .tool, text: path, tool: name,
                             paths: path.isEmpty ? [] : [FileTouch(path: path, how: .read)])
            case "Agent", "Task":
                let text = [string("description"), string("prompt")].compactMap { $0 }.joined(separator: "\n\n")
                return .init(kind: .tool, text: text, tool: name)
            default:
                let data = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes]))
                    ?? Data("{}".utf8)
                return .init(kind: .tool, text: String(decoding: data, as: UTF8.self), tool: name)
            }
        }

        /// Claude's own hunks, as unified-diff text.
        static func unified(_ hunks: [[String: Any]]) -> String {
            hunks.map { hunk in
                let header = "@@ -\(hunk["oldStart"] as? Int ?? 0),\(hunk["oldLines"] as? Int ?? 0) "
                    + "+\(hunk["newStart"] as? Int ?? 0),\(hunk["newLines"] as? Int ?? 0) @@"
                return ([header] + (hunk["lines"] as? [String] ?? [])).joined(separator: "\n")
            }.joined(separator: "\n")
        }

        /// What an edit took out and put in, when the transcript has no patch for it.
        static func replaced(_ old: String, with new: String) -> String {
            let removed = old.isEmpty ? [] : old.components(separatedBy: "\n").map { "-" + $0 }
            let inserted = new.isEmpty ? [] : new.components(separatedBy: "\n").map { "+" + $0 }
            return (removed + inserted).joined(separator: "\n")
        }

        static func added(_ content: String) -> String {
            var lines = content.components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }
            return lines.map { "+" + $0 }.joined(separator: "\n")
        }
    }
}
