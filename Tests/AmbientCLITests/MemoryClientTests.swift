@testable import AmbientCore
import Foundation
import Testing
@testable import ambient

/// Records requests and answers memory ones with `reply`.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [WireMessage] = []
    var reply: MemoryReply?
    var sent: [WireMessage] { lock.lock(); defer { lock.unlock() }; return _sent }

    init(reply: MemoryReply? = nil) { self.reply = reply }

    func client(_ paths: AmbientPaths) -> MemoryClient {
        MemoryClient(paths: paths) { message in
            self.lock.lock(); self._sent.append(message); self.lock.unlock()
            guard case .memory = message, let reply = self.reply else { return nil }
            return .memoryReply(reply)
        }
    }

    var memoryRequests: [MemoryRequest] {
        sent.compactMap { if case let .memory(r) = $0 { return r } else { return nil } }
    }
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct MemoryClientTests {
    @Test func scopeNames() throws {
        #expect(try MemoryClient.scope(nil, project: "/p") == nil)
        #expect(try MemoryClient.scope("", project: "/p") == nil)
        #expect(try MemoryClient.scope("project", project: "/p") == .project("/p"))
        #expect(try MemoryClient.scope("PROJECT", project: "/p") == .project("/p"))
        #expect(try MemoryClient.scope("Global", project: "/p") == .global)
        #expect(throws: MemoryError.self) { try MemoryClient.scope("team", project: "/p") }
    }

    @Test(arguments: [(0.0, "just now"), (59.0, "just now"), (60, "1 min ago"), (3_599, "59 min ago"), (3_600, "1 h ago"),
                      (86_399, "23 h ago"), (86_400, "1 d ago"), (10 * 86_400, "10 d ago"), (-500, "just now")] as [(Double, String)])
    func ageReadsLikeAPerson(seconds: Double, expected: String) {
        #expect(MemoryClient.age(now.addingTimeInterval(-seconds), now: now) == expected)
    }

    @Test func notRunningIsAFailure() throws {
        let home = try TempHome(); defer { home.remove() }
        let client = Recorder().client(home.paths)
        guard case let .failed(message) = client.list(scope: nil, folder: home.root.path) else {
            Issue.record("Expected a failure")
            return
        }
        #expect(message.contains("isn't running"))
    }

    @Test func listReadForgetAddressTheFoldersProject() throws {
        let home = try TempHome(); defer { home.remove() }
        let recorder = Recorder(reply: .entries([]))
        let client = recorder.client(home.paths)
        let project = MemoryProject.root(for: home.root.path)

        _ = client.list(scope: nil, folder: home.root.path)
        _ = client.read(key: "k", scope: "global", folder: home.root.path)
        _ = client.forget(key: "k", scope: "project", folder: home.root.path)
        #expect(recorder.memoryRequests == [
            .list(project: project, scope: nil),
            .read(key: "k", project: project, scope: .global),
            .forget(key: "k", project: project, scope: .project(project)),
        ])
        #expect(client.project(home.root.path) == project)
    }

    @Test func aBadScopeFailsWithoutAskingTheApp() throws {
        let home = try TempHome(); defer { home.remove() }
        let recorder = Recorder(reply: .entries([]))
        let client = recorder.client(home.paths)
        for reply in [client.list(scope: "x", folder: home.root.path), client.read(key: "k", scope: "x", folder: home.root.path),
                      client.forget(key: "k", scope: "x", folder: home.root.path),
                      client.write(key: "k", value: "v", filePath: nil, description: nil, scope: "x", ttlMinutes: nil,
                                   untilSessionEnds: false, folder: home.root.path)] {
            guard case .failed = reply else { Issue.record("Expected failure, got \(reply)"); continue }
        }
        #expect(recorder.sent.isEmpty)
    }

    @Test func writeSendsTextToTheProjectByDefault() throws {
        let home = try TempHome(); defer { home.remove() }
        let recorder = Recorder(reply: .entries([]))
        let client = recorder.client(home.paths)
        _ = client.write(key: "build-cmd", value: "swift test", filePath: nil, description: "How to test",
                         scope: nil, ttlMinutes: 30, untilSessionEnds: true, folder: home.root.path)
        guard case let .write(write, callerPids)? = recorder.memoryRequests.first else {
            Issue.record("No write sent")
            return
        }
        #expect(write.key == "build-cmd")
        #expect(write.value == "swift test")
        #expect(write.scope == .project(MemoryProject.root(for: home.root.path)))
        #expect(write.description == "How to test")
        #expect(write.ttlMinutes == 30)
        #expect(write.untilSessionEnds)
        #expect(!callerPids.isEmpty)
    }

    @Test func writeClipsLongDescriptions() throws {
        let home = try TempHome(); defer { home.remove() }
        let recorder = Recorder(reply: .entries([]))
        _ = recorder.client(home.paths).write(key: "k", value: "v", filePath: nil,
                                              description: String(repeating: "d", count: 1_000), scope: "global",
                                              ttlMinutes: nil, untilSessionEnds: false, folder: home.root.path)
        guard case let .write(write, _)? = recorder.memoryRequests.first else { Issue.record("No write"); return }
        #expect((write.description?.count ?? 0) <= MemoryStore.maxDescriptionLength)
        #expect(write.scope == .global)
    }

    @Test(arguments: ["AKIAIOSFODNN7EXAMPLE", "token ghp_" + String(repeating: "a", count: 36),
                      "-----BEGIN RSA PRIVATE KEY-----\nabc", "sk-ant-" + String(repeating: "x", count: 30)])
    func secretsAreNeverSent(value: String) throws {
        let home = try TempHome(); defer { home.remove() }
        let recorder = Recorder(reply: .entries([]))
        let reply = recorder.client(home.paths).write(key: "k", value: value, filePath: nil, description: nil, scope: nil,
                                                      ttlMinutes: nil, untilSessionEnds: false, folder: home.root.path)
        guard case let .failed(message) = reply else { Issue.record("Secret was accepted"); return }
        #expect(message.contains("secret"))
        #expect(recorder.sent.isEmpty)
    }

    @Test(arguments: ["", "   ", String(repeating: "k", count: 81)])
    func badKeysAreRefused(key: String) throws {
        let home = try TempHome(); defer { home.remove() }
        let recorder = Recorder(reply: .entries([]))
        let reply = recorder.client(home.paths).write(key: key, value: "v", filePath: nil, description: nil, scope: nil,
                                                      ttlMinutes: nil, untilSessionEnds: false, folder: home.root.path)
        guard case .failed = reply else { Issue.record("Bad key accepted"); return }
        #expect(recorder.sent.isEmpty)
    }

    @Test func fileSharesCopyIntoTheBlobStoreRelativeToTheFolder() throws {
        let home = try TempHome(); defer { home.remove() }
        try Data("report body".utf8).write(to: home.root.appendingPathComponent("report.md"))
        let recorder = Recorder(reply: .entries([]))
        _ = recorder.client(home.paths).write(key: "report", value: nil, filePath: "report.md", description: nil, scope: nil,
                                              ttlMinutes: nil, untilSessionEnds: false, folder: home.root.path)
        guard case let .write(write, _)? = recorder.memoryRequests.first, let blob = write.file else {
            Issue.record("No file write sent")
            return
        }
        #expect(blob.name == "report.md")
        #expect(blob.size == 11)
        let copy = MemoryBlobStore(root: home.paths.memoryBlobs).url(for: blob)
        #expect(try String(contentsOf: copy, encoding: .utf8) == "report body")
    }

    @Test(arguments: [".env", "id_rsa", "server.pem", "missing.txt"])
    func secretOrMissingFilesAreRefused(name: String) throws {
        let home = try TempHome(); defer { home.remove() }
        if name != "missing.txt" { try Data("x".utf8).write(to: home.root.appendingPathComponent(name)) }
        let recorder = Recorder(reply: .entries([]))
        let reply = recorder.client(home.paths).write(key: "f", value: nil, filePath: name, description: nil, scope: nil,
                                                      ttlMinutes: nil, untilSessionEnds: false, folder: home.root.path)
        guard case .failed = reply else { Issue.record("\(name) was shared"); return }
        #expect(recorder.sent.isEmpty)
    }

    @Test func fieldsCarryEverythingAnAgentNeeds() throws {
        let home = try TempHome(); defer { home.remove() }
        let client = Recorder().client(home.paths)
        let entry = MemoryEntry(key: "k", scope: .project("/src/app"), value: "hello", description: "greeting",
                                author: MemoryAuthor(sessionID: "s1", agent: .claude, label: "Claude Code"),
                                createdAt: now, updatedAt: now.addingTimeInterval(-120),
                                expiresAt: now.addingTimeInterval(3_600), untilSessionEnds: true)
        let f = client.fields(entry, now: now)
        #expect(f["key"] as? String == "k")
        #expect(f["scope"] as? String == "project")
        #expect(f["project"] as? String == "/src/app")
        #expect(f["value"] as? String == "hello")
        #expect(f["description"] as? String == "greeting")
        #expect(f["shared_by"] as? String == "Claude Code (s1)")
        #expect(f["until_session_ends"] as? Bool == true)
        #expect(f["updated"] as? String == "2 min ago")
        #expect(f["size"] as? Int == 5)
        #expect(f["expires"] != nil)
        #expect(f["file"] == nil)

        let blob = MemoryBlob(name: "a.txt", sha256: String(repeating: "0", count: 64), size: 3)
        let g = client.fields(MemoryEntry(key: "g", scope: .global, file: blob, createdAt: now, updatedAt: now), now: now)
        #expect(g["scope"] as? String == "global")
        #expect(g["project"] == nil)
        #expect(g["value"] == nil)
        #expect((g["file"] as? String)?.hasPrefix(home.paths.memoryBlobs.path) == true)
        #expect(g["until_session_ends"] == nil)
        #expect(g["expires"] == nil)
    }

    @Test func digestIsNilWhenNothingIsShared() throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(Recorder().client(home.paths).digest() == nil)
        #expect(Recorder(reply: .entries([])).client(home.paths).digest() == nil)
        #expect(Recorder(reply: .failed("no")).client(home.paths).digest() == nil)
    }

    @Test func digestListsKeysAndCountsTheRest() throws {
        let home = try TempHome(); defer { home.remove() }
        let entries = (0..<10).map { i in
            MemoryEntry(key: "key-\(i)", scope: i.isMultiple(of: 2) ? .global : .project("/p"), value: "v",
                        createdAt: now, updatedAt: now)
        }
        let digest = try #require(Recorder(reply: .entries(entries)).client(home.paths).digest(limit: 8, now: now))
        let lines = digest.split(separator: "\n")
        #expect(lines.count == 9)
        #expect(lines[0] == "- key-0 (global, text, just now)")
        #expect(lines[1] == "- key-1 (project, text, just now)")
        #expect(lines.last == "- …and 2 more; memory_list shows them all.")

        let few = try #require(Recorder(reply: .entries(Array(entries.prefix(3)))).client(home.paths).digest(now: now))
        #expect(few.split(separator: "\n").count == 3)
        #expect(!few.contains("more"))
    }
}

// MARK: - `ambient memory`

@Suite(.serialized) struct MemoryCommandTests {
    @Test(arguments: [["memory", "--ttl", "soon", "list"], ["memory", "--in"], ["memory", "--file"], ["memory", "--bogus"],
                      ["memory", "get"], ["memory", "rm"], ["memory", "frob", "k"], ["memory", "get", "a", "b"],
                      ["memory", "set"], ["memory", "set", "k", "v", "extra"], ["memory", "set", "k", "v", "--file", "f"]])
    func usageErrors(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args, paths: home.paths) == 64)
    }

    @Test(arguments: [["memory", "--help"], ["memory", "-h"]])
    func help(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args, paths: home.paths) == 0)
    }

    @Test(arguments: [["memory"], ["memory", "list"], ["memory", "get", "k"], ["memory", "rm", "k"]])
    func failsWithNoApp(args: [String]) throws {
        let home = try TempHome(); defer { home.remove() }
        #expect(runCLI(args + ["--in", home.root.path], paths: home.paths) == 1)
    }

    @Test func secretValueIsRefusedWithoutContactingTheApp() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths) { _ in .memoryReply(.entries([])) }
        defer { app.stop() }
        #expect(runCLI(["memory", "set", "aws", "AKIAIOSFODNN7EXAMPLE", "--in", home.root.path], paths: home.paths) == 1)
        #expect(app.received.isEmpty)
    }

    @Test func roundTripThroughTheApp() throws {
        let home = try TempHome(); defer { home.remove() }
        let project = MemoryProject.root(for: home.root.path)
        let entry = MemoryEntry(key: "build", scope: .project(project), value: "swift test", description: "how",
                                author: MemoryAuthor(sessionID: "s1", agent: .codex, label: "Codex"),
                                expiresAt: Date().addingTimeInterval(3_600))
        let app = try FakeAppSocket(paths: home.paths) { message in
            guard case let .memory(request) = message else { return nil }
            switch request {
            case .write: return .memoryReply(.entry(entry))
            case .read: return .memoryReply(.entry(entry))
            case .list: return .memoryReply(.entries([entry, MemoryEntry(key: "g", scope: .global, value: "x")]))
            case .forget: return .memoryReply(.forgotten(entry))
            }
        }
        defer { app.stop() }
        let folder = ["--in", home.root.path]
        #expect(runCLI(["memory", "set", "build", "swift test", "--description", "how", "--ttl", "60"] + folder, paths: home.paths) == 0)
        #expect(runCLI(["memory", "set", "build", "swift test", "--json"] + folder, paths: home.paths) == 0)
        #expect(runCLI(["memory", "get", "build"] + folder, paths: home.paths) == 0)
        #expect(runCLI(["memory", "get", "build", "--json"] + folder, paths: home.paths) == 0)
        #expect(runCLI(["memory", "ls", "--global"] + folder, paths: home.paths) == 0)
        #expect(runCLI(["memory", "list", "--json"] + folder, paths: home.paths) == 0)
        #expect(runCLI(["memory", "rm", "build", "--project"] + folder, paths: home.paths) == 0)
        #expect(runCLI(["memory", "forget", "build", "--json"] + folder, paths: home.paths) == 0)

        let requests = app.received.compactMap { m -> MemoryRequest? in if case let .memory(r) = m { return r } else { return nil } }
        #expect(requests.count == 8)
        guard case let .write(write, _) = requests[0] else { Issue.record("First wasn't a write"); return }
        #expect(write.key == "build")
        #expect(write.value == "swift test")
        #expect(write.ttlMinutes == 60)
        #expect(write.description == "how")
        #expect(requests[4] == .list(project: project, scope: .global))
        #expect(requests[6] == .forget(key: "build", project: project, scope: .project(project)))
    }

    @Test func getOfASharedFilePrintsItsPath() throws {
        let home = try TempHome(); defer { home.remove() }
        let blob = MemoryBlob(name: "a.txt", sha256: String(repeating: "1", count: 64), size: 1)
        let app = try FakeAppSocket(paths: home.paths) { _ in .memoryReply(.entry(MemoryEntry(key: "f", scope: .global, file: blob))) }
        defer { app.stop() }
        #expect(runCLI(["memory", "get", "f", "--in", home.root.path], paths: home.paths) == 0)
    }

    @Test func setWithAFileSharesIt() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.root.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: file)
        let app = try FakeAppSocket(paths: home.paths) { message in
            guard case let .memory(.write(write, _)) = message else { return nil }
            return .memoryReply(.entry(MemoryEntry(key: write.key, scope: write.scope, file: write.file)))
        }
        defer { app.stop() }
        #expect(runCLI(["memory", "set", "notes", "--file", file.path, "--in", home.root.path], paths: home.paths) == 0)
        guard case let .memory(.write(write, _))? = app.received.first else { Issue.record("No write"); return }
        #expect(write.file?.name == "notes.txt")
        #expect(write.value == nil)
    }

    @Test func anAppFailureIsReported() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try FakeAppSocket(paths: home.paths) { _ in .memoryReply(.failed("No entry called k.")) }
        defer { app.stop() }
        #expect(runCLI(["memory", "get", "k", "--in", home.root.path], paths: home.paths) == 1)
    }
}
