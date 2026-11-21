import Foundation
import Testing
@testable import AmbientBase

/// A fresh directory under the system temp dir, removed by the caller.
private func qaTempDir(_ label: String = "paths") throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("qa-base-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func posixMode(_ url: URL) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private func isDirectory(_ url: URL) -> Bool {
    var dir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
}

@Suite("AmbientPaths")
struct QAPathsTests {
    // MARK: current(environment:)

    @Test func homeAndAmbientHomeFromEnvironment() {
        let p = AmbientPaths.current(environment: ["HOME": "/Users/qa", "AMBIENT_HOME": "/var/qa/amb"])
        #expect(p.userHome.path == "/Users/qa")
        #expect(p.home.path == "/var/qa/amb")
        #expect(p.userHome.hasDirectoryPath)
        #expect(p.home.hasDirectoryPath)
    }

    @Test func ambientHomeDefaultsToDotAmbientUnderHome() {
        let p = AmbientPaths.current(environment: ["HOME": "/Users/qa"])
        #expect(p.home.path == "/Users/qa/.ambient")
    }

    @Test func emptyAmbientHomeIsIgnored() {
        let p = AmbientPaths.current(environment: ["HOME": "/Users/qa", "AMBIENT_HOME": ""])
        #expect(p.home.path == "/Users/qa/.ambient")
    }

    @Test(arguments: [[String: String](), ["HOME": ""]])
    func missingOrEmptyHomeFallsBackToNSHomeDirectory(env: [String: String]) {
        let p = AmbientPaths.current(environment: env)
        #expect(p.userHome.standardizedFileURL.path == URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path)
        #expect(p.home.lastPathComponent == ".ambient")
        #expect(p.home.deletingLastPathComponent().standardizedFileURL.path == p.userHome.standardizedFileURL.path)
    }

    @Test func ambientHomeWorksWithoutHome() {
        let p = AmbientPaths.current(environment: ["AMBIENT_HOME": "/tmp/qa-amb"])
        #expect(p.home.path == "/tmp/qa-amb")
    }

    @Test func relativeAmbientHomeResolvesAgainstTheWorkingDirectory() {
        let p = AmbientPaths.current(environment: ["HOME": "/Users/qa", "AMBIENT_HOME": "rel/amb"])
        #expect(p.home.path.hasSuffix("/rel/amb"))
        #expect(p.home.path.hasPrefix("/"))
    }

    @Test func defaultEnvironmentMatchesProcessEnvironment() {
        #expect(AmbientPaths.current() == AmbientPaths.current(environment: ProcessInfo.processInfo.environment))
    }

    @Test func homeWithTrailingSlashIsTheSameDirectory() {
        let p = AmbientPaths.current(environment: ["HOME": "/Users/qa/"])
        #expect(p.home.path == "/Users/qa/.ambient")
    }

    // MARK: init + derived paths

    @Test func initDefaultsHomeUnderUserHome() {
        let p = AmbientPaths(userHome: URL(fileURLWithPath: "/u", isDirectory: true))
        #expect(p.home.path == "/u/.ambient")
        #expect(p.home.hasDirectoryPath)
    }

    @Test func everyDerivedPath() {
        let p = AmbientPaths(userHome: URL(fileURLWithPath: "/u", isDirectory: true),
                             home: URL(fileURLWithPath: "/h", isDirectory: true))
        #expect(p.socket.path == "/h/ambient.sock")
        #expect(!p.socket.hasDirectoryPath)
        #expect(p.binDir.path == "/h/bin")
        #expect(p.binDir.hasDirectoryPath)
        #expect(p.cliLink.path == "/h/bin/ambient")
        #expect(!p.cliLink.hasDirectoryPath)
        #expect(p.backups.path == "/h/backups")
        #expect(p.backups.hasDirectoryPath)
        #expect(p.logs.path == "/h/logs")
        #expect(p.logs.hasDirectoryPath)
        #expect(p.voice.path == "/h/voice")
        #expect(p.voice.hasDirectoryPath)
        #expect(p.taskSkill.path == "/h/task-skill.json")
        #expect(!p.taskSkill.hasDirectoryPath)
    }

    @Test func defaultSocketPathFitsInSunPath() {
        // A typical home must leave the socket under the 104-byte sockaddr_un limit.
        let p = AmbientPaths.current(environment: ["HOME": "/Users/a-fairly-long-user-name"])
        #expect(p.socket.path.utf8.count < 104)
    }

    @Test func equatable() {
        let a = AmbientPaths(userHome: URL(fileURLWithPath: "/u", isDirectory: true))
        let b = AmbientPaths(userHome: URL(fileURLWithPath: "/u", isDirectory: true),
                             home: URL(fileURLWithPath: "/u/.ambient", isDirectory: true))
        let c = AmbientPaths(userHome: URL(fileURLWithPath: "/u", isDirectory: true),
                             home: URL(fileURLWithPath: "/other", isDirectory: true))
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: ensureHome

    @Test func ensureHomeCreatesDirectoriesReadableOnlyByTheUser() throws {
        let root = try qaTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AmbientPaths(userHome: root, home: root.appendingPathComponent("amb", isDirectory: true))
        try p.ensureHome()
        for dir in [p.home, p.binDir, p.backups, p.logs] {
            #expect(isDirectory(dir), "\(dir.path) missing")
            #expect(try posixMode(dir) == 0o700, "\(dir.path) mode")
        }
        // Not part of ensureHome: voice packs and the skill file are created on demand.
        #expect(!FileManager.default.fileExists(atPath: p.voice.path))
        #expect(!FileManager.default.fileExists(atPath: p.taskSkill.path))
        #expect(!FileManager.default.fileExists(atPath: p.socket.path))
    }

    @Test func ensureHomeIsIdempotent() throws {
        let root = try qaTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let p = AmbientPaths(userHome: root, home: root.appendingPathComponent("amb", isDirectory: true))
        try p.ensureHome()
        let marker = p.logs.appendingPathComponent("keep.txt")
        try Data("x".utf8).write(to: marker)
        try p.ensureHome()
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(try posixMode(p.home) == 0o700)
    }

    @Test func ensureHomeTightensAnExistingLooseHome() throws {
        let root = try qaTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("amb", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        #expect(try posixMode(home) == 0o755)
        try AmbientPaths(userHome: root, home: home).ensureHome()
        #expect(try posixMode(home) == 0o700)
    }

    @Test func ensureHomeCreatesMissingParents() throws {
        let root = try qaTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("a/b/c/amb", isDirectory: true)
        let p = AmbientPaths(userHome: root, home: home)
        try p.ensureHome()
        #expect(isDirectory(p.binDir))
    }

    @Test func ensureHomeThrowsWhenHomeIsAFile() throws {
        let root = try qaTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("amb")
        try Data("not a dir".utf8).write(to: home)
        #expect(throws: (any Error).self) {
            try AmbientPaths(userHome: root, home: home).ensureHome()
        }
    }

    @Test func ensureHomeThrowsWhenASubdirectoryIsAFile() throws {
        let root = try qaTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("amb", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data().write(to: home.appendingPathComponent("logs"))
        #expect(throws: (any Error).self) {
            try AmbientPaths(userHome: root, home: home).ensureHome()
        }
    }
}
