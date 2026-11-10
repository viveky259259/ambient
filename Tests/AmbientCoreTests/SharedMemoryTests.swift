import Foundation
import Testing
@testable import AmbientCore

@Suite struct SharedMemoryTests {
    let app = "/src/app"

    private func write(_ key: String, untilSessionEnds: Bool = false) -> MemoryRequest {
        .write(MemoryWrite(key: key, scope: .project(app), value: "v", untilSessionEnds: untilSessionEnds), callerPids: [42])
    }

    private var agent: Session {
        var s = Session(agent: .claude, sessionId: "s1", at: Date())
        s.host = HostInfo(agentPid: 42)
        return s
    }

    @Test func answersAndSavesShortlyAfter() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("memory.json")
        let memory = SharedMemory(url: url, blobs: nil, saveDelay: 0.05)

        guard case let .entry(entry) = memory.answer(write("plan"), sessions: [agent]) else {
            Issue.record("the write failed")
            return
        }
        #expect(entry.author?.sessionID == "claude:s1")
        #expect(wait { MemoryFile.load(from: url)?.map(\.key) == ["plan"] })
    }

    @Test func manyAgentsAtOnce() {
        let memory = SharedMemory(url: nil, blobs: nil)
        DispatchQueue.concurrentPerform(iterations: 64) { i in
            _ = memory.answer(write("key-\(i)"), sessions: [])
            _ = memory.answer(.list(project: app, scope: nil), sessions: [])
        }
        #expect(memory.entries.count == 64)
    }

    @Test func sessionsEndOrTheirAgentsExit() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("memory.json")
        let memory = SharedMemory(url: url, blobs: nil, saveDelay: 0.05)
        _ = memory.answer(write("ends", untilSessionEnds: true), sessions: [agent])
        memory.sessionEnded("claude:s1")
        #expect(memory.entries.isEmpty)

        _ = memory.answer(write("exits", untilSessionEnds: true), sessions: [agent])
        _ = memory.answer(write("stays"), sessions: [agent])
        memory.sweep(isAlive: { _ in true })
        #expect(memory.entries.count == 2)
        memory.sweep(isAlive: { _ in false })
        #expect(memory.entries.map(\.key) == ["stays"])
        #expect(wait { MemoryFile.load(from: url)?.map(\.key) == ["stays"] })
    }

    @Test func loadsWithoutWhatExpired() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("memory.json")
        let old = MemoryEntry(key: "old", scope: .global, value: "v", expiresAt: Date(timeIntervalSinceNow: -60))
        let fresh = MemoryEntry(key: "fresh", scope: .global, value: "v", expiresAt: Date(timeIntervalSinceNow: 60))
        try MemoryFile.save([old, fresh], to: url)

        let memory = SharedMemory(url: url, blobs: nil, saveDelay: 0.05)
        memory.load()
        #expect(memory.entries.map(\.key) == ["fresh"])
        #expect(wait { MemoryFile.load(from: url)?.map(\.key) == ["fresh"] })
    }

    @Test func collectsCopiesNothingRefersTo() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let blobs = MemoryBlobStore(root: dir.appendingPathComponent("memory"))
        let (kept, dropped) = try (oldCopy(named: "kept.txt", in: blobs, dir: dir), oldCopy(named: "dropped.txt", in: blobs, dir: dir))
        let memory = SharedMemory(url: dir.appendingPathComponent("memory.json"), blobs: blobs)
        memory.load()
        _ = memory.answer(.write(MemoryWrite(key: "log", scope: .global, file: kept), callerPids: []), sessions: [])

        memory.sweep()
        #expect(wait { !FileManager.default.fileExists(atPath: blobs.url(for: dropped).path) })
        #expect(FileManager.default.fileExists(atPath: blobs.url(for: kept).path))
    }

    @Test func anUnreadableFileIsLeftWithItsCopies() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("memory.json")
        let unreadable = Data("{\"version\":2,\"entries\":[]}".utf8)
        try unreadable.write(to: url)
        let blobs = MemoryBlobStore(root: dir.appendingPathComponent("memory"))
        let copy = try oldCopy(named: "theirs.txt", in: blobs, dir: dir)

        let memory = SharedMemory(url: url, blobs: blobs, saveDelay: 0.05)
        memory.load()
        guard case .entry = memory.answer(write("meanwhile"), sessions: []) else {
            Issue.record("sharing should still work")
            return
        }
        memory.sweep()
        memory.saveNow()
        Thread.sleep(forTimeInterval: 0.2)
        #expect(try Data(contentsOf: url) == unreadable)
        #expect(FileManager.default.fileExists(atPath: blobs.url(for: copy).path))
    }

    /// A copy in `blobs` changed long enough ago to be collected.
    private func oldCopy(named name: String, in blobs: MemoryBlobStore, dir: URL) throws -> MemoryBlob {
        let source = dir.appendingPathComponent(name)
        try "\(name)\n".write(to: source, atomically: true, encoding: .utf8)
        let blob = try blobs.add(fileAt: source.path)
        let old = Date(timeIntervalSinceNow: -2 * SharedMemory.collectInterval)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: blobs.url(for: blob).path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: blobs.url(for: blob).deletingLastPathComponent().path)
        return blob
    }

    private func wait(_ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: 3)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return condition()
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
