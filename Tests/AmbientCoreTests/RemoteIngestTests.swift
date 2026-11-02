import Foundation
import Testing
@testable import AmbientCore

private let now = Date(timeIntervalSince1970: 1_761_600_000)
private let pin = "id:" + String(repeating: "a", count: 32)
private let machine = Machine(id: "devbox", label: "Devbox", transport: ["ssh", "devbox"], fingerprint: pin)

private func hello(seq: Int64 = 10, epoch: String = "0123456789abcdef", identity: String = pin, proto: Int = 1,
                   ts: Date = now, level: String = "standard") -> Data {
    Data(#"{"v":1,"type":"hello","shim":"1.0.0","proto":\#(proto),"caps":"exit,title,heartbeat","level":"\#(level)","seq":\#(seq),"epoch":"\#(epoch)","identity":"\#(identity)","ts":\#(Int(ts.timeIntervalSince1970))}"#.utf8)
}

private func event(_ seq: Int64, kind: String = "toolStarted", id: String? = nil, ts: Date = now, extra: String = "") -> Data {
    let eventID = id ?? String(format: "%032x", seq)
    return Data(#"{"v":1,"seq":\#(seq),"id":"\#(eventID)","ts":\#(Int(ts.timeIntervalSince1970)),"agent":"claude","session":"s1","kind":"\#(kind)"\#(extra)}"#.utf8)
}

private func delivery(_ output: RemoteIngestOutput) -> RemoteDelivery? {
    if case let .deliver(d) = output { return d }
    return nil
}

private func auditFile() -> RemoteAudit {
    RemoteAudit(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/audit.jsonl"))
}

@Suite struct RemoteIngestTests {
    @Test func nothingCountsBeforeTheHandshake() {
        let audit = auditFile()
        let ingest = RemoteIngest(machine: machine, cursor: .init(), audit: audit)
        #expect(ingest.receive(event(1), now: now) == .dropped)
        #expect(ingest.cursor.seq == 0)
        #expect(audit.records().map(\.detail) == ["invalid"])
        guard case .linked = ingest.receive(hello(), now: now) else { Issue.record("no link"); return }
        #expect(delivery(ingest.receive(event(1), now: now)) != nil)
    }

    @Test func aChangedIdentityStopsTheLink() {
        let audit = auditFile()
        let other = "SHA256:" + String(repeating: "B", count: 43)
        let ingest = RemoteIngest(machine: machine, cursor: .init(), audit: audit)
        #expect(ingest.receive(hello(identity: other), now: now) == .refused(.fingerprintChanged(expected: pin, got: other)))
        #expect(ingest.receive(event(1), now: now) == .dropped)
        #expect(audit.records().first?.action == .fingerprintChanged)
    }

    @Test func aDifferentProtocolAsksForAnUpgrade() {
        let ingest = RemoteIngest(machine: machine, cursor: .init())
        guard case .refused(.upgradeNeeded) = ingest.receive(hello(proto: 99), now: now) else {
            Issue.record("no upgrade prompt")
            return
        }
        // So does an event from a newer shim, rather than vanishing silently (ER-34).
        let linked = RemoteIngest(machine: machine, cursor: .init())
        _ = linked.receive(hello(), now: now)
        let newer = Data(#"{"v":99,"seq":1,"id":"\#(String(repeating: "0", count: 32))","ts":1,"agent":"claude","session":"s","kind":"notice"}"#.utf8)
        guard case .refused(.upgradeNeeded) = linked.receive(newer, now: now) else {
            Issue.record("no upgrade prompt")
            return
        }
    }

    @Test func aNewSpoolRestartsFromTheBeginning() {
        let audit = auditFile()
        let ingest = RemoteIngest(machine: machine, cursor: .init(seq: 500, epoch: "0123456789abcdef"), audit: audit)
        #expect(ingest.receive(hello(seq: 3, epoch: "fedcba9876543210"), now: now) == .restart)
        #expect(ingest.cursor == RemoteCursor(seq: 0, epoch: "fedcba9876543210"))
        #expect(audit.records().first?.action == .spoolReset)
        // The same epoch going backwards is a reset too.
        let same = RemoteIngest(machine: machine, cursor: .init(seq: 500, epoch: "0123456789abcdef"))
        #expect(same.receive(hello(seq: 3), now: now) == .restart)
    }

    @Test func deduplicatesBySeqAndByEventID() {
        let ingest = RemoteIngest(machine: machine, cursor: .init())
        _ = ingest.receive(hello(), now: now)
        #expect(delivery(ingest.receive(event(1), now: now)) != nil)
        #expect(ingest.receive(event(1), now: now) == .dropped)
        #expect(delivery(ingest.receive(event(2), now: now)) != nil)
        #expect(ingest.receive(event(1), now: now) == .dropped)
        // A new seq carrying an old id is the same event.
        #expect(ingest.receive(event(3, id: String(format: "%032x", 2)), now: now) == .dropped)
        #expect(ingest.duplicates == 3)
        #expect(ingest.delivered == 2)
    }

    @Test func aGapInTheSpoolIsRecorded() {
        let audit = auditFile()
        let ingest = RemoteIngest(machine: machine, cursor: .init(seq: 4, epoch: "0123456789abcdef"), audit: audit)
        _ = ingest.receive(hello(), now: now)
        _ = ingest.receive(event(9), now: now)
        #expect(audit.records().first?.action == .spoolGap)
        #expect(audit.records().first?.count == 4)
    }

    @Test func oldReplayedAlertsAreMissedAndFreshOnesAreNot() {
        let ingest = RemoteIngest(machine: machine, cursor: .init())
        _ = ingest.receive(hello(seq: 3), now: now)
        let old = now.addingTimeInterval(-3_600)
        #expect(delivery(ingest.receive(event(1, kind: "needsInput", ts: old), now: now))?.missed == true)
        #expect(delivery(ingest.receive(event(2, kind: "toolStarted", ts: old), now: now))?.missed == false)
        #expect(delivery(ingest.receive(event(3, kind: "needsInput", ts: now.addingTimeInterval(-60)), now: now))?.missed == false)
        // Past the handshake's head it's live, however odd its clock.
        #expect(delivery(ingest.receive(event(4, kind: "needsInput", ts: old), now: now))?.missed == false)
    }

    @Test func clockSkewIsCorrectedAndNeverInTheFuture() {
        let ingest = RemoteIngest(machine: machine, cursor: .init())
        // The remote clock is two hours fast.
        let remoteNow = now.addingTimeInterval(7_200)
        _ = ingest.receive(hello(seq: 5, ts: remoteNow), now: now)
        let d = delivery(ingest.receive(event(1, kind: "needsInput", ts: remoteNow.addingTimeInterval(-30)), now: now))
        #expect(d?.at == now.addingTimeInterval(-30))
        #expect(d?.missed == false)
        // Small differences are left alone, but nothing lands after the moment it arrived.
        let close = RemoteIngest(machine: machine, cursor: .init())
        _ = close.receive(hello(ts: now.addingTimeInterval(30)), now: now)
        #expect(delivery(close.receive(event(1, ts: now.addingTimeInterval(30)), now: now))?.at == now)
    }

    @Test func rejectionsAreCountedWithoutContentAndCannotFillTheLog() throws {
        let audit = auditFile()
        let ingest = RemoteIngest(machine: machine, cursor: .init(), audit: audit)
        _ = ingest.receive(hello(), now: now)
        for i in 0..<1_000 {
            #expect(ingest.receive(Data(#"{"secret":"hunter2-\#(i)"}"#.utf8), now: now.addingTimeInterval(Double(i) / 100)) == .dropped)
        }
        ingest.flush(now: now.addingTimeInterval(10))
        let records = audit.records()
        #expect(ingest.rejected == 1_000)
        #expect(records.map(\.detail) == ["unknownField", "unknownField"])
        #expect(records.compactMap(\.count).reduce(0, +) == 1_000)
        let raw = try String(contentsOf: audit.url, encoding: .utf8)
        #expect(!raw.contains("hunter2"))
    }

    @Test func aReplayRunsFreeAndALiveFloodIsHeldBack() {
        let audit = auditFile()
        let ingest = RemoteIngest(machine: machine, cursor: .init(), limiter: RemoteRateLimiter(rate: 50, burst: 2), audit: audit)
        _ = ingest.receive(hello(seq: 100), now: now)
        for seq in Int64(1)...100 {
            #expect(ingest.delay(after: RemoteEvent(seq: seq, id: "", ts: now, agent: .claude, session: "s", kind: .notice), now: now) == 0)
        }
        func live(_ seq: Int64) -> TimeInterval {
            ingest.delay(after: RemoteEvent(seq: seq, id: "", ts: now, agent: .claude, session: "s", kind: .notice), now: now)
        }
        #expect(live(101) == 0)
        #expect(live(102) == 0)
        #expect(live(103) == 1.0 / 50)
        #expect(abs(live(104) - 2.0 / 50) < 1e-9)
        #expect(audit.records().map(\.action) == [.rateLimited])
    }

    /// `hello.seq` is whatever the machine says: this one says every event it will ever send is a replay.
    @Test func aForgedHandshakeDoesntBuyFreePacing() {
        let ingest = RemoteIngest(machine: machine, cursor: .init(), replayLimiter: RemoteRateLimiter(rate: 50, burst: 3))
        _ = ingest.receive(hello(seq: 1 << 53), now: now)
        func replay(_ seq: Int64, at: Date = now) -> TimeInterval {
            ingest.delay(after: RemoteEvent(seq: seq, id: "", ts: now, agent: .claude, session: "s", kind: .needsInput), now: at)
        }
        for seq in Int64(1)...3 { #expect(replay(seq) == 0) }
        #expect(replay(4) == 1.0 / 50)
        // Reconnecting doesn't refill it, only time does.
        ingest.beginConnection()
        _ = ingest.receive(hello(seq: 1 << 53), now: now)
        #expect(replay(5) > 0)
        #expect(replay(6, at: now.addingTimeInterval(1)) == 0)
    }

    @Test func aFullSpoolReplaysWithoutWaiting() {
        let ingest = RemoteIngest(machine: machine, cursor: .init())
        _ = ingest.receive(hello(seq: 1 << 53), now: now)
        func replay(_ seq: Int64) -> TimeInterval {
            ingest.delay(after: RemoteEvent(seq: seq, id: "", ts: now, agent: .claude, session: "s", kind: .toolStarted), now: now)
        }
        // 5 MB of the shortest lines real sessions write: a UUID for the session, and no project or tool.
        let spool = Int64(5 * 1024 * 1024 / 165)
        for seq in 1...spool { #expect(replay(seq) == 0) }
        var held = false
        for seq in (spool + 1)...(spool + 10_000) { held = held || replay(seq) > 0 }
        #expect(held)
    }

    @Test func gapsAndResetsCantFillTheLog() {
        let audit = auditFile()
        let ingest = RemoteIngest(machine: machine, cursor: .init(), audit: audit)
        _ = ingest.receive(hello(), now: now)
        for i in Int64(0)..<1_000 { _ = ingest.receive(event(i * 2 + 1), now: now) }
        for i in 1...1_000 {
            ingest.beginConnection()
            #expect(ingest.receive(hello(seq: 0, epoch: String(format: "%016x", i)), now: now) == .restart)
        }
        ingest.flush(now: now)
        let records = audit.records()
        #expect(records.count <= 4)
        #expect(records.filter { $0.action == .spoolGap }.compactMap(\.count).reduce(0, +) == 999)
        #expect(records.filter { $0.action == .spoolReset }.compactMap(\.count).reduce(0, +) == 1_000)
    }

    @Test func nothingAboveTheMachinesLevelGetsThrough() throws {
        let extra = #","tool":"Bash","title":"Fix the secret thing","message":"secret text""#
        for (level, names, text) in [("metadata", false, false), ("standard", true, false), ("full", true, true)] {
            let ingest = RemoteIngest(machine: machine, cursor: .init())
            _ = ingest.receive(hello(level: level), now: now)
            let e = try #require(delivery(ingest.receive(event(1, kind: "needsInput", extra: extra), now: now))).event
            #expect((e.tool != nil) == names, "\(level)")
            #expect((e.title != nil) == names, "\(level)")
            #expect((e.message != nil) == text, "\(level)")
        }
    }

    @Test func tokensRefillAtTheRate() {
        var limiter = RemoteRateLimiter(rate: 10, burst: 1)
        #expect(limiter.delay(now: now) == 0)
        #expect(limiter.delay(now: now) > 0)
        #expect(limiter.delay(now: now.addingTimeInterval(10)) == 0)
    }

    @Test func splitterHandlesChunksAndCapsLongLines() {
        var splitter = RemoteLineSplitter(cap: 8)
        #expect(splitter.feed(Data("ab".utf8)).isEmpty)
        #expect(splitter.feed(Data("c\nde\n\nf".utf8)) == [Data("abc".utf8), Data("de".utf8)])
        // Over the cap in one chunk, and across several: one oversized line either way, and the next is intact.
        var long = RemoteLineSplitter(cap: 8)
        #expect(long.feed(Data("0123456789\nok\n".utf8)).map(\.count) == [9, 2])
        #expect(long.feed(Data("01234567".utf8)).isEmpty)
        #expect(long.feed(Data("89".utf8)).isEmpty)
        #expect(long.feed(Data("ab\nok\n".utf8)).map(\.count) == [9, 2])
    }

    @Test func backoffGrowsToItsLimitWithJitter() {
        let backoff = RemoteBackoff()
        #expect(backoff.delay(attempt: 1, random: 0) == 1)
        #expect(backoff.delay(attempt: 4, random: 0) == 8)
        #expect(backoff.delay(attempt: 50, random: 0) == 60)
        #expect(backoff.delay(attempt: 4, random: 1) == 9.6)
        #expect(backoff.delay(attempt: 4, random: -1) == 6.4)
    }

    @Test func signInFailuresAreToldApartFromOutages() {
        #expect(RemoteLink.signInProblem("user@devbox: Permission denied (publickey).\n") != nil)
        #expect(RemoteLink.signInProblem("Host key verification failed.\r\n") == "Host key verification failed.")
        #expect(RemoteLink.signInProblem("ssh: connect to host devbox port 22: Operation timed out") == nil)
        #expect(RemoteLink.signInProblem("") == nil)
    }

    @Test func controlLinesHaveTheirOwnAllowlist() {
        func rejected(_ s: String) -> RemoteRejection? {
            do { _ = try RemoteLineDecoder.decode(Data(s.utf8)); return nil } catch { return error }
        }
        #expect(rejected(#"{"v":1,"type":"heartbeat","seq":3,"extra":1}"#) == .unknownField("extra"))
        #expect(rejected(#"{"v":1,"type":"open","seq":3}"#) == .invalid("type"))
        #expect(rejected(#"{"v":1,"type":"status","seq":3}"#) == .invalid("type"))
        #expect(rejected(#"{"v":1,"type":"hello"}"#) == .missingField("shim"))
        #expect(rejected(#"{"v":1,"type":["hello"]}"#) == .invalid("type"))
        let badShim = String(decoding: hello(), as: UTF8.self).replacingOccurrences(of: "1.0.0", with: "1 0;rm")
        #expect(rejected(badShim) == .invalid("shim"))
        let badIdentity = String(decoding: hello(identity: "nonsense"), as: UTF8.self)
        #expect(rejected(badIdentity) == .invalid("identity"))
    }
}

/// What the hub's surfaces do with a remote session's caveats.
@Suite struct RemoteStateTests {
    private let devbox = MachineRef(id: "devbox", label: "Devbox")

    private func remote(_ kind: RemoteEvent.Kind, seq: Int64, session: String = "s1", reason: String? = nil) -> RemoteEvent {
        RemoteEvent(seq: seq, id: String(format: "%032x", seq), ts: now, agent: .claude, session: session, kind: kind,
                    project: "api", title: nil, reason: reason)
    }

    private let settings = AlertPolicy.Settings(notifications: true, sounds: true, doneThreshold: 0, quiet: false)

    @Test func aMissedPromptShowsButNeverAlerts() throws {
        let store = SessionStore()
        store.apply(remote(.promptSubmitted, seq: 1), from: devbox, at: now)
        let change = try #require(store.apply(remote(.needsInput, seq: 2, reason: "permission"), from: devbox, at: now, missed: true))
        #expect(change.session.mood == .waiting)
        #expect(AlertPolicy.decide(change, settings: settings, hostIsFrontmost: false) == nil)
        #expect(IslandPolicy.bloomDuration(for: change, quiet: false) == nil)
        #expect(Describe.remoteState(change.session) == "Missed")
        #expect(Describe.status(change.session) == "Missed · Needs permission")
        #expect(Describe.shortStatus(change.session) == "Missed")

        // The same event on time does alert.
        let fresh = SessionStore()
        fresh.apply(remote(.promptSubmitted, seq: 1), from: devbox, at: now)
        let live = try #require(fresh.apply(remote(.needsInput, seq: 2, reason: "permission"), from: devbox, at: now))
        #expect(AlertPolicy.decide(live, settings: settings, hostIsFrontmost: false) != nil)
    }

    @Test func aMissedPromptStaysUntilSeenThenSettles() throws {
        var timeouts = SessionStore.Timeouts()
        timeouts.waiting = 100
        let store = SessionStore(timeouts: timeouts)
        store.apply(remote(.needsInput, seq: 1), from: devbox, at: now, missed: true)
        store.sweep(now: now.addingTimeInterval(5_000))
        #expect(store.sessions.first?.mood == .waiting)
        #expect(store.acknowledge(sessionID: "remote/devbox/claude:s1"))
        #expect(store.sessions.first?.mood == .idle)
    }

    @Test func aFreshEventClearsMissed() {
        let store = SessionStore()
        store.apply(remote(.needsInput, seq: 1), from: devbox, at: now, missed: true)
        store.apply(remote(.toolStarted, seq: 2), from: devbox, at: now)
        #expect(store.sessions.first?.origin?.missed == false)
    }

    @Test func anUnreachableMachinesSessionsAreUnknownNotWorking() throws {
        let store = SessionStore()
        store.apply(remote(.promptSubmitted, seq: 1), from: devbox, at: now)
        store.apply(remote(.needsInput, seq: 1, session: "s2"), from: devbox, at: now)
        store.apply(AgentEvent(agent: .codex, sessionId: "local", cwd: "/x", kind: .promptSubmitted, timestamp: now))
        #expect(store.setUnreachable(true, machine: "devbox").count == 2)
        #expect(store.setUnreachable(true, machine: "devbox").isEmpty)
        let s = try #require(store.session(id: "remote/devbox/claude:s1"))
        #expect(s.mood == .idle)
        #expect(Describe.status(s) == "Unknown · Thinking")
        #expect(Describe.shortStatus(s) == "Unknown")
        #expect(store.waitingCount == 0)
        #expect(store.session(id: "codex:local")?.mood == .working)

        store.setUnreachable(false, machine: "devbox")
        #expect(store.session(id: "remote/devbox/claude:s1")?.mood == .working)
    }

    @Test func aNewEventMeansTheMachineIsBack() {
        let store = SessionStore()
        store.apply(remote(.promptSubmitted, seq: 1), from: devbox, at: now)
        store.setUnreachable(true, machine: "devbox")
        store.apply(remote(.toolStarted, seq: 2), from: devbox, at: now)
        #expect(store.sessions.first?.origin?.unreachable == false)
    }

    @Test func unpairingForgetsOnlyThatMachine() {
        let store = SessionStore()
        store.apply(remote(.promptSubmitted, seq: 1), from: devbox, at: now)
        store.apply(remote(.promptSubmitted, seq: 1), from: MachineRef(id: "ci", label: "CI"), at: now)
        #expect(store.remove(machine: "devbox").map(\.removed) == [true])
        #expect(store.sessions.map(\.id) == ["remote/ci/claude:s1"])
    }

    @Test func alertsWaitForTheSaveAndOnlyWhenThereAreAlerts() {
        let store = SessionStore()
        func batch(_ events: RemoteEvent...) -> [RemoteDelivery] { events.map { RemoteDelivery(event: $0, at: now, missed: false) } }
        #expect(store.apply(batch(remote(.promptSubmitted, seq: 1), remote(.toolStarted, seq: 2)), from: devbox).saveFirst == false)
        #expect(store.apply(batch(remote(.needsInput, seq: 3)), from: devbox).saveFirst == true)
        // Already waiting: no new alert, so nothing to protect.
        #expect(store.apply(batch(remote(.needsInput, seq: 4)), from: devbox).saveFirst == false)
        let missed = [RemoteDelivery(event: remote(.turnCompleted, seq: 5), at: now, missed: true)]
        #expect(store.apply(missed, from: devbox).saveFirst == false)
    }

    @Test func remoteTextNeverLeavesTheMac() throws {
        let local = Session(agent: .claude, sessionId: "a", at: now)
        let session = Session(agent: .claude, sessionId: "a", at: now, origin: RemoteOrigin(machine: devbox))
        let loopback = try #require(URL(string: "http://127.0.0.1:5051/mcp"))
        let cloud = try #require(URL(string: "https://api.example.com/v1"))
        let lookalike = try #require(URL(string: "http://127.0.0.1.example.com/mcp"))

        #expect(!RemoteEgress.allows(session, to: .onlineVoice, remoteSummaries: true))
        #expect(!RemoteEgress.allows(session, to: .skillBootstrap, remoteSummaries: true))
        #expect(!RemoteEgress.allows(session, to: .url(cloud), remoteSummaries: true))
        #expect(!RemoteEgress.allows(session, to: .url(lookalike), remoteSummaries: true))
        #expect(!RemoteEgress.allows(session, to: .localLLM(cloud), remoteSummaries: true))
        #expect(!RemoteEgress.allows(session, to: .localLLM(loopback), remoteSummaries: false))
        #expect(RemoteEgress.allows(session, to: .localLLM(loopback), remoteSummaries: true))
        #expect(RemoteEgress.allows(session, to: .url(loopback), remoteSummaries: false))
        // Local sessions keep their own rules.
        #expect(RemoteEgress.allows(local, to: .onlineVoice, remoteSummaries: false))
    }

    @Test func theDayLogKeepsNoRemoteText() throws {
        var log = DayLog(now: now)
        let store = SessionStore()
        store.apply(remote(.promptSubmitted, seq: 1), from: devbox, at: now)
        var named = remote(.turnCompleted, seq: 2)
        named = RemoteEvent(seq: 2, id: named.id, ts: now, agent: .claude, session: "s1", kind: .turnCompleted, project: "secret-project",
                            title: "Secret title", message: "Secret message")
        let change = try #require(store.apply(named, from: devbox, at: now))
        log.apply(change, now: now)
        #expect(log.turnsDone == 1)
        #expect(log.projects.isEmpty)
        #expect(log.moments.map(\.place) == ["Claude on Devbox"])
        log.removeMoments(machine: "devbox")
        #expect(log.moments.isEmpty)
    }

    @Test func aMachineCanOnlyHoldSoManySessions() throws {
        func batch(_ events: RemoteEvent...) -> [RemoteDelivery] { events.map { RemoteDelivery(event: $0, at: now, missed: false) } }
        #expect(SessionStore().machineSessionLimit >= 900)
        let store = SessionStore()
        store.machineSessionLimit = 3
        let other = MachineRef(id: "other", label: "Other")
        store.apply(AgentEvent(agent: .claude, sessionId: "local", cwd: "/x", kind: .promptSubmitted, timestamp: now))
        for i in Int64(1)...3 { #expect(store.apply(remote(.promptSubmitted, seq: i, session: "s\(i)"), from: devbox, at: now) != nil) }

        #expect(store.apply(remote(.promptSubmitted, seq: 4, session: "s4"), from: devbox, at: now) == nil)
        #expect(store.apply(batch(remote(.needsInput, seq: 5, session: "s5"), remote(.needsInput, seq: 6, session: "s6")), from: devbox).refused == 2)
        // Its own sessions go on, and nobody else's are affected.
        #expect(store.apply(remote(.toolStarted, seq: 7, session: "s1"), from: devbox, at: now) != nil)
        #expect(store.apply(remote(.promptSubmitted, seq: 1, session: "x"), from: other, at: now) != nil)
        #expect(store.apply(AgentEvent(agent: .claude, sessionId: "local2", cwd: "/x", kind: .promptSubmitted, timestamp: now)) != nil)
        #expect(store.sessions.count == 6)
        // One ending makes room.
        store.apply(remote(.sessionEnded, seq: 8, session: "s1"), from: devbox, at: now)
        #expect(store.apply(remote(.promptSubmitted, seq: 9, session: "s9"), from: devbox, at: now) != nil)
    }

    @Test func aSessionLoopCantGrowTheBoard() throws {
        #expect(TaskStore().machineTaskLimit >= 3_000)
        let store = SessionStore()
        let tasks = TaskStore()
        tasks.machineTaskLimit = 20
        let local = try #require(store.apply(AgentEvent(agent: .claude, sessionId: "l", cwd: "/x/api", kind: .promptSubmitted, timestamp: now)))
        tasks.observe(local, now: now)
        var mine = try #require(tasks.tasks.first)
        mine.machine = devbox
        tasks.upsert(mine, at: now)

        // No session outlives its loop, so the session limit doesn't help here.
        for i in Int64(1)...200 {
            let at = now.addingTimeInterval(Double(i))
            for (offset, kind) in [(Int64(0), RemoteEvent.Kind.sessionStarted), (1, .sessionEnded)] {
                let e = RemoteEvent(seq: i * 2 + offset, id: String(format: "%032x", i * 2 + offset), ts: at, agent: .claude,
                                    session: "s\(i)", kind: kind, project: "project-\(i)")
                let change = try #require(store.apply(e, from: devbox, at: at))
                tasks.observe(change, now: at)
            }
        }
        let own = tasks.tasks.filter { $0.machine == devbox }
        #expect(own.count == 20)
        #expect(own.contains { $0.project == "project-200" })
        #expect(!own.contains { $0.project == "project-1" })
        // What the user wrote isn't anyone's to drop.
        #expect(own.contains { $0.id == mine.id })
    }

    @Test func aFullBoardOfTheUsersOwnTasksTakesNoMore() throws {
        let store = SessionStore()
        let tasks = TaskStore()
        tasks.machineTaskLimit = 1
        let first = try #require(store.apply(remote(.promptSubmitted, seq: 1, session: "s1"), from: devbox, at: now))
        var task = try #require(tasks.observe(first, now: now))
        task.machine = devbox
        tasks.upsert(task, at: now)
        let second = RemoteEvent(seq: 2, id: String(format: "%032x", 2), ts: now, agent: .claude, session: "s2", kind: .promptSubmitted, project: "other")
        let change = try #require(store.apply(second, from: devbox, at: now))
        #expect(tasks.observe(change, now: now) == nil)
        #expect(tasks.tasks.count == 1)
    }

    @Test func whatAModelSaysAboutARemoteSessionIsPlainTextToo() throws {
        let store = SessionStore()
        let tasks = TaskStore()
        let change = try #require(store.apply(remote(.promptSubmitted, seq: 1), from: devbox, at: now))
        let task = try #require(tasks.observe(change, now: now))
        let semantics = TaskSemantics(title: "Clean\u{1B}[2J up", summary: "Done\u{1B}]0;x\u{7} now")
        let plain = try #require(tasks.applySemantics(semantics, toTaskID: task.id))
        #expect(plain.title == "Clean[2J up")
        #expect(plain.summary == "Done]0;x now")
    }

    @Test func tasksNeverMixMachines() throws {
        let store = SessionStore()
        let tasks = TaskStore()
        let local = try #require(store.apply(AgentEvent(agent: .claude, sessionId: "l", cwd: "/x/api", kind: .promptSubmitted, timestamp: now)))
        let localTask = try #require(tasks.observe(local, now: now))
        let change = try #require(store.apply(remote(.promptSubmitted, seq: 1), from: devbox, at: now))
        let remoteTask = try #require(tasks.observe(change, now: now))
        #expect(remoteTask.id != localTask.id)
        #expect(remoteTask.machine == devbox)
        #expect(localTask.machine == nil)
        #expect(tasks.remove(machine: "devbox"))
        #expect(tasks.tasks.map(\.id) == [localTask.id])
        #expect(!tasks.remove(machine: "devbox"))
    }

    @Test func machinesAndCursorsSurviveTheirFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let machines = dir.appendingPathComponent("remote/machines.json")
        let good = Machine(id: "devbox", transport: ["ssh", "devbox"], fingerprint: pin, pairedAt: now)
        let bad = Machine(id: "Not Valid", transport: ["ssh", "x"], fingerprint: pin, pairedAt: now)
        try MachineFile.save([good, bad], to: machines)
        #expect(MachineFile.load(from: machines) == [good])
        let mode = try FileManager.default.attributesOfItem(atPath: machines.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        try MachineFile.save([good, good], to: machines)
        #expect(MachineFile.load(from: machines) == [good])

        let state = dir.appendingPathComponent("state.json")
        try StateFile.save([], cursors: ["devbox": RemoteCursor(seq: 9, epoch: "e")], to: state)
        #expect(StateFile.loadCursors(from: state) == ["devbox": RemoteCursor(seq: 9, epoch: "e")])
        // A state file from before remote agents still loads.
        try Data(#"{"version":1,"sessions":[]}"#.utf8).write(to: state)
        #expect(StateFile.load(from: state).isEmpty)
        #expect(StateFile.loadCursors(from: state).isEmpty)
    }
}
