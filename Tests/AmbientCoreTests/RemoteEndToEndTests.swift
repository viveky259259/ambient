import Foundation
import Testing
@testable import AmbientCore

private let shimURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Resources/ambient-remote")

/// A pretend remote machine: a home folder, reached by a `sh -c` transport that runs the remote command in it with
/// the same shim, the same spool and the same hooks a real machine would have.
private final class StubMachine {
    let home: URL
    let hub: URL
    var paths: AmbientPaths { AmbientPaths(userHome: hub, home: hub.appendingPathComponent(".ambient", isDirectory: true)) }
    var spool: URL { home.appendingPathComponent(".ambient/spool") }
    var shim: URL { home.appendingPathComponent(".ambient/bin/ambient-remote") }

    var transportOverride: [String]?

    /// Identity comes from the install id: a test can change it without touching the Mac's host keys.
    var transport: [String] {
        transportOverride ?? ["/bin/sh", "-c", #"HOME="$1"; AMBIENT_REMOTE_HOSTKEYS=/nonexistent; export HOME AMBIENT_REMOTE_HOSTKEYS; cd "$HOME" && exec /bin/sh -c "$2""#,
         "stub", home.path]
    }

    init() throws {
        // Short: a Unix socket isn't involved, but these paths appear in every command and failure.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ar-" + UUID().uuidString.prefix(8))
        home = root.appendingPathComponent("remote", isDirectory: true)
        hub = root.appendingPathComponent("hub", isDirectory: true)
        for dir in [home.appendingPathComponent(".claude"), home.appendingPathComponent(".codex"), hub] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    deinit { try? FileManager.default.removeItem(at: home.deletingLastPathComponent()) }

    func pair(redaction: RemoteRedaction? = nil) throws -> Machine {
        let outcome = try RemotePairing.pair(.init(id: "devbox", label: "Devbox", transport: transport, redaction: redaction),
                                             shim: RemoteShim(url: shimURL), existing: nil, audit: paths.remoteAudit)
        return outcome.machine
    }

    /// What the agent's hook does: pipes a payload into `emit`. Returns how long it took.
    @discardableResult
    func emit(_ payload: [String: Any], agent: String = "claude") throws -> TimeInterval {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [shim.path, "emit", agent]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let start = Date()
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: data)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return Date().timeIntervalSince(start)
    }

    func hook(_ name: String, session: String = "s1", _ extra: [String: Any] = [:]) throws {
        var payload: [String: Any] = ["session_id": session, "hook_event_name": name, "cwd": "/home/dev/api"]
        for (k, v) in extra { payload[k] = v }
        try emit(payload)
    }

    /// Appends raw bytes to the spool, as something other than `emit` might.
    func appendToSpool(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: spool.appendingPathComponent("events.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    func spoolLines() throws -> [String] {
        try String(contentsOf: spool.appendingPathComponent("events.jsonl"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }
}

/// The hub's part of an alert, as `AppModel` does it: apply, save first if anyone is about to hear of it, then alert.
/// `saveEvery` stands in for the app's debounced save, which a killed hub never reaches.
private final class Hub: @unchecked Sendable {
    let machine: Machine
    let stateURL: URL
    let store = SessionStore()
    private let lock = NSLock()
    private(set) var cursor: RemoteCursor
    private(set) var alerts: [String] = []
    private(set) var health: [RemoteHealth] = []
    /// The moment of the crash: nothing from this seq on is processed.
    var crashAt: Int64?
    private(set) var crashed = false
    private(set) var applied: [Int64] = []

    init(machine: Machine, stateURL: URL) {
        self.machine = machine
        self.stateURL = stateURL
        store.load(StateFile.load(from: stateURL))
        cursor = StateFile.loadCursors(from: stateURL)[machine.id] ?? RemoteCursor()
    }

    func link(options: RemoteLink.Options = .init(), policy: RemoteIngest.Policy = .init(), audit: RemoteAudit?) -> RemoteLink {
        RemoteLink(machine: machine, cursor: cursor, policy: policy, options: options, audit: audit,
                   deliver: { [self] batch, cursor in receive(batch, cursor: cursor) },
                   report: { [self] health, _ in
                       lock.lock(); defer { lock.unlock() }
                       self.health.append(health)
                   })
    }

    private func receive(_ batch: [RemoteDelivery], cursor: RemoteCursor) {
        lock.lock(); defer { lock.unlock() }
        guard !crashed else { return }
        var batch = batch
        var cursor = cursor
        if let crashAt, let i = batch.firstIndex(where: { $0.event.seq >= crashAt }) {
            batch = Array(batch[..<i])
            cursor.seq = batch.last?.event.seq ?? self.cursor.seq
            crashed = true
        }
        let (changes, saveFirst) = store.apply(batch, from: machine.ref, saved: self.cursor, cursor: cursor)
        self.cursor = cursor
        applied += batch.map(\.event.seq)
        if saveFirst { try! StateFile.save(store.sessions, cursors: [machine.id: cursor], to: stateURL) }
        let settings = AlertPolicy.Settings(notifications: true, sounds: true, doneThreshold: 0, quiet: false)
        for change in changes where AlertPolicy.decide(change, settings: settings, hostIsFrontmost: false) != nil {
            alerts.append("\(change.session.sessionId)@\(change.session.origin!.lastSeq)")
        }
    }

    var healthLog: [RemoteHealth] {
        lock.lock(); defer { lock.unlock() }
        return health
    }

    var alertLog: [String] {
        lock.lock(); defer { lock.unlock() }
        return alerts
    }

    var appliedLog: [Int64] {
        lock.lock(); defer { lock.unlock() }
        return applied
    }

    var hasCrashed: Bool {
        lock.lock(); defer { lock.unlock() }
        return crashed
    }

    func sessions() -> [Session] {
        lock.lock(); defer { lock.unlock() }
        return store.sessions
    }
}

private func waitUntil(_ timeout: TimeInterval = 15, _ condition: () throws -> Bool) rethrows -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if try condition() { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return try condition()
}

@Suite(.serialized) struct RemoteEndToEndTests {
    /// Two prompts and two results in three sessions, on a live spool: alerts at each `needsInput` and `Stop`.
    private func work(on stub: StubMachine, sessions: [String]) throws {
        for s in sessions {
            try stub.hook("UserPromptSubmit", session: s)
            try stub.hook("PreToolUse", session: s, ["tool_name": "Bash"])
            try stub.hook("PermissionRequest", session: s, ["tool_name": "Bash"])
            try stub.hook("PostToolUse", session: s, ["tool_name": "Bash"])
            try stub.hook("Stop", session: s)
        }
    }

    @Test func pairingCopiesVerifiesInstallsAndPins() throws {
        let stub = try StubMachine()
        let machine = try stub.pair(redaction: .metadata)
        #expect(machine.fingerprint.hasPrefix("id:"))
        #expect(Machine.isValidFingerprint(machine.fingerprint))
        let mode = try FileManager.default.attributesOfItem(atPath: stub.shim.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
        let installed = try String(contentsOf: stub.home.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
        #expect(installed.contains(#"ambient-remote\" emit claude"#))
        let codex = try String(contentsOf: stub.home.appendingPathComponent(".codex/hooks.json"), encoding: .utf8)
        #expect(codex.contains(#"ambient-remote\" emit codex"#))
        #expect(stub.paths.remoteAudit.records().map(\.action) == [.paired])

        // Pairing again is idempotent, and leaves the user's own settings alone.
        let settings = stub.home.appendingPathComponent(".claude/settings.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        object["theme"] = "dark"
        try JSONSerialization.data(withJSONObject: object).write(to: settings)
        _ = try stub.pair()
        let again = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        #expect(again["theme"] as? String == "dark")
        #expect((again["hooks"] as? [String: Any])?.count == 14)
    }

    @Test func aChecksumMismatchPairsNothing() throws {
        let stub = try StubMachine()
        // A machine whose `cat` hands back something else.
        var argv = stub.transport
        argv[2] = argv[2].replacingOccurrences(of: "cd \"$HOME\" &&", with: #"cd "$HOME" && PATH="$HOME/fake:$PATH" &&"#)
        let fake = stub.home.appendingPathComponent("fake")
        try FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho tampered\n".utf8).write(to: fake.appendingPathComponent("cat"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.appendingPathComponent("cat").path)
        #expect {
            _ = try RemotePairing.pair(.init(id: "devbox", transport: argv), shim: RemoteShim(url: shimURL), existing: nil, audit: nil)
        } throws: { error in
            if case RemotePairing.Failure.checksumMismatch = error { return true }
            return false
        }
    }

    @Test func aChattyLoginShellDoesNotGetInTheWay() throws {
        let stub = try StubMachine()
        // A shell rc that prints, the classic way to break anything run over ssh.
        stub.transportOverride = stub.transport.map {
            $0.replacingOccurrences(of: #"exec /bin/sh -c "$2""#, with: #"echo 'Welcome to devbox!'; exec /bin/sh -c "$2""#)
        }
        let machine = try stub.pair()
        let shim = try RemoteShim(url: shimURL)
        let checks = RemoteDoctor.check(machine, shim: shim, cursor: nil)
        #expect(!checks.contains { $0.level == .fail }, "\(checks)")

        let audit = stub.paths.remoteAudit
        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        let link = hub.link(audit: audit)
        link.start()
        defer { link.stop() }
        try stub.hook("UserPromptSubmit")
        #expect(waitUntil { !hub.sessions().isEmpty })
        #expect(audit.records().contains { $0.action == .rejected && $0.detail == "notJSON" })
    }

    @Test func aLiveStreamReachesTheStoreWithLabelsAndRedaction() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        let link = hub.link(audit: stub.paths.remoteAudit)
        link.start()
        defer { link.stop() }
        #expect(waitUntil { hub.healthLog.contains(.connected) })

        try stub.hook("SessionStart", ["source": "startup"])
        try stub.hook("UserPromptSubmit", ["prompt": "my secret prompt"])
        try stub.hook("PreToolUse", ["tool_name": "Bash", "tool_input": ["command": "curl -H 'token: abc' x"]])
        try stub.hook("Notification", ["notification_type": "permission_prompt", "message": "Allow curl with token abc?"])
        #expect(waitUntil { hub.alertLog.count == 1 })

        let s = try #require(hub.sessions().first)
        #expect(s.id == "remote/devbox/claude:s1")
        #expect(s.origin?.machine.label == "Devbox")
        #expect(s.project == "api")
        #expect(s.host == nil)
        // `standard` carries no prompt or message text, and it never reached the spool either.
        #expect(s.activity == .waiting(reason: "permission", message: nil))
        let spool = try stub.spoolLines().joined()
        #expect(!spool.contains("secret"))
        #expect(!spool.contains("token"))
        #expect(!spool.contains("/home/dev"))
        #expect(spool.contains(#""tool":"Bash""#))
        #expect(FocusPlanner.routes(for: s).isEmpty)
    }

    @Test func redactionLevelsApplyOnTheRemote() throws {
        for (level, wantTool, wantMessage) in [(RemoteRedaction.metadata, false, false), (.standard, true, false), (.full, true, true)] {
            let stub = try StubMachine()
            _ = try stub.pair(redaction: level)
            try stub.hook("PreToolUse", ["tool_name": "Bash"])
            try stub.hook("Stop", ["last_assistant_message": "All finished"])
            let spool = try stub.spoolLines().joined()
            #expect(spool.contains(#""tool":"Bash""#) == wantTool, "\(level)")
            #expect(spool.contains("All finished") == wantMessage, "\(level)")
            #expect(spool.contains(#""project":"api""#), "\(level)")
        }
    }

    @Test func killingTheHubLosesAndDuplicatesNoAlerts() throws {
        // Each kill point: right before an alert, right after one, and in a quiet stretch between them.
        for crashAt in [Int64(3), 4, 6, 8, 12] {
            let stub = try StubMachine()
            let machine = try stub.pair()
            let state = stub.hub.appendingPathComponent("state.json")
            try work(on: stub, sessions: ["a", "b", "c"])
            let total = try stub.spoolLines().count

            let first = Hub(machine: machine, stateURL: state)
            first.crashAt = crashAt
            let dying = first.link(audit: nil)
            dying.start()
            #expect(waitUntil { first.hasCrashed })
            dying.stop()

            // A new process finds only what reached the disk, while the agents keep working.
            try work(on: stub, sessions: ["d"])
            let second = Hub(machine: machine, stateURL: state)
            let link = second.link(audit: nil)
            link.start()
            defer { link.stop() }
            let all = total + 5
            #expect(waitUntil { second.cursor.seq == Int64(all) }, "crash at \(crashAt): stopped at \(second.cursor.seq)")

            // Every prompt and result was announced exactly once, across both lives of the hub.
            let alerts = first.alertLog + second.alertLog
            let expected = ["a", "b", "c", "d"].flatMap { s in
                let base = (["a": 0, "b": 5, "c": 10, "d": 15][s] ?? 0)
                return ["\(s)@\(base + 3)", "\(s)@\(base + 5)"]
            }
            #expect(alerts.sorted() == expected.sorted(), "crash at \(crashAt)")
            #expect(Set(alerts).count == alerts.count, "crash at \(crashAt)")
            // And what's on screen agrees with an uninterrupted hub.
            #expect(second.sessions().map(\.id).sorted() == ["a", "b", "c", "d"].map { "remote/devbox/claude:\($0)" })
            #expect(second.sessions().allSatisfy { $0.mood == .done })
        }
    }

    @Test func theHookStaysWithinItsLatencyBudget() throws {
        let stub = try StubMachine()
        _ = try stub.pair()
        let huge = String(repeating: "line of \"quoted\" tool output\n", count: 8_000)
        var small: [TimeInterval] = []
        var large: [TimeInterval] = []
        for _ in 0..<30 {
            small.append(try stub.emit(["session_id": "s", "hook_event_name": "PreToolUse", "cwd": "/x", "tool_name": "Bash"]))
            large.append(try stub.emit(["session_id": "s", "hook_event_name": "PostToolUse", "cwd": "/x", "tool_name": "Bash",
                                        "tool_response": ["stdout": huge]]))
        }
        small.sort()
        large.sort()
        // The target is about 10 ms; measured 12 ms under dash on a laptop. These limits are for a loaded CI machine and
        // the slower macOS /bin/sh. They're here to catch the shape of the problem: parsing that grows with the payload
        // took half a second per event before the tokenizer stopped rejoining strings.
        #expect(small[small.count / 2] < 0.1, "median \(small[small.count / 2])")
        #expect(large[large.count / 2] < 0.3, "median \(large[large.count / 2])")
    }

    @Test func aFailingSpoolNeverFailsTheHook() throws {
        let stub = try StubMachine()
        _ = try stub.pair()
        // The spool can't be written: emit still exits 0, which `emit` here asserts.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: stub.spool.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.spool.path) }
        try stub.hook("PreToolUse", ["tool_name": "Bash"])
        // Nor do payloads it can't read.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #"printf 'not json' | HOME="$0" /bin/sh "$1" emit claude"#, stub.home.path, stub.shim.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func aMalformedSpoolLineIsRejectedAndAudited() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        try stub.hook("UserPromptSubmit")
        try stub.appendToSpool(#"{"event":{"_0":{"agent":"claude","sessionId":"x","kind":{"sessionEnded":{}}}},"secret":"hunter2"}"# + "\n")
        try stub.appendToSpool("not json at all, with a secret: hunter2\n")
        try stub.appendToSpool(#"{"v":1,"seq":2,"id":"\#(String(repeating: "c", count: 32))","ts":\#(Int(Date().timeIntervalSince1970)),"agent":"claude","session":"forged","kind":"needsInput","host":{"agentPid":1,"tty":"/dev/ttys001"}}"# + "\n")
        try stub.hook("PreToolUse", ["tool_name": "Bash"])

        let audit = stub.paths.remoteAudit
        let link = hub.link(audit: audit)
        link.start()
        #expect(waitUntil { hub.sessions().first?.activity == .tool(name: "Bash", detail: nil) })
        link.stop()

        #expect(hub.sessions().map(\.sessionId) == ["s1"])
        #expect(hub.sessions().first?.host == nil)
        let rejected = audit.records().filter { $0.action == .rejected }
        #expect(Set(rejected.compactMap(\.detail)) == ["notJSON", "tooDeep", "unknownField"], "\(rejected)")
        #expect(rejected.compactMap(\.count).reduce(0, +) == 3, "\(rejected)")
        #expect(try !String(contentsOf: audit.url, encoding: .utf8).contains("hunter2"))
    }

    @Test func aReplayedPromptFromLongAgoIsMissedWithoutAChime() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        try stub.hook("UserPromptSubmit")
        try stub.hook("PermissionRequest", ["tool_name": "Bash"])
        // Two hours pass with the hub asleep.
        let then = Int(Date().timeIntervalSince1970) - 7_200
        let file = stub.spool.appendingPathComponent("events.jsonl")
        let aged = try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: #""ts":\d+"#, with: "\"ts\":\(then)", options: .regularExpression)
        try aged.write(to: file, atomically: true, encoding: .utf8)

        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        let link = hub.link(audit: nil)
        link.start()
        defer { link.stop() }
        #expect(waitUntil { hub.sessions().first?.origin?.missed == true })
        #expect(hub.alertLog.isEmpty)
        let s = try #require(hub.sessions().first)
        #expect(s.mood == .waiting)
        #expect(Describe.remoteState(s) == "Missed")

        // What happens next on the machine is live again.
        try stub.hook("Stop")
        #expect(waitUntil { hub.alertLog.count == 1 })
        #expect(hub.sessions().first?.origin?.missed == false)
    }

    @Test func aChangedMachineStopsTheLinkUntilApproved() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        try Data((String(repeating: "f", count: 32) + "\n").utf8).write(to: stub.home.appendingPathComponent(".ambient/remote.id"))

        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        let link = hub.link(audit: stub.paths.remoteAudit)
        link.start()
        defer { link.stop() }
        #expect(waitUntil { hub.healthLog.contains { if case .revoked = $0 { true } else { false } } })
        #expect(!hub.healthLog.contains(.connected))
        #expect(stub.paths.remoteAudit.records().contains { $0.action == .fingerprintChanged })

        // Pairing again doesn't quietly accept it.
        #expect {
            _ = try RemotePairing.pair(.init(id: "devbox", transport: stub.transport), shim: RemoteShim(url: shimURL),
                                       existing: machine, audit: nil)
        } throws: { error in
            if case RemotePairing.Failure.identityChanged = error { return true }
            return false
        }
        let approved = try RemotePairing.pair(.init(id: "devbox", transport: stub.transport, acceptNewIdentity: true),
                                              shim: RemoteShim(url: shimURL), existing: machine, audit: nil)
        #expect(approved.machine.fingerprint == "id:" + String(repeating: "f", count: 32))
    }

    @Test func aDifferentMachineIsLeftAsItWas() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()

        // The transport now reaches another machine, which has its own shim and its own settings.
        try Data((String(repeating: "f", count: 32) + "\n").utf8).write(to: stub.home.appendingPathComponent(".ambient/remote.id"))
        let settings = stub.home.appendingPathComponent(".claude/settings.json")
        try Data("{}".utf8).write(to: settings)
        var theirShim = try Data(contentsOf: stub.shim)
        theirShim.append(Data("# this machine's own copy\n".utf8))
        try theirShim.write(to: stub.shim)

        #expect {
            _ = try RemotePairing.pair(.init(id: "devbox", transport: stub.transport), shim: RemoteShim(url: shimURL),
                                       existing: machine, audit: stub.paths.remoteAudit)
        } throws: { error in
            if case RemotePairing.Failure.identityChanged = error { return true }
            return false
        }
        #expect(try Data(contentsOf: settings) == Data("{}".utf8))
        #expect(try Data(contentsOf: stub.shim) == theirShim)
        #expect(stub.paths.remoteAudit.records().filter { $0.action == .fingerprintChanged }.count == 1)
    }

    @Test func aDifferentMachineWithNoShimIsStillRefused() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        try Data((String(repeating: "f", count: 32) + "\n").utf8).write(to: stub.home.appendingPathComponent(".ambient/remote.id"))
        try FileManager.default.removeItem(at: stub.shim)

        #expect {
            _ = try RemotePairing.pair(.init(id: "devbox", transport: stub.transport), shim: RemoteShim(url: shimURL),
                                       existing: machine, audit: nil)
        } throws: { error in
            if case RemotePairing.Failure.identityChanged = error { return true }
            return false
        }
    }

    @Test func theLinkReconnectsAndARebuiltSpoolStartsOver() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        var options = RemoteLink.Options()
        options.backoff.base = 0.05
        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        try work(on: stub, sessions: ["a"])
        let link = hub.link(options: options, audit: stub.paths.remoteAudit)
        link.start()
        defer { link.stop() }
        #expect(waitUntil { hub.cursor.seq == 5 })

        // The machine is rebuilt: new spool, new epoch, seq back to 1. `follow` hangs up, and the link starts again.
        try FileManager.default.removeItem(at: stub.spool)
        try stub.hook("UserPromptSubmit", session: "b")
        #expect(waitUntil { hub.sessions().contains { $0.sessionId == "b" } })
        #expect(hub.cursor.seq == 1)
        #expect(hub.healthLog.contains { if case .reconnecting = $0 { true } else { false } })
        #expect(hub.healthLog.filter { $0 == .connected }.count >= 2)
        #expect(stub.paths.remoteAudit.records().contains { $0.action == .spoolReset })

        // A session from before the rebuild goes on, with a seq far below the one it remembers.
        try stub.hook("UserPromptSubmit", session: "a")
        #expect(waitUntil { hub.sessions().first { $0.sessionId == "a" }?.activity == .thinking })
    }

    @Test func aFloodIsHeldBackOnlyAsLongAsTheLimitSays() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        let link = hub.link(audit: nil)
        link.start()
        defer { link.stop() }
        #expect(waitUntil { hub.healthLog.contains(.connected) })

        // 300 past the burst of 500, so about 6 s at 50 a second. Adding up each event's wait would take minutes.
        let count = 800, now = Int(Date().timeIntervalSince1970)
        try Data().write(to: stub.spool.appendingPathComponent("events.jsonl"))
        try stub.appendToSpool((1...count).map {
            #"{"v":1,"seq":\#($0),"id":"\#(String(format: "%032x", $0))","ts":\#(now),"agent":"claude","session":"s1","kind":"toolStarted"}"# + "\n"
        }.joined())
        try "\(count) 0\n".write(to: stub.spool.appendingPathComponent("seq"), atomically: true, encoding: .utf8)
        #expect(waitUntil(20) { hub.cursor.seq == Int64(count) })
    }

    @Test func pairingAgainStartsANewLink() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        let again = try RemotePairing.pair(.init(id: machine.id, label: machine.label, transport: machine.transport),
                                           shim: RemoteShim(url: shimURL), existing: machine, audit: nil)
        // The coordinator restarts a link when its machine changes, which is what puts the new shim and level to work.
        #expect(again.machine != machine)
        #expect(again.machine.fingerprint == machine.fingerprint)
    }

    @Test func pairingKeepsASymlinkedConfigALink() throws {
        let stub = try StubMachine()
        let dotfile = stub.home.appendingPathComponent("dotfiles-settings.json")
        try Data("{}".utf8).write(to: dotfile)
        let config = stub.home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: dotfile)

        _ = try stub.pair()
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: config.path) == dotfile.path)
        #expect(try String(contentsOf: dotfile, encoding: .utf8).contains("ambient-remote"))
    }

    @Test func anUnreachableMachineRetriesWithoutAFuss() throws {
        let stub = try StubMachine()
        let machine = Machine(id: "gone", transport: ["/bin/sh", "-c", "echo 'ssh: connect to host gone port 22: No route to host' >&2; exit 255", "stub"],
                              fingerprint: "id:" + String(repeating: "0", count: 32))
        var options = RemoteLink.Options()
        options.backoff.base = 0.02
        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        let link = hub.link(options: options, audit: stub.paths.remoteAudit)
        link.start()
        defer { link.stop() }
        #expect(waitUntil { hub.healthLog.filter { if case .reconnecting = $0 { true } else { false } }.count >= 3 })
        #expect(!stub.paths.remoteAudit.records().contains { $0.action == .linkUp })
    }

    @Test func aShimThatCantBeUnderstoodAsksForAnUpdate() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        // A future shim whose handshake has moved on.
        var script = try String(contentsOf: stub.shim, encoding: .utf8)
        script = script.replacingOccurrences(of: #""identity":"%s","ts":%s'"#, with: #""identity":"%s","ts":%s,"future":1'"#)
        try script.write(to: stub.shim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.shim.path)

        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        let link = hub.link(audit: nil)
        link.start()
        defer { link.stop() }
        #expect(waitUntil { hub.healthLog.contains { if case .upgradeNeeded = $0 { true } else { false } } })

        // Pairing again is what fixes it, even though this shim's `status` can't be read either.
        let shim = try RemoteShim(url: shimURL)
        let again = try RemotePairing.pair(.init(id: machine.id, transport: machine.transport), shim: shim, existing: machine, audit: nil)
        #expect(again.status.hello.shim == shim.version)
    }

    @Test func aRefusedSignInAsksForIt() throws {
        let stub = try StubMachine()
        let machine = Machine(id: "locked", transport: ["/bin/sh", "-c", "echo 'dev@locked: Permission denied (publickey).' >&2; exit 255", "stub"],
                              fingerprint: "id:" + String(repeating: "0", count: 32))
        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        let link = hub.link(audit: stub.paths.remoteAudit)
        link.start()
        defer { link.stop() }
        #expect(waitUntil { hub.healthLog.contains { if case .signInNeeded = $0 { true } else { false } } })
        #expect(stub.paths.remoteAudit.records().contains { $0.action == .signInNeeded })
    }

    @Test func followReportsWhenTheAgentExits() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        try stub.hook("UserPromptSubmit")
        // A session whose agent is gone. Its pid stays on the remote: nothing about it reaches the hub.
        let live = stub.spool.appendingPathComponent("live/claude.s1")
        try Data("999999\n\napi\n\n".utf8).write(to: live)

        let hub = Hub(machine: machine, stateURL: stub.hub.appendingPathComponent("state.json"))
        let link = hub.link(audit: nil)
        link.start()
        defer { link.stop() }
        #expect(waitUntil { hub.cursor.seq == 2 && hub.sessions().isEmpty })
        #expect(!FileManager.default.fileExists(atPath: live.path))
    }

    @Test func doctorSeesEachPartOfTheLink() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        let shim = try RemoteShim(url: shimURL)
        let levels = { (checks: [RemoteDoctor.Check]) in checks.filter { $0.level == .fail }.map(\.text) }
        let good = RemoteDoctor.check(machine, shim: shim, cursor: nil)
        #expect(levels(good).isEmpty, "\(good)")
        #expect(good.contains { $0.text.contains("Identity matches") })
        #expect(good.contains { $0.text == "Claude Code: hooks installed" })

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.spool.path)
        #expect(levels(RemoteDoctor.check(machine, shim: shim, cursor: nil)).contains { $0.contains("permissions") })
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.spool.path)

        var tampered = try Data(contentsOf: stub.shim)
        tampered.append(Data("# edited\n".utf8))
        try tampered.write(to: stub.shim)
        #expect(levels(RemoteDoctor.check(machine, shim: shim, cursor: nil)).contains { $0.contains("checksum") })

        let dead = Machine(id: "gone", transport: ["/bin/sh", "-c", "exit 255", "stub"], fingerprint: machine.fingerprint)
        #expect(RemoteDoctor.check(dead, shim: shim, cursor: nil).map(\.level) == [.fail])
    }

    @Test func removingAndPurgingLeaveNothingBehind() throws {
        let stub = try StubMachine()
        let machine = try stub.pair()
        let paths = stub.paths
        try FileManager.default.createDirectory(at: paths.home, withIntermediateDirectories: true)
        let store = SessionStore()
        let e = RemoteEvent(seq: 1, id: String(repeating: "1", count: 32), ts: Date(), agent: .claude, session: "s1", kind: .turnCompleted,
                            project: "secret-project")
        let change = try #require(store.apply(e, from: machine.ref, at: e.ts))
        let tasks = TaskStore()
        tasks.observe(change)
        var day = DayLog(now: Date())
        day.apply(change, now: Date())
        let local = AgentEvent(agent: .codex, sessionId: "mine", cwd: "/x", kind: .promptSubmitted)
        store.apply(local)
        try StateFile.save(store.sessions, cursors: ["devbox": RemoteCursor(seq: 1, epoch: "e"), "ci": RemoteCursor(seq: 2)], to: paths.stateFile)
        try TaskFile.save(tasks.tasks, to: paths.tasksFile)
        try DayLogFile.save(day, to: paths.dayFile)

        try RemotePurge.scrub(machine: "devbox", paths: paths)
        #expect(StateFile.load(from: paths.stateFile).map(\.id) == ["codex:mine"])
        #expect(StateFile.loadCursors(from: paths.stateFile) == ["ci": RemoteCursor(seq: 2)])
        #expect(TaskFile.load(from: paths.tasksFile).isEmpty)
        #expect(DayLogFile.load(from: paths.dayFile)?.moments.isEmpty == true)
        for file in [paths.stateFile, paths.tasksFile, paths.dayFile] {
            #expect(try !String(contentsOf: file, encoding: .utf8).contains("secret-project"))
        }
        // A running app picks the rest up from the marker, once.
        #expect(RemotePurge.pendingPurges(paths: paths) == ["devbox"])
        RemotePurge.clearPurge("devbox", paths: paths)
        #expect(RemotePurge.pendingPurges(paths: paths).isEmpty)
    }

    /// The same path over real ssh, with a throwaway sshd on loopback, its own keys, and a forced command that keeps
    /// everything in a temp home. Opens a port for as long as it runs, so it's opt-in: `AMBIENT_TEST_SSHD=1 swift test`.
    @Test func overARealSSHServer() throws {
        guard ProcessInfo.processInfo.environment["AMBIENT_TEST_SSHD"] != nil else { return }
        let stub = try StubMachine()
        let root = stub.home.deletingLastPathComponent()
        func path(_ name: String) -> String { root.appendingPathComponent(name).path }
        func keygen(_ name: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            process.arguments = ["-q", "-t", "ed25519", "-N", "", "-f", path(name)]
            try process.run()
            process.waitUntilExit()
        }
        try keygen("host_key")
        try keygen("client_key")
        try FileManager.default.copyItem(atPath: path("client_key.pub"), toPath: path("authorized_keys"))
        let port = Int.random(in: 42_000...58_000)
        try """
        ListenAddress 127.0.0.1
        Port \(port)
        HostKey \(path("host_key"))
        AuthorizedKeysFile \(path("authorized_keys"))
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        UsePAM no
        StrictModes no
        PidFile \(path("sshd.pid"))
        ForceCommand /bin/sh -c 'HOME=\(stub.home.path); export HOME; cd "$HOME" && exec /bin/sh -c "$SSH_ORIGINAL_COMMAND"'
        """.write(toFile: path("sshd_config"), atomically: true, encoding: .utf8)

        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
        server.arguments = ["-D", "-e", "-f", path("sshd_config")]
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { server.terminate() }

        stub.transportOverride = ["ssh", "-F", "/dev/null", "-p", "\(port)", "-i", path("client_key"), "-o", "IdentitiesOnly=yes",
                                  "-o", "UserKnownHostsFile=\(path("known_hosts"))", "-o", "StrictHostKeyChecking=accept-new",
                                  "-o", "BatchMode=yes", "127.0.0.1"]
        var machine: Machine?
        let paired = waitUntil(10) {
            machine = try? stub.pair()
            return machine != nil
        }
        #expect(paired)
        let pinned = try #require(machine)
        #expect(pinned.fingerprint.hasPrefix("SHA256:"))

        try work(on: stub, sessions: ["a", "b"])
        let state = stub.hub.appendingPathComponent("state.json")
        let first = Hub(machine: pinned, stateURL: state)
        first.crashAt = 4
        let dying = first.link(audit: nil)
        dying.start()
        #expect(waitUntil { first.hasCrashed })
        dying.stop()

        let second = Hub(machine: pinned, stateURL: state)
        let link = second.link(audit: nil)
        link.start()
        defer { link.stop() }
        #expect(waitUntil { second.cursor.seq == 10 })
        let alerts = (first.alertLog + second.alertLog).sorted()
        #expect(alerts == ["a@3", "a@5", "b@8", "b@10"].sorted())
    }
}
