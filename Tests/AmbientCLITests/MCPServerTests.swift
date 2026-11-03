@testable import AmbientCore
import Foundation
import Testing
@testable import ambient

/// Stands in for Ambient.app: answers every request with `reply` and keeps what it was sent.
private final class FakeApp: @unchecked Sendable {
    var reply: WireMessage?
    var sent: [WireMessage] = []

    init(reply: WireMessage? = nil) { self.reply = reply }

    var server: MCPServer {
        let request: (WireMessage) -> WireMessage? = { self.sent.append($0); return self.reply }
        let paths = AmbientPaths(userHome: FileManager.default.temporaryDirectory)
        return MCPServer(request: request, memory: MemoryClient(paths: paths, request: request))
    }
}

private func object(_ line: String?) throws -> [String: Any] {
    let text = try #require(line)
    return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

private func call(_ name: String, _ arguments: [String: Any], id: Int = 1) throws -> String {
    let message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": "tools/call",
                                  "params": ["name": name, "arguments": arguments]]
    return String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)
}

/// The text and error flag of a tools/call reply.
private func toolResult(_ line: String?) throws -> (text: String, isError: Bool) {
    let result = try #require(try object(line)["result"] as? [String: Any])
    let content = try #require((result["content"] as? [[String: Any]])?.first)
    return (try #require(content["text"] as? String), try #require(result["isError"] as? Bool))
}

private let readyReport = TaskModelReport(
    config: TaskLLMConfig(enabled: true, modelPath: "/models/qwen"),
    model: LocalModelPath(requested: "/models/qwen", resolved: "/models/qwen", format: .mlxText, note: nil),
    resolution: .ready(.mlx(path: "/models/qwen", vision: false, python: "/app/python3")))

@Suite struct MCPProtocolTests {
    @Test func initializeAgreesOnAVersion() throws {
        let server = FakeApp().server
        let known = try object(server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#))
        #expect((known["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-03-26")
        let unknown = try object(server.handle(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#))
        #expect((unknown["result"] as? [String: Any])?["protocolVersion"] as? String == MCPServer.protocolVersions[0])
    }

    @Test func notificationsGetNoReply() {
        #expect(FakeApp().server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func badMessagesGetErrors() throws {
        let server = FakeApp().server
        let parse = try object(server.handle("{"))["error"] as? [String: Any]
        #expect(parse?["code"] as? Int == -32700)
        let invalid = try object(server.handle("42"))["error"] as? [String: Any]
        #expect(invalid?["code"] as? Int == -32600)
        let unknown = try object(server.handle(#"{"jsonrpc":"2.0","id":3,"method":"nope"}"#))
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
        #expect(unknown["id"] as? Int == 3)
    }

    /// 2025-03-26, which the server offers, allows batches.
    @Test func batchesGetOneReplyPerRequest() throws {
        let server = FakeApp().server
        let line = try #require(server.handle("""
        [{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"},\
        {"jsonrpc":"2.0","id":2,"method":"tools/list"},7]
        """))
        let replies = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [[String: Any]])
        #expect(replies.count == 3)
        #expect(replies[0]["id"] as? Int == 1)
        #expect(replies[1]["id"] as? Int == 2)
        #expect((replies[2]["error"] as? [String: Any])?["code"] as? Int == -32600)
        #expect(server.handle(#"[{"jsonrpc":"2.0","method":"notifications/initialized"}]"#) == nil)
        #expect((try object(server.handle("[]"))["error"] as? [String: Any])?["code"] as? Int == -32600)
    }

    /// Ambient runs whatever Python the setting names, so agents can't choose it.
    @Test func setTaskModelPathTakesNoPython() throws {
        let tool = try #require(MCPServer.tools.first { $0["name"] as? String == "set_task_model_path" })
        let schema = try #require(tool["inputSchema"] as? [String: Any])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["path", "enable"])
        #expect(schema["required"] as? [String] == ["path"])
        #expect(schema["additionalProperties"] as? Bool == false)
    }
}

@Suite struct MCPTaskModelTests {
    @Test func aPathThatCantWorkNeverReachesTheApp() throws {
        let app = FakeApp(reply: .taskModelReport(readyReport))
        let result = try toolResult(app.server.handle(try call("set_task_model_path", ["path": "models/qwen"])))
        #expect(result == ("Use an absolute path.", true))
        #expect(app.sent.isEmpty)
    }

    @Test func setSendsThePathAndShowsHowTheAppRunsIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent("config.json"))
        try Data().write(to: folder.appendingPathComponent("model.safetensors"))

        let app = FakeApp(reply: .taskModelReport(readyReport))
        let result = try toolResult(app.server.handle(try call("set_task_model_path", ["path": folder.path, "enable": true])))
        #expect(app.sent == [.setTaskModel(TaskModelChange(modelPath: folder.path, enabled: true))])
        #expect(!result.isError)
        let fields = try #require(try JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: String])
        // The app's Python, not one the CLI found.
        #expect(fields["runtime"] == "/app/python3")
        #expect(fields["runs"] == "directly with mlx-lm")
    }

    @Test func getAsksTheApp() throws {
        let app = FakeApp(reply: .taskModelReport(readyReport))
        let result = try toolResult(app.server.handle(try call("get_task_model", [:])))
        #expect(app.sent == [.taskModelRequest])
        #expect(!result.isError && result.text.contains("\"status\" : \"Local LLM ready\""))
    }

    /// A report worked out with the CLI's own PATH says so, since the app's may find other runtimes.
    @Test func aReportTheCLIMadeSaysSo() throws {
        let app = FakeApp(reply: .taskModel(TaskLLMConfig(mcpURL: "http://127.0.0.1:9/mcp", modelPath: "/nonexistent/qwen")))
        let result = try toolResult(app.server.handle(try call("get_task_model", [:])))
        let fields = try #require(try JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: String])
        #expect(fields["status"] == "Nothing at /nonexistent/qwen.")
        #expect(fields["note"]?.contains("how the CLI would") == true)
        #expect(MCPServer.report(from: .taskModelReport(readyReport))?.note == nil)
    }

    @Test func saysWhenTheAppIsntThereOrSlow() throws {
        let closed = try toolResult(FakeApp().server.handle(try call("get_task_model", [:])))
        #expect(closed == ("Ambient isn't running. Open Ambient.app, then try again.", true))
        let busy = FakeApp(reply: .taskModelTimedOut)
        let slow = try toolResult(busy.server.handle(try call("set_task_model_path", ["path": ""])))
        #expect(slow.isError && slow.text.hasPrefix("Ambient didn't confirm the change in time."))
    }
}

@Suite struct TaskModelArgumentTests {
    @Test func readsEachOption() throws {
        let parsed = try #require(Commands.parseTaskModel(["/models/qwen", "--enable", "--json"]))
        #expect(parsed.change == TaskModelChange(modelPath: "/models/qwen", enabled: true))
        #expect(parsed.json)
        #expect(Commands.parseTaskModel(["--clear", "--disable"])?.change == TaskModelChange(modelPath: "", enabled: false))
        #expect(Commands.parseTaskModel([])?.change == TaskModelChange())
    }

    @Test func refusesWhatItCantRead() {
        #expect(Commands.parseTaskModel(["--python"]) == nil)
        #expect(Commands.parseTaskModel(["/a", "/b"]) == nil)
        #expect(Commands.parseTaskModel(["--fast"]) == nil)
    }

    @Test func pythonMustBeAnExecutableFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-cli-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(Commands.problem(with: TaskModelChange(pythonPath: folder.path))
            == "No executable Python at \(folder.path). Nothing changed.")
        #expect(Commands.problem(with: TaskModelChange(pythonPath: "/bin/sh")) == nil)
        #expect(Commands.problem(with: TaskModelChange(pythonPath: "")) == nil)
        #expect(Commands.problem(with: TaskModelChange(modelPath: "relative/model")) == "Use an absolute path.")
    }
}
