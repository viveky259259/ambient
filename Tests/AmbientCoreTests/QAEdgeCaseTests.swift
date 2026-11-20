import Foundation
import Testing
@testable import AmbientCore

/// Smaller gaps found with coverage: model formats, pairing messages, the machine allowlist file, shared-file limits.
@Suite struct QAEdgeCaseTests {
    // MARK: - Local models

    @Test func formatRuntimesAndLabels() {
        #expect(LocalModelFormat.mlxText.runtime == "mlx-lm")
        #expect(LocalModelFormat.mlxVision.runtime == "mlx-vlm")
        #expect(LocalModelFormat.gguf.runtime == "llama.cpp")
        #expect(LocalModelFormat.media.runtime == nil)
        #expect(LocalModelFormat.unknown.runtime == nil)
        #expect([LocalModelFormat.mlxText, .mlxVision, .gguf, .media, .unknown].filter(\.writesText) == [.mlxText, .mlxVision, .gguf])
    }

    @Test func llamaCppIsFoundOnPathFirst() throws {
        let dir = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = dir.appendingPathComponent("llama-completion")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        #expect(LocalRuntimes.llamaCpp(environment: ["PATH": dir.path, "HOME": dir.path]) == tool.path)
    }

    @Test func nonExecutableLlamaIsIgnored() throws {
        let dir = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("x".utf8).write(to: dir.appendingPathComponent("llama-cli"))
        let found = LocalRuntimes.llamaCpp(environment: ["PATH": dir.path, "HOME": dir.path])
        #expect(found != dir.appendingPathComponent("llama-cli").path)
    }

    @Test func emptyOrMissingModelPathsAreNil() {
        #expect(LocalModelPath.inspect("") == nil)
        #expect(LocalModelPath.inspect("   ") == nil)
        #expect(LocalModelPath.inspect("/nonexistent/qa/\(UUID().uuidString)") == nil)
    }

    @Test func emptyFolderIsUnknown() throws {
        let dir = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = try #require(LocalModelPath.inspect(dir.path))
        #expect(model.format == .unknown)
        #expect(model.note == "No config.json or .gguf file in this folder.")
    }

    @Test func projectorGGUFIsNotAModel() throws {
        let dir = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("mmproj-model-f16.gguf")
        try Data().write(to: file)
        let model = try #require(LocalModelPath.inspect(file.path))
        #expect(model.format != .gguf)
        #expect(model.note?.contains("projector") == true)
    }

    // MARK: - Pairing messages

    @Test func pairingFailureDescriptions() {
        typealias F = RemotePairing.Failure
        #expect(F.invalidID("Bad Name").description.hasPrefix("'Bad Name' isn't a valid machine name."))
        #expect(F.unreachable("no route").description == "Couldn't reach the machine: no route")
        #expect(F.copyFailed("disk full").description == "Couldn't copy the shim: disk full")
        #expect(F.checksumMismatch(expected: "a", got: "b").description.contains("expected a, got b"))
        #expect(F.installFailed("x").description == "The shim's install failed: x")
        #expect(F.badStatus("y").description == "The machine's status couldn't be read: y")
        #expect(F.identityChanged(expected: "e", got: "g").description.contains("--accept-new-identity"))
    }

    @Test func explainPrefersTimeoutThenLastLineThenStatus() {
        typealias R = RemoteTransport.Result
        #expect(RemotePairing.explain(R(status: 1, stdout: Data(), stderr: "boom", timedOut: true)) == "timed out")
        #expect(RemotePairing.explain(R(status: 1, stdout: Data("ok\nlast words".utf8), stderr: "", timedOut: false)) == "last words")
        #expect(RemotePairing.explain(R(status: 7, stdout: Data(), stderr: "", timedOut: false)) == "exit status 7")
    }

    @Test func explainStripsControlCharactersFromTheMachine() {
        let hostile = RemoteTransport.Result(status: 1, stdout: Data("\u{1B}[31mred\u{07}".utf8), stderr: "", timedOut: false)
        let text = RemotePairing.explain(hostile)
        #expect(!text.contains("\u{1B}"))
        #expect(!text.contains("\u{07}"))
    }

    // MARK: - Machine allowlist file

    static let pin = "id:" + String(repeating: "a", count: 32)

    @Test func machineFileRoundTripsSortedAndPrivate() throws {
        let dir = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("remote/machines.json")
        let date = Date(timeIntervalSince1970: 1_000)
        try MachineFile.save([Machine(id: "zeta", transport: ["ssh", "zeta"], fingerprint: Self.pin, pairedAt: date),
                              Machine(id: "alpha", transport: ["ssh", "alpha"], fingerprint: Self.pin, pairedAt: date)], to: url)
        #expect(MachineFile.load(from: url).map(\.id) == ["alpha", "zeta"])
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(perms?.intValue == 0o600)
    }

    @Test func machineFileDropsInvalidAndDuplicateEntries() throws {
        let dir = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("machines.json")
        let good = Machine(id: "devbox", transport: ["ssh", "devbox"], fingerprint: Self.pin)
        try MachineFile.save([good], to: url)
        // Hand-edit the file the way a person might.
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var machines = try #require(json["machines"] as? [[String: Any]])
        var dup = machines[0]; dup["label"] = "Second"
        var badID = machines[0]; badID["id"] = "Not Valid"
        var badPin = machines[0]; badPin["id"] = "other"; badPin["fingerprint"] = "nope"
        var noTransport = machines[0]; noTransport["id"] = "empty"; noTransport["transport"] = [String]()
        machines += [dup, badID, badPin, noTransport]
        json["machines"] = machines
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let loaded = MachineFile.load(from: url)
        #expect(loaded.map(\.id) == ["devbox"])
        #expect(loaded.first?.label != "Second")
    }

    @Test func machineFileOfAnotherVersionOrGarbageIsEmpty() throws {
        let dir = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("machines.json")
        try Data(#"{"version":2,"machines":[]}"#.utf8).write(to: url)
        #expect(MachineFile.load(from: url).isEmpty)
        try Data("garbage".utf8).write(to: url)
        #expect(MachineFile.load(from: url).isEmpty)
        #expect(MachineFile.load(from: dir.appendingPathComponent("missing.json")).isEmpty)
    }

    @Test func remotePathsLiveUnderTheAmbientHome() {
        let paths = AmbientPaths(userHome: URL(fileURLWithPath: "/Users/qa"))
        #expect(paths.remoteDir.path == "/Users/qa/.ambient/remote")
        #expect(paths.machinesFile.lastPathComponent == "machines.json")
        #expect(paths.remoteAuditLog.lastPathComponent == "audit.jsonl")
        #expect(paths.memoryFile.path == "/Users/qa/.ambient/memory.json")
        #expect(paths.memoryBlobs.path == "/Users/qa/.ambient/memory")
    }

    // MARK: - Shared files

    @Test func blobStoreRefusesMissingFoldersAndSpecialFiles() throws {
        let dir = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MemoryBlobStore(root: dir.appendingPathComponent("blobs"))
        #expect(throws: MemoryError.self) { try store.add(fileAt: dir.appendingPathComponent("nope.txt").path) }
        #expect(throws: MemoryError.self) { try store.add(fileAt: dir.path) }
        #expect(throws: MemoryError.self) { try store.add(fileAt: "/dev/null") }
    }

    @Test func blobStoreRefusesSecretsByNameAndContent() throws {
        let dir = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MemoryBlobStore(root: dir.appendingPathComponent("blobs"))
        let env = dir.appendingPathComponent(".env")
        try Data("A=1".utf8).write(to: env)
        #expect(throws: MemoryError.self) { try store.add(fileAt: env.path) }
        let notes = dir.appendingPathComponent("notes.txt")
        try Data("token ghp_\(String(repeating: "A", count: 36))".utf8).write(to: notes)
        #expect(throws: MemoryError.self) { try store.add(fileAt: notes.path) }
        // A symlink with an innocent name pointing at a secret is judged by its target too.
        let link = dir.appendingPathComponent("innocent.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: env)
        #expect(throws: MemoryError.self) { try store.add(fileAt: link.path) }
    }

    @Test func sameFileTwiceIsOneBlob() throws {
        let dir = try shortTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MemoryBlobStore(root: dir.appendingPathComponent("blobs"))
        let file = dir.appendingPathComponent("plan.md")
        try Data("# Plan".utf8).write(to: file)
        let a = try store.add(fileAt: file.path)
        let b = try store.add(fileAt: file.path)
        #expect(a == b)
        #expect(store.contains(a))
    }

    // MARK: - Memory guard

    @Test(arguments: [
        "-----BEGIN OPENSSH PRIVATE KEY-----", "AKIAABCDEFGHIJKLMNOP", "glpat-abcdefghijklmnopqrstuv",
        "sk-ant-api03-abcdefghijklmnopqrstuvwxyz", "xoxb-1234567890-abc", "AIza" + String(repeating: "x", count: 35),
        "npm_" + String(repeating: "a", count: 36), "github_pat_" + String(repeating: "a", count: 40),
    ])
    func secretsInTextAreRefused(text: String) {
        #expect(MemoryGuard.problem(withText: "config: \(text)") != nil)
    }

    @Test(arguments: ["The build passed.", "sk-short", "AKIA-not-a-key", "use the ghp_ prefix for tokens"])
    func ordinaryTextIsFine(text: String) {
        #expect(MemoryGuard.problem(withText: text) == nil)
    }

    @Test(arguments: [".env", ".env.local", "prod.env", "id_ed25519", "cert.pem", "server.KEY", "~/.ssh/config",
                      "/Users/x/.AWS/credentials", "/Users/x/Library/Keychains/login.keychain-db", ".npmrc"])
    func secretPathsAreRefused(path: String) {
        #expect(MemoryGuard.problem(withFilePath: path) != nil)
    }

    @Test(arguments: [".env.example", ".env.sample", ".env.template", "README.md", "/src/env.swift", "keys.txt"])
    func templatesAndOrdinaryFilesAreFine(path: String) {
        #expect(MemoryGuard.problem(withFilePath: path) == nil)
    }
}
