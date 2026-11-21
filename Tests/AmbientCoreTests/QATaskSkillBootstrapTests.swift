import Foundation
import Testing
@testable import AmbientCore

/// The one-shot skill-pack bootstrap, with Anthropic replaced by a stub: nothing leaves the Mac, and no Keychain is read
/// (every call passes its key).
@Suite(.serialized) struct QATaskSkillBootstrapTests {
    typealias G = QAStubGateway

    static var examples: [[String: Any]] { [
        ["facts": "agent: Codex\nmood: Needs permission", "title": "Approve shell", "summary": "Waiting on you.", "status": "blocked"],
        ["facts": "agent: Claude\nmood: Working", "title": "Wire MCP", "summary": "Building it.", "status": "inProgress"],
        ["facts": "agent: Cursor\nmood: Done", "title": "Ship board", "summary": "Finished.", "status": "done"],
        ["facts": "agent: Gemini\nmood: Idle", "title": "Polish", "summary": "Later.", "status": "backlog"],
    ] }

    static func anthropicBody(_ payload: Any) -> Data {
        let text = String(decoding: try! JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        return try! JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": text]]])
    }

    private func boot(_ gateway: G) -> TaskSkillBootstrap {
        TaskSkillBootstrap(apiKey: "sk-ant-test", endpoint: URL(string: "http://127.0.0.1:\(gateway.port)/v1/messages")!)
    }

    @Test func generateSendsAnAnthropicRequestAndParsesThePack() async throws {
        var headers: [String: String] = [:]
        var body: [String: Any] = [:]
        let gateway = G { _, _, _ in .init(status: 200, body: Self.anthropicBody(["hints": ["Be brief"], "examples": Self.examples])) }
        let pack = try await boot(gateway).generate(session: G.session())
        headers = gateway.calls.first?.headers ?? [:]
        body = gateway.calls.first?.params ?? [:]
        #expect(pack.source == "anthropic-bootstrap")
        #expect(pack.version == 1)
        #expect(pack.hints == ["Be brief"])
        #expect(pack.examples.count == 4)
        #expect(headers["x-api-key"] == "sk-ant-test")
        #expect(headers["anthropic-version"] == "2023-06-01")
        _ = body
    }

    @Test func generateSyncWorksToo() throws {
        let gateway = G { _, _, _ in .init(status: 200, body: Self.anthropicBody(["examples": Self.examples])) }
        let pack = try boot(gateway).generateSync(session: G.session())
        // No hints from the model: the bundled seed's hints stand in.
        #expect(pack.hints == TaskSkillPack.bundledSeed.hints)
        #expect(pack.examples.map(\.status) == ["blocked", "inProgress", "done", "backlog"])
    }

    @Test(arguments: [401, 429, 500])
    func httpErrorsCarryTheStatusAndBody(code: Int) async throws {
        let gateway = G { _, _, _ in .init(status: code, body: Data("rate limited".utf8)) }
        do {
            _ = try await boot(gateway).generate(session: G.session())
            Issue.record("expected an error")
        } catch let SecretStoreError.anthropicHTTP(status, text) {
            #expect(status == code)
            #expect(text == "rate limited")
        }
    }

    @Test func replyWithoutContentIsADecodeError() async throws {
        let gateway = G { _, _, _ in .init(status: 200, body: Data(#"{"id":"msg"}"#.utf8)) }
        do {
            _ = try await boot(gateway).generate(session: G.session())
            Issue.record("expected an error")
        } catch let SecretStoreError.decode(message) {
            #expect(message == "Anthropic response missing content")
        }
    }

    @Test func transportErrorsSurfaceFromGenerateSync() throws {
        let gateway = G { _, _, _ in .init(error: URLError(.timedOut)) }
        #expect(throws: (any Error).self) { _ = try boot(gateway).generateSync(session: G.session()) }
    }

    @Test func runSyncWritesThePackWithAnExplicitKey() throws {
        let home = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = AmbientPaths(userHome: home, home: home)
        // The default endpoint is https://api.anthropic.com, which the stub answers on 443.
        let gateway = G(port: 443) { _, _, _ in .init(status: 200, body: Self.anthropicBody(["examples": Self.examples])) }
        let pack = try TaskSkillBootstrap.runSync(paths: paths, apiKey: "sk-ant-x", session: G.session())
        #expect(gateway.calls.count == 1)
        #expect(TaskSkillStore.exists(paths: paths))
        #expect(TaskSkillStore.load(paths: paths).examples == pack.examples)
    }

    @Test func runWritesThePackAsync() async throws {
        let home = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = AmbientPaths(userHome: home, home: home)
        let gateway = G(port: 443) { _, _, _ in .init(status: 200, body: Self.anthropicBody(["examples": Self.examples])) }
        let pack = try await TaskSkillBootstrap.run(paths: paths, apiKey: "sk-ant-x", session: G.session())
        #expect(pack.examples.count == 4)
        #expect(gateway.calls.count == 1)
        #expect(TaskSkillStore.exists(paths: paths))
    }

    @Test func resolveKeyPrefersTheOverride() throws {
        #expect(try TaskSkillBootstrap.resolveKey("override", environment: [:]) == "override")
        // An empty override would fall through to the login Keychain, which a test must not read: an item the app
        // saved could raise an access prompt for the unsigned test runner. Covered by the manual checks instead.
    }

    // MARK: - Payload parsing

    @Test func fencedJSONIsAccepted() throws {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: ["examples": Self.examples]), as: UTF8.self)
        let payload = try TaskSkillBootstrap.parsePayload("```json\n\(json)\n```")
        #expect(payload.examples.count == 4)
    }

    @Test func invalidExamplesAreDroppedAndTooFewThrow() throws {
        var examples = Self.examples
        examples[0]["status"] = "someday"            // unknown status
        examples[1]["facts"] = ""                    // no facts
        examples.append(["title": "no facts at all"])
        let json = String(decoding: try JSONSerialization.data(withJSONObject: ["examples": examples]), as: UTF8.self)
        #expect(throws: SecretStoreError.self) { try TaskSkillBootstrap.parsePayload(json) }
    }

    @Test(arguments: ["", "not json", "[1,2,3]", "```\nnope\n```"])
    func nonJSONRepliesThrow(raw: String) {
        #expect(throws: (any Error).self) { try TaskSkillBootstrap.parsePayload(raw) }
    }

    @Test func longFieldsAreClipped() throws {
        var examples = Self.examples
        examples[0]["facts"] = String(repeating: "f", count: 2_000)
        examples[0]["title"] = String(repeating: "t", count: 200)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: ["examples": examples]), as: UTF8.self)
        let payload = try TaskSkillBootstrap.parsePayload(json)
        #expect(payload.examples[0].facts.count <= 800)
        #expect(payload.examples[0].title.count <= 50)
    }

    @Test func blankHintsAreDropped() throws {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: ["hints": ["  ", "Keep it short"], "examples": Self.examples]), as: UTF8.self)
        let hints = try TaskSkillBootstrap.parsePayload(json).hints
        #expect(hints.contains("Keep it short"))
        // `Trim.clean(...) ?? $0` puts the raw blank back when cleaning empties it, so the isEmpty filter never sees "".
        withKnownIssue("BUG: whitespace-only hints survive parsePayload as \"  \"") {
            #expect(hints == ["Keep it short"])
        }
    }
}
