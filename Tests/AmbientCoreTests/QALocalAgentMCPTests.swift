import Foundation
import Testing
@testable import AmbientCore

/// LocalAgentMCP against a stub gateway: the handshake, how tool results are decoded, and every way a call fails.
@Suite struct QALocalAgentMCPTests {
    typealias G = QAStubGateway

    @Test func handshakeRunsOnceAndReusesTheSessionID() async throws {
        let gateway = G.standard(sessionID: "abc") { _, _, id in G.toolJSON(id, ["ok": true]) }
        let mcp = gateway.mcp()
        try await mcp.ensureSession()
        try await mcp.ensureSession()
        _ = try await mcp.callTool(name: "list_models")
        let methods = gateway.calls.map(\.method)
        #expect(methods == ["initialize", "notifications/initialized", "tools/call"])
        // The first request has no session; every later one carries the one the gateway gave.
        #expect(gateway.calls[0].headers["Mcp-Session-Id"] == nil)
        #expect(gateway.calls[1].headers["Mcp-Session-Id"] == "abc")
        #expect(gateway.calls[2].headers["Mcp-Session-Id"] == "abc")
        #expect(gateway.calls[0].params["protocolVersion"] as? String == "2025-03-26")
        #expect((gateway.calls[0].params["clientInfo"] as? [String: Any])?["name"] as? String == "ambient")
    }

    @Test func requestsAskForJSONOrEventStream() async throws {
        let gateway = G.standard { _, _, id in G.toolJSON(id, [:]) }
        _ = try await gateway.mcp().callTool(name: "x")
        let headers = try #require(gateway.calls.last?.headers)
        #expect(headers["Accept"] == "application/json, text/event-stream")
        #expect(headers["Content-Type"] == "application/json")
    }

    @Test func toolArgumentsAreSent() async throws {
        let gateway = G.standard { _, _, id in G.toolJSON(id, [:]) }
        _ = try await gateway.mcp().callTool(name: "get_job", arguments: ["job_id": "j1"])
        // callTool opens the session first; the tool call comes after the handshake.
        let call = try #require(gateway.calls.first { $0.method == "tools/call" })
        #expect(call.params["name"] as? String == "get_job")
        #expect((call.params["arguments"] as? [String: Any])?["job_id"] as? String == "j1")
    }

    @Test func singleJSONTextIsDecoded() async throws {
        let gateway = G.standard { _, _, id in G.toolJSON(id, ["models": [["id": "m"]]]) }
        let result = try await gateway.mcp().callTool(name: "list_models") as? [String: Any]
        #expect((result?["models"] as? [[String: Any]])?.first?["id"] as? String == "m")
    }

    @Test func singlePlainTextComesBackAsAString() async throws {
        let gateway = G.standard { _, _, id in G.result(id, ["content": [["type": "text", "text": "hello there"]]]) }
        let result = try await gateway.mcp().callTool(name: "x")
        #expect(result as? String == "hello there")
    }

    @Test func severalTextsComeBackAsAnArray() async throws {
        let gateway = G.standard { _, _, id in
            G.result(id, ["content": [["type": "text", "text": "a"], ["type": "text", "text": "b"]]])
        }
        let result = try await gateway.mcp().callTool(name: "x")
        #expect(result as? [String] == ["a", "b"])
    }

    @Test func noTextReturnsTheWholeResult() async throws {
        let gateway = G.standard { _, _, id in G.result(id, ["content": [], "structured": 7]) }
        let result = try await gateway.mcp().callTool(name: "x") as? [String: Any]
        #expect(result?["structured"] as? Int == 7)
    }

    @Test func nonObjectResultIsReturnedAsIs() async throws {
        let gateway = G.standard { _, _, id in G.result(id, [1, 2, 3]) }
        let result = try await gateway.mcp().callTool(name: "x")
        #expect(result as? [Int] == [1, 2, 3])
    }

    @Test func toolErrorThrowsItsText() async throws {
        let gateway = G.standard { _, _, id in
            G.result(id, ["isError": true, "content": [["type": "text", "text": "model not found"]]])
        }
        await #expect(throws: LocalAgentMCP.MCPError.rpc("model not found")) {
            _ = try await gateway.mcp().callTool(name: "x")
        }
    }

    @Test func toolErrorWithoutTextNamesTheTool() async throws {
        let gateway = G.standard { _, _, id in G.result(id, ["isError": true]) }
        await #expect(throws: LocalAgentMCP.MCPError.rpc("Tool load failed.")) {
            _ = try await gateway.mcp().callTool(name: "load")
        }
    }

    @Test func rpcErrorThrowsItsMessage() async throws {
        let gateway = G { _, _, id in G.sse(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": -1, "message": "nope"]]) }
        await #expect(throws: LocalAgentMCP.MCPError.rpc("nope")) { try await gateway.mcp().ensureSession() }
    }

    @Test func rpcErrorWithoutMessageHasADefault() async throws {
        let gateway = G { _, _, id in G.sse(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": -1]]) }
        await #expect(throws: LocalAgentMCP.MCPError.rpc("MCP error")) { try await gateway.mcp().ensureSession() }
    }

    @Test func missingResultIsADecodeError() async throws {
        let gateway = G { _, _, id in G.sse(["jsonrpc": "2.0", "id": id ?? NSNull()]) }
        await #expect(throws: LocalAgentMCP.MCPError.decode("Missing result for initialize")) {
            try await gateway.mcp().ensureSession()
        }
    }

    @Test(arguments: [400, 401, 404, 500, 503])
    func nonSuccessStatusThrowsHTTP(code: Int) async throws {
        let gateway = G { _, _, _ in .init(status: code, body: Data("oops".utf8)) }
        await #expect(throws: LocalAgentMCP.MCPError.http(code)) { try await gateway.mcp().ensureSession() }
    }

    @Test func emptyBodyForARequestIsMissingItsResult() async throws {
        let gateway = G { _, _, _ in .init(status: 200) }
        await #expect(throws: LocalAgentMCP.MCPError.decode("Missing result for initialize")) {
            try await gateway.mcp().ensureSession()
        }
    }

    @Test func unreadableBodyIsADecodeError() async throws {
        let gateway = G { _, _, _ in .init(status: 200, body: Data("<html>not mcp</html>".utf8)) }
        await #expect(throws: LocalAgentMCP.MCPError.decode("<html>not mcp</html>")) {
            try await gateway.mcp().ensureSession()
        }
    }

    @Test func rawJSONRepliesAreAccepted() async throws {
        let gateway = G { method, _, id in
            if method == "notifications/initialized" { return .init(status: 202) }
            let json = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": [:]])
            return .init(status: 200, headers: ["Content-Type": "application/json"], body: json)
        }
        try await gateway.mcp().ensureSession()
        #expect(gateway.calls.count == 2)
    }

    @Test func transportFailureNamesTheHost() async throws {
        let gateway = G { _, _, _ in .init(error: URLError(.networkConnectionLost)) }
        do {
            try await gateway.mcp().ensureSession()
            Issue.record("expected a transport error")
        } catch let LocalAgentMCP.MCPError.transport(message) {
            #expect(message.hasPrefix("Couldn't reach local-agent at 127.0.0.1"))
        }
    }

    @Test func unregisteredGatewayIsUnreachable() async throws {
        let mcp = LocalAgentMCP(config: .init(url: URL(string: "http://127.0.0.1:9/mcp")!), session: G.session())
        await #expect(throws: LocalAgentMCP.MCPError.self) { try await mcp.ensureSession() }
    }

    @Test(arguments: ["http://example.com/mcp", "https://10.0.0.5:5051/mcp", "ftp://127.0.0.1/mcp", "file:///tmp/mcp"])
    func nonLoopbackURLsAreRefusedBeforeAnyRequest(url: String) async throws {
        let mcp = LocalAgentMCP(config: .init(url: URL(string: url)!), session: G.session())
        await #expect(throws: LocalAgentMCP.MCPError.nonLoopback) { try await mcp.ensureSession() }
    }

    @Test func requestIDsIncrease() async throws {
        var ids: [Int] = []
        let lock = NSLock()
        let gateway = G.standard { _, _, id in
            lock.lock(); ids.append(id as? Int ?? -1); lock.unlock()
            return G.toolJSON(id, [:])
        }
        let mcp = gateway.mcp()
        _ = try await mcp.callTool(name: "a")
        _ = try await mcp.callTool(name: "b")
        #expect(ids.count == 2)
        #expect(ids[1] == ids[0] + 1)
    }

    @Test func defaultConfigIsLoopback() {
        let config = LocalAgentMCP.Config()
        #expect(config.url.absoluteString == "http://127.0.0.1:5051/mcp")
        #expect(config.requestTimeout == 30)
        #expect(config.url.isLoopback)
    }

    @Test func errorDescriptions() {
        typealias E = LocalAgentMCP.MCPError
        #expect(E.badURL.description == "Local-agent MCP URL is invalid.")
        #expect(E.nonLoopback.description.contains("loopback"))
        #expect(E.http(502).description == "Local-agent MCP returned HTTP 502.")
        #expect(E.transport("t").description == "t")
        #expect(E.rpc("r").description == "r")
        #expect(E.decode("d").description == "Couldn't read the MCP reply: d")
        #expect(E.decode("d").errorDescription == E.decode("d").description)
    }
}

@Suite struct QASSEParseTests {
    @Test func firstDataLineWins() {
        let body = Data("data: {\"a\":1}\ndata: {\"a\":2}\n".utf8)
        #expect(LocalAgentMCP.parseSSE(body)?["a"] as? Int == 1)
    }

    @Test func skipsCommentsAndUnparseableDataLines() {
        let body = Data(": keepalive\nevent: message\ndata: not json\ndata:{\"b\":true}\n".utf8)
        #expect(LocalAgentMCP.parseSSE(body)?["b"] as? Bool == true)
    }

    @Test func handlesCRLF() {
        let body = Data("event: message\r\ndata: {\"c\":3}\r\n\r\n".utf8)
        #expect(LocalAgentMCP.parseSSE(body)?["c"] as? Int == 3)
    }

    @Test func fallsBackToRawJSON() {
        #expect(LocalAgentMCP.parseSSE(Data(#"{"raw":"yes"}"#.utf8))?["raw"] as? String == "yes")
    }

    @Test(arguments: ["", "event: ping\n", "[1,2]", "data: [1]\n", "garbage"])
    func nothingUsableIsNil(text: String) {
        #expect(LocalAgentMCP.parseSSE(Data(text.utf8)) == nil)
    }
}
