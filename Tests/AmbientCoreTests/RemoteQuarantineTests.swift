import Foundation
import Testing
@testable import AmbientCore

private let t0 = Date(timeIntervalSince1970: 1_761_600_000)
private let devbox = MachineRef(id: "devbox", label: "Devbox")

private func remote(_ kind: RemoteEvent.Kind, seq: Int64, session: String = "s1", agent: AgentKind = .claude,
                    tool: String? = nil, reason: String? = nil, message: String? = nil, title: String? = nil) -> RemoteEvent {
    RemoteEvent(seq: seq, id: String(format: "%032x", seq), ts: t0.addingTimeInterval(Double(seq)), agent: agent,
                session: session, kind: kind, project: "api", tool: tool, title: title, reason: reason, message: message)
}

@discardableResult
private func apply(_ store: SessionStore, _ e: RemoteEvent, machine: MachineRef = devbox) -> SessionChange? {
    store.apply(e, from: machine, at: e.ts)
}

/// Remote sessions are data: no focus route, pid check, tty, tmux or AppleScript ever runs for them (ER-8).
@Suite struct RemoteQuarantineTests {
    @Test func remoteSessionsAreKeyedByMachineAndNeverHaveAHost() throws {
        let store = SessionStore()
        apply(store, remote(.promptSubmitted, seq: 1))
        apply(store, remote(.toolStarted, seq: 2, tool: "Bash"))
        let s = try #require(store.sessions.first)
        #expect(s.id == "remote/devbox/claude:s1")
        #expect(s.origin?.machine == devbox)
        #expect(s.origin?.lastSeq == 2)
        #expect(s.project == "api")
        #expect(s.host == nil)
        #expect(s.cwd == nil)
        #expect(s.activity == .tool(name: "Bash", detail: nil))
    }

    @Test func theSameSessionIdOnTwoMachinesAndLocallyStaysThree() {
        let store = SessionStore()
        apply(store, remote(.promptSubmitted, seq: 1))
        apply(store, remote(.promptSubmitted, seq: 1), machine: MachineRef(id: "ci", label: "CI"))
        store.apply(AgentEvent(agent: .claude, sessionId: "s1", cwd: "/src/api", kind: .promptSubmitted, timestamp: t0,
                               host: HostInfo(bundleId: "com.apple.Terminal", agentPid: 42)))
        #expect(Set(store.sessions.map(\.id)) == ["remote/devbox/claude:s1", "remote/ci/claude:s1", "claude:s1"])
        // A local event can't reach a remote session, even when its session id looks like one.
        store.apply(AgentEvent(agent: .claude, sessionId: "remote/devbox/claude:s1", cwd: nil, kind: .sessionEnded, timestamp: t0))
        #expect(store.session(id: "remote/devbox/claude:s1") != nil)
        #expect(store.session(id: "claude:s1")?.host?.agentPid == 42)
    }

    @Test func remoteEventsAreOrderedBySeqNotByClock() {
        let store = SessionStore()
        apply(store, remote(.promptSubmitted, seq: 5))
        // An older or repeated seq changes nothing, even with a later remote time.
        let late = RemoteEvent(seq: 4, id: String(repeating: "a", count: 32), ts: t0.addingTimeInterval(9_999), agent: .claude,
                               session: "s1", kind: .turnCompleted)
        #expect(store.apply(late, from: devbox, at: late.ts) == nil)
        #expect(apply(store, remote(.promptSubmitted, seq: 5)) == nil)
        #expect(store.sessions.first?.activity == .thinking)
        // A newer seq with an earlier clock still applies, and time never runs backwards.
        let skewed = RemoteEvent(seq: 6, id: String(repeating: "b", count: 32), ts: t0, agent: .claude, session: "s1",
                                 kind: .turnCompleted)
        #expect(store.apply(skewed, from: devbox, at: skewed.ts) != nil)
        #expect(store.sessions.first?.lastEventAt == t0.addingTimeInterval(5))
    }

    @Test func remoteSessionsHaveNoFocusRoutes() throws {
        let store = SessionStore()
        apply(store, remote(.needsInput, seq: 1, reason: "permission", message: "Bash: rm -rf /"))
        let s = try #require(store.sessions.first)
        #expect(FocusPlanner.routes(for: s).isEmpty)
        // Even a remote session carrying a forged host (say, from a tampered state file) gets no routes.
        var forged = s
        forged.host = HostInfo(bundleId: "com.apple.Terminal", termProgram: "Apple_Terminal", pids: [1], agentPid: 1,
                               tty: "/dev/ttys001", hostSessionId: "local_abc", tmuxSocket: "/tmp/tmux", tmuxPane: "%1")
        #expect(FocusPlanner.routes(for: forged).isEmpty)
        // The same host on a local session would have produced routes.
        var local = Session(agent: .claude, sessionId: "s1", at: t0)
        local.host = forged.host
        #expect(!FocusPlanner.routes(for: local).isEmpty)
    }

    @Test func sweepNeverChecksARemotePid() {
        var checked: [Int32] = []
        let store = SessionStore(isAlive: { checked.append($0); return false })
        apply(store, remote(.promptSubmitted, seq: 1))
        store.apply(AgentEvent(agent: .codex, sessionId: "local", cwd: "/x", kind: .promptSubmitted, timestamp: t0,
                               host: HostInfo(agentPid: 777)))
        // A forged pid on a restored remote session is dropped on load and never checked.
        var forged = store.sessions.first { $0.isRemote }!
        forged.host = HostInfo(pids: [1], agentPid: 1)
        store.load(store.sessions.filter { !$0.isRemote } + [forged])
        #expect(store.sessions.first { $0.isRemote }?.host == nil)

        store.sweep(now: t0.addingTimeInterval(10))
        #expect(checked == [777])
        #expect(store.session(id: "codex:local") == nil)
        #expect(store.session(id: "remote/devbox/claude:s1") != nil)
    }

    @Test func hostAppAcknowledgementSkipsRemoteSessions() {
        let store = SessionStore()
        apply(store, remote(.turnCompleted, seq: 1))
        var forged = store.sessions[0]
        forged.host = HostInfo(bundleId: "com.apple.Terminal")
        store.load([forged])
        #expect(store.acknowledge(hostBundleId: "com.apple.Terminal").isEmpty)
        #expect(store.sessions[0].mood == .done)
    }

    @Test func titlesAreNeverReadFromLocalTranscriptsForRemoteSessions() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent(".claude/projects/p")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data(#"{"type":"custom-title","customTitle":"Local secret"}"#.utf8 + [0x0A])
            .write(to: project.appendingPathComponent("abc-123.jsonl"))
        let titles = SessionTitles(userHome: home)

        #expect(titles.title(for: Session(agent: .claude, sessionId: "abc-123", at: t0)) == "Local secret")
        let remoteSession = Session(agent: .claude, sessionId: "abc-123", at: t0, origin: RemoteOrigin(machine: devbox))
        #expect(titles.title(for: remoteSession) == nil)
        #expect(titles.excerpt(for: remoteSession) == nil)
    }

    @Test func titleEventsNameAnExistingSessionOnly() {
        let store = SessionStore()
        #expect(apply(store, remote(.titleChanged, seq: 1, title: "Orphan")) == nil)
        #expect(store.sessions.isEmpty)
        apply(store, remote(.promptSubmitted, seq: 2))
        let change = apply(store, remote(.titleChanged, seq: 3, title: "Fix login"))
        #expect(change?.session.title == "Fix login")
        #expect(store.sessions.first?.activity == .thinking)
    }

    @Test func agentExitEndsTheSession() {
        let store = SessionStore()
        apply(store, remote(.promptSubmitted, seq: 1))
        let change = apply(store, remote(.agentExited, seq: 2))
        #expect(change?.removed == true)
        #expect(store.sessions.isEmpty)
    }

    @Test func remoteSessionsSurviveAStateFileRoundTrip() throws {
        let store = SessionStore()
        apply(store, remote(.needsInput, seq: 3, reason: "question", message: "Which branch?"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try StateFile.save(store.sessions, to: url)
        let restored = StateFile.load(from: url)
        #expect(restored == store.sessions)
        #expect(restored.first?.origin?.lastSeq == 3)
    }

    @Test func theDefaultTransportForwardsNothing() {
        let transport = Machine.defaultTransport(host: "devbox")
        #expect(transport.last == "devbox")
        for option in ["ForwardAgent=no", "ForwardX11=no", "ClearAllForwardings=yes"] {
            let at = transport.firstIndex(of: option)
            #expect(at != nil && transport[at! - 1] == "-o", "\(option)")
        }
    }

    @Test func aHostIsNeverAnOption() {
        #expect(Machine.isValidHost("devbox"))
        #expect(Machine.isValidHost("dev@10.0.0.1"))
        #expect(!Machine.isValidHost("-oProxyCommand=touch /tmp/x"))
        #expect(!Machine.isValidHost("-J"))
        #expect(!Machine.isValidHost(""))
    }

    @Test func machineIdsAndFingerprintsAreStrict() {
        #expect(Machine.isValidID("devbox"))
        #expect(Machine.isValidID("gpu-01.lab"))
        #expect(!Machine.isValidID("Devbox"))
        #expect(!Machine.isValidID("-x"))
        #expect(!Machine.isValidID("a/b"))
        #expect(!Machine.isValidID("a b"))
        #expect(!Machine.isValidID(String(repeating: "a", count: 33)))
        #expect(Machine.isValidFingerprint("SHA256:" + String(repeating: "A", count: 43)))
        #expect(Machine.isValidFingerprint("id:" + String(repeating: "0", count: 32)))
        #expect(!Machine.isValidFingerprint("SHA256:short"))
        #expect(!Machine.isValidFingerprint("MD5:aa:bb"))
        #expect(Machine(id: "devbox", transport: ["ssh", "devbox"], fingerprint: "id:" + String(repeating: "0", count: 32)).label == "devbox")
    }
}
