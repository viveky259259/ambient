import Foundation
import Testing
@testable import AmbientCore

/// The formats that cross a process boundary or outlive one: the files in `~/.ambient`, the CLI↔app socket, and the
/// lines the `ambient-remote` shim writes.
@Suite struct FormatFixtureTests {
    // MARK: Files

    @Test func stateFile() throws {
        let cursors = [Samples.machine.id: Samples.cursor]
        let written = try writing { try StateFile.save(Samples.sessions, cursors: cursors, to: $0) }
        try Fixture.check("StateFile.v1.json", matches: written)
        #expect(StateFile.load(from: Fixture.url("StateFile.v1.json")) == Samples.sessions)
        #expect(StateFile.loadCursors(from: Fixture.url("StateFile.v1.json")) == cursors)
    }

    @Test func taskFile() throws {
        let written = try writing { try TaskFile.save(Samples.tasks, to: $0) }
        try Fixture.check("TaskFile.v1.json", matches: written)
        #expect(TaskFile.load(from: Fixture.url("TaskFile.v1.json")) == Samples.tasks)
    }

    @Test func dayLogFile() throws {
        let written = try writing { try DayLogFile.save(Samples.day, to: $0) }
        try Fixture.check("DayLogFile.v1.json", matches: written)
        #expect(DayLogFile.load(from: Fixture.url("DayLogFile.v1.json")) == Samples.day)
    }

    // MARK: The CLI↔app socket

    /// One line per message. `taskModelReport` and the memory replies that carry entries get theirs when LocalAgent
    /// and Memory become modules of their own.
    @Test func wireMessages() throws {
        let messages: [WireMessage] = [
            .event(Samples.event), .event(Samples.customEvent), .statusRequest,
            .status(sessions: Samples.sessions, mood: .waiting), .acknowledgeAll, .open(query: "ambient"),
            .open(query: nil), .opened(sessionID: "claude:s-1"), .opened(sessionID: nil), .listTasks,
            .tasks(Samples.tasks), .upsertTask(Samples.task), .upsertTaskResult(Samples.manualTask), .openTask("task-1"),
            .taskModelRequest,
            .setTaskModel(TaskModelChange(modelPath: "/Volumes/Models/qwen", pythonPath: nil, enabled: true)),
            .taskModel(TaskLLMConfig(enabled: true, mcpURL: "http://127.0.0.1:5051/mcp", modelID: "hf:qwen",
                                     modelPath: "", pythonPath: "/usr/bin/python3", readTranscripts: false,
                                     modelsVolumePath: "/Volumes/Models", minRefreshSeconds: 45)),
            .taskModelTimedOut,
            .memory(.write(MemoryWrite(key: "plan", scope: .project("/Users/me/ambient"), value: "phase 1",
                                       description: "Where we are", ttlMinutes: 60, untilSessionEnds: true),
                           callerPids: [501, 77])),
            .memory(.read(key: "plan", project: "/Users/me/ambient", scope: nil)),
            .memory(.list(project: "/Users/me/ambient", scope: .global)),
            .memory(.forget(key: "plan", project: "/Users/me/ambient", scope: .project("/Users/me/ambient"))),
            .memoryReply(.entries([])), .memoryReply(.failed("No such key")), .ping, .pong(version: "0.8.0"),
            .permissionRequest(PermissionAsk(id: "ask-1", event: Samples.event, toolName: "Bash", hint: "swift test")),
            .permissionAnswer(.allow), .permissionAnswer(.deny), .permissionAnswer(.ask),
        ]
        let written = try messages.map { try Wire.encode($0).dropLast() }.map { Data($0) }
        let fixture = try Fixture.checkLines("WireMessage.v1.jsonl", match: written)
        for (line, message) in zip(fixture, messages) {
            #expect(try Wire.decode(line) == message)
        }
    }

    // MARK: Remote lines

    /// The shim writes these by hand (`Resources/ambient-remote`), so the fixture is the source: one line per kind,
    /// in the shim's own field order, and the event each one must decode to.
    @Test func remoteEventLines() throws {
        let id = "0123456789abcdef0123456789abcdef"
        let ts = Date(timeIntervalSince1970: 1_763_000_000)
        func event(_ seq: Int64, _ kind: RemoteEvent.Kind, project: String? = "ambient", tool: String? = nil,
                   title: String? = nil, reason: String? = nil, message: String? = nil) -> RemoteEvent {
            RemoteEvent(v: 1, seq: seq, id: id, ts: ts, agent: .claude, session: "s-1", kind: kind, project: project,
                        tool: tool, title: title, reason: reason, message: message)
        }
        let expected: [RemoteEvent] = [
            event(1, .sessionStarted), event(2, .promptSubmitted, message: "Write the fixtures"),
            event(3, .toolStarted, tool: "Bash"), event(4, .toolFinished, tool: "Bash"),
            event(5, .toolFailed, tool: "Bash", message: "exit 1"),
            event(6, .needsInput, tool: "Bash", reason: "permission", message: "swift test"),
            event(7, .needsInput, reason: "question", message: "Which branch?"), event(8, .compactStarted),
            event(9, .compactFinished), event(10, .subagentStarted), event(11, .subagentFinished),
            event(12, .turnCompleted, message: "Done"), event(13, .turnFailed, message: "Overloaded"),
            event(14, .sessionEnded), event(15, .notice, project: nil, message: "Hello"),
            event(16, .titleChanged, project: nil, title: "Write fixtures"), event(17, .agentExited),
        ]
        #expect(Set(expected.map(\.kind)) == Set(RemoteEvent.Kind.allCases), "one line per kind")
        let lines = try Fixture.lines("RemoteEvent.v1.jsonl")
        #expect(lines.count == expected.count)
        for (line, want) in zip(lines, expected) {
            #expect(try RemoteEventDecoder.decode(line) == want)
        }
    }

    /// The bytes a save writes, through a temporary file.
    private func writing(_ save: (URL) throws -> Void) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try save(url)
        return try Data(contentsOf: url)
    }
}
