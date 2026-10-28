import Foundation
import Testing
@testable import AmbientCore

@Suite struct MemoryStoreTests {
    let app = "/src/app"
    let codex = MemoryAuthor(sessionID: "codex:c1", agent: .codex, label: "Codex")

    @Test func projectFirstThenGlobal() throws {
        let store = MemoryStore()
        try store.write(MemoryWrite(key: "schema", scope: .global, value: "global"), author: nil)
        #expect(store.read(key: "schema", project: app)?.value == "global")
        try store.write(MemoryWrite(key: "schema", scope: .project(app), value: "project"), author: codex)
        #expect(store.read(key: "schema", project: app)?.value == "project")
        #expect(store.read(key: "schema", project: app, scope: .global)?.value == "global")
        #expect(store.read(key: "schema", project: "/src/other")?.value == "global")
        #expect(store.read(key: "schema", project: app)?.author == codex)
    }

    @Test func projectsDontSeeEachOther() throws {
        let store = MemoryStore()
        try store.write(MemoryWrite(key: "plan", scope: .project(app), value: "ship it"), author: codex)
        #expect(store.read(key: "plan", project: "/src/other") == nil)
        #expect(store.list(project: "/src/other").isEmpty)
        #expect(store.list(project: app).map(\.key) == ["plan"])
    }

    @Test func rewriteReplacesAndKeepsCreation() throws {
        let store = MemoryStore()
        let start = Date(timeIntervalSince1970: 1_000)
        try store.write(MemoryWrite(key: "tests", scope: .project(app), value: "3 failing"), author: codex, now: start)
        let later = start.addingTimeInterval(60)
        let again = try store.write(MemoryWrite(key: "tests", scope: .project(app), value: "1 failing"), author: nil, now: later)
        #expect(store.entries.count == 1)
        #expect(again.value == "1 failing")
        #expect(again.createdAt == start)
        #expect(again.updatedAt == later)
    }

    @Test func listingsLeaveValuesOut() throws {
        let store = MemoryStore()
        try store.write(MemoryWrite(key: "notes", scope: .project(app), value: "abc", description: "Notes"), author: nil)
        let listed = try #require(store.list(project: app).first)
        #expect(listed.value == nil)
        #expect(listed.size == 3)
        #expect(listed.description == "Notes")
    }

    @Test func entriesExpire() throws {
        let store = MemoryStore()
        let now = Date()
        try store.write(MemoryWrite(key: "short", scope: .project(app), value: "x", ttlMinutes: 5), author: nil, now: now)
        try store.write(MemoryWrite(key: "default", scope: .project(app), value: "x"), author: nil, now: now)
        let soon = now.addingTimeInterval(6 * 60)
        #expect(store.read(key: "short", project: app, now: soon) == nil)
        #expect(store.read(key: "default", project: app, now: soon) != nil)
        #expect(store.sweep(now: soon).map(\.key) == ["short"])
        #expect(store.read(key: "default", project: app, now: now.addingTimeInterval(8 * 86_400)) == nil)
    }

    @Test func sessionBoundEntriesEndWithTheirSession() throws {
        let store = MemoryStore()
        try store.write(MemoryWrite(key: "scratch", scope: .project(app), value: "x", untilSessionEnds: true), author: codex)
        try store.write(MemoryWrite(key: "keep", scope: .project(app), value: "x"), author: codex)
        #expect(store.sessionEnded("claude:other").isEmpty)
        #expect(store.sessionEnded("codex:c1").map(\.key) == ["scratch"])
        #expect(store.entries.map(\.key) == ["keep"])

        try store.write(MemoryWrite(key: "scratch", scope: .project(app), value: "x", untilSessionEnds: true), author: codex)
        #expect(store.retainSessions(["codex:c1"]).isEmpty)
        #expect(store.retainSessions([]).map(\.key) == ["scratch"])
    }

    @Test func sessionBoundNeedsAnAuthor() {
        let store = MemoryStore()
        #expect(throws: MemoryError.self) {
            try store.write(MemoryWrite(key: "scratch", scope: .project(app), value: "x", untilSessionEnds: true), author: nil)
        }
    }

    @Test func refusesBadWrites() throws {
        let store = MemoryStore()
        for key in ["", "has space", "-leading", String(repeating: "k", count: 81)] {
            #expect(throws: MemoryError.self) { try store.write(MemoryWrite(key: key, scope: .global, value: "x"), author: nil) }
        }
        #expect(throws: MemoryError.self) { try store.write(MemoryWrite(key: "k", scope: .global), author: nil) }
        #expect(throws: MemoryError.self) { try store.write(MemoryWrite(key: "k", scope: .global, value: ""), author: nil) }
        let big = String(repeating: "a", count: MemoryStore.maxValueBytes + 1)
        #expect(throws: MemoryError.self) { try store.write(MemoryWrite(key: "k", scope: .global, value: big), author: nil) }
        #expect(throws: MemoryError.self) {
            try store.write(MemoryWrite(key: "k", scope: .global, value: "x", ttlMinutes: 0), author: nil)
        }
        #expect(throws: MemoryError.self) {
            try store.write(MemoryWrite(key: "k", scope: .global, value: "token ghp_" + String(repeating: "a", count: 36)), author: nil)
        }
        try store.write(MemoryWrite(key: "api/schema.v2", scope: .global, value: "ok"), author: nil)
        #expect(store.entries.count == 1)
    }

    @Test func scopesHoldALimitedNumber() throws {
        let store = MemoryStore()
        for i in 0..<MemoryStore.maxEntriesPerScope {
            try store.write(MemoryWrite(key: "k\(i)", scope: .project(app), value: "x"), author: nil)
        }
        #expect(throws: MemoryError.self) { try store.write(MemoryWrite(key: "one-more", scope: .project(app), value: "x"), author: nil) }
        // Replacing an entry and writing elsewhere still work.
        try store.write(MemoryWrite(key: "k0", scope: .project(app), value: "y"), author: nil)
        try store.write(MemoryWrite(key: "one-more", scope: .global, value: "x"), author: nil)
    }

    @Test func forgetLooksUpLikeRead() throws {
        let store = MemoryStore()
        try store.write(MemoryWrite(key: "k", scope: .global, value: "g"), author: nil)
        try store.write(MemoryWrite(key: "k", scope: .project(app), value: "p"), author: nil)
        #expect(store.forget(key: "k", project: app)?.value == "p")
        #expect(store.forget(key: "k", project: app)?.value == "g")
        #expect(store.forget(key: "k", project: app) == nil)
    }

    @Test func authorIsTheNearestAgentProcess() {
        var older = Session(agent: .claude, sessionId: "old", at: Date(timeIntervalSince1970: 100))
        older.host = HostInfo(agentPid: 42)
        var newer = Session(agent: .claude, sessionId: "new", at: Date(timeIntervalSince1970: 200))
        newer.host = HostInfo(agentPid: 42)
        var other = Session(agent: .codex, sessionId: "c", at: Date())
        other.host = HostInfo(agentPid: 7)
        let sessions = [older, newer, other]
        #expect(MemoryAuthor.resolve(callerPids: [42, 7], sessions: sessions)?.sessionID == "claude:new")
        #expect(MemoryAuthor.resolve(callerPids: [99, 7], sessions: sessions)?.label == "Codex")
        #expect(MemoryAuthor.resolve(callerPids: [99], sessions: sessions) == nil)
    }

    @Test func persistRoundTrip() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("memory.json")
        let store = MemoryStore()
        try store.write(MemoryWrite(key: "plan", scope: .project(app), value: "ship", untilSessionEnds: true), author: codex)
        try MemoryFile.save(store.entries, to: url)
        let loaded = MemoryFile.load(from: url)
        #expect(loaded == store.entries)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func answersRequestsAndCountsChanges() throws {
        let store = MemoryStore()
        var claude = Session(agent: .claude, sessionId: "s1", at: Date())
        claude.host = HostInfo(agentPid: 42)
        let start = store.revision

        let wrote = store.answer(.write(MemoryWrite(key: "k", scope: .project(app), value: "v"), callerPids: [9, 42]),
                                 sessions: [claude], blobs: nil)
        guard case let .entry(entry) = wrote else { Issue.record("\(wrote)"); return }
        #expect(entry.author?.sessionID == "claude:s1")
        #expect(store.revision > start)

        let reads = store.revision
        #expect(store.answer(.read(key: "k", project: app, scope: nil), sessions: [], blobs: nil) == .entry(entry))
        #expect(store.answer(.list(project: app, scope: nil), sessions: [], blobs: nil) == .entries([entry.summary]))
        #expect(store.answer(.read(key: "nope", project: app, scope: nil), sessions: [], blobs: nil)
            == .failed("Nothing is shared as nope in app or globally."))
        #expect(store.revision == reads)

        // A file whose copy isn't in the blob store isn't shared.
        let missing = MemoryWrite(key: "f", scope: .global, file: MemoryBlob(name: "a.txt", sha256: "00", size: 1))
        let blobs = MemoryBlobStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        guard case .failed = store.answer(.write(missing, callerPids: []), sessions: [], blobs: blobs) else {
            Issue.record("wrote a file with no copy"); return
        }
        #expect(store.answer(.forget(key: "k", project: app, scope: nil), sessions: [], blobs: nil) == .forgotten(entry))
        #expect(store.revision > reads)
    }

    @Test func requestsCrossTheWire() throws {
        let write = MemoryWrite(key: "k", scope: .project(app), value: "v", ttlMinutes: 10)
        for message: WireMessage in [.memory(.write(write, callerPids: [1, 2])), .memory(.list(project: app, scope: .global)),
                                     .memoryReply(.failed("no")), .memoryReply(.entries([MemoryEntry(key: "k", scope: .global, value: "v")]))] {
            #expect(try Wire.decode(Wire.encode(message)) == message)
        }
    }

    // MARK: - Projects

    @Test func projectRootIsTheRepository() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = dir.appendingPathComponent("repo")
        let nested = repo.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let root = repo.resolvingSymlinksInPath().path
        #expect(MemoryProject.root(for: nested.path) == root)

        // A worktree shares its main checkout's memory.
        let worktree = dir.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(repo.path)/.git/worktrees/wt\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        #expect(MemoryProject.root(for: worktree.path) == root)

        let loose = dir.appendingPathComponent("loose")
        try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
        #expect(MemoryProject.root(for: loose.path) == loose.resolvingSymlinksInPath().path)
    }

    // MARK: - Files

    @Test func sharedFilesAreReadOnlyCopies() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blobs = MemoryBlobStore(root: dir.appendingPathComponent("memory"))
        let source = dir.appendingPathComponent("log.txt")
        try "build ok\n".write(to: source, atomically: true, encoding: .utf8)

        let blob = try blobs.add(fileAt: source.path)
        #expect(blob.name == "log.txt")
        #expect(blob.size == 9)
        #expect(blobs.contains(blob))
        #expect(try String(contentsOf: blobs.url(for: blob), encoding: .utf8) == "build ok\n")
        let mode = try FileManager.default.attributesOfItem(atPath: blobs.url(for: blob).path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o400)
        #expect(try blobs.add(fileAt: source.path) == blob)

        // Kept while referenced or new; deleted once neither.
        blobs.collect(keeping: [], changedBefore: Date().addingTimeInterval(-60))
        #expect(blobs.contains(blob))
        blobs.collect(keeping: [blob], changedBefore: Date().addingTimeInterval(60))
        #expect(blobs.contains(blob))
        blobs.collect(keeping: [], changedBefore: Date().addingTimeInterval(60))
        #expect(!blobs.contains(blob))
        #expect((try? FileManager.default.contentsOfDirectory(atPath: blobs.root.path))?.isEmpty == true)
    }

    @Test func secretFilesStayPut() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blobs = MemoryBlobStore(root: dir.appendingPathComponent("memory"))
        for name in [".env", ".env.local", "server.pem", "id_ed25519"] {
            let file = dir.appendingPathComponent(name)
            try "x".write(to: file, atomically: true, encoding: .utf8)
            #expect(throws: MemoryError.self) { try blobs.add(fileAt: file.path) }
        }
        let leaky = dir.appendingPathComponent("config.yml")
        try "key: sk-ant-\(String(repeating: "x", count: 30))".write(to: leaky, atomically: true, encoding: .utf8)
        #expect(throws: MemoryError.self) { try blobs.add(fileAt: leaky.path) }
        let template = dir.appendingPathComponent(".env.example")
        try "API_KEY=".write(to: template, atomically: true, encoding: .utf8)
        _ = try blobs.add(fileAt: template.path)
        #expect(throws: MemoryError.self) { try blobs.add(fileAt: dir.path) }
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
