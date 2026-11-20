@testable import AmbientApp
@testable import AmbientCore
import Combine
import Foundation
import Testing

/// The app's source of truth, driven without `start()`: no timers, files or workspace observers.
@MainActor @Suite struct AppModelTests {
    let box: AppSandbox
    let model: AppModel

    init() throws {
        box = try AppSandbox()
        model = AppModel(prefs: box.preferences(), stateURL: nil)
    }

    @Test func startsEmptyAndIdle() {
        #expect(model.sessions.isEmpty)
        #expect(model.mood == .idle)
        #expect(model.tasks.isEmpty)
        #expect(model.remoteLinks.isEmpty)
        #expect(model.taskLLMStatus == .disabled)
    }

    @Test func applyingEventsPublishesSessionsAndMood() {
        model.apply(event(.promptSubmitted))
        #expect(model.sessions.map(\.sessionId) == ["s1"])
        #expect(model.mood == .working)
        model.apply(event(.needsInput(reason: "permission", message: "rm -rf build"), at: 1))
        #expect(model.mood == .waiting)
        model.apply(event(.turnCompleted(summary: "Done"), at: 2))
        #expect(model.mood == .done)
    }

    @Test func everyAppliedEventIsSentAsATransition() {
        var seen: [SessionChange] = []
        let c = model.transitions.sink { seen.append($0) }
        model.apply(event(.promptSubmitted))
        model.apply(event(.toolStarted(name: "Bash", detail: "npm test"), at: 1))
        c.cancel()
        #expect(seen.count == 2)
        #expect(seen.last?.session.activity == .tool(name: "Bash", detail: "npm test"))
    }

    @Test func endedSessionsLeave() {
        model.apply(event(.promptSubmitted))
        model.apply(event(.sessionEnded, at: 1))
        #expect(model.sessions.isEmpty)
        #expect(model.mood == .idle)
    }

    @Test func acknowledgingADoneSessionCalmsIt() throws {
        model.apply(event(.promptSubmitted))
        model.apply(event(.turnCompleted(summary: nil), at: 1))
        let id = try #require(model.sessions.first?.id)
        #expect(model.mood == .done)
        model.acknowledge(id)
        #expect(model.mood == .idle)
        #expect(model.sessions.first?.acknowledged == true)
    }

    @Test func acknowledgeAllCalmsEverySession() {
        model.apply(event(.promptSubmitted, session: "a"))
        model.apply(event(.turnFailed(message: "quota"), session: "a", at: 1))
        model.apply(event(.promptSubmitted, session: "b", agent: .codex))
        model.apply(event(.needsInput(reason: "permission", message: nil), session: "b", agent: .codex, at: 1))
        #expect(model.mood == .waiting)
        model.acknowledgeAll()
        #expect(model.sessions.allSatisfy { $0.acknowledged })
        #expect(model.mood < .waiting)
    }

    @Test func acknowledgingAnUnknownSessionDoesNothing() {
        model.apply(event(.promptSubmitted))
        var count = 0
        let c = model.transitions.sink { _ in count += 1 }
        model.acknowledge("nope")
        c.cancel()
        #expect(count == 0)
    }

    @Test func upsertTaskSavesAndPublishesIt() {
        let saved = model.upsertTask(AgentTask(id: "t1", title: "Ship QA plan", status: .inProgress, project: "ambient",
                                               manual: true))
        #expect(saved.id == "t1" && saved.title == "Ship QA plan")
        #expect(model.tasks.contains { $0.id == "t1" && $0.status == .inProgress })
        _ = model.upsertTask(AgentTask(id: "t1", title: "Ship QA plan", status: .done, manual: true))
        #expect(model.tasks.filter { $0.id == "t1" }.map(\.status) == [.done])
    }

    @Test func sessionsShowUpOnTheBoard() {
        model.apply(event(.promptSubmitted))
        #expect(!model.tasks.isEmpty)
    }

    @Test func openingAnUnknownTaskFindsNothing() {
        #expect(model.openTask("missing") == nil)
    }

    @Test func remoteCursorStartsAtZero() {
        #expect(model.remoteCursor("devbox") == RemoteCursor())
    }

    @Test func keepMachinesFollowsTheAllowlist() {
        model.keepMachines([makeMachine("devbox"), makeMachine("studio", label: "Studio")])
        #expect(model.remoteLinks.map(\.machine.id) == ["devbox", "studio"])
        #expect(model.remoteLinks.allSatisfy { $0.health == .connecting })
        model.keepMachines([makeMachine("studio", label: "Studio Mac")])
        #expect(model.remoteLinks.map(\.machine.id) == ["studio"])
        #expect(model.remoteLinks.first?.machine.label == "Studio Mac")
    }

    @Test func remoteHealthIsRecordedForPairedMachinesOnly() {
        let devbox = makeMachine("devbox")
        model.setRemoteHealth(.connected, machine: devbox, hello: nil, updateAvailable: false)
        #expect(model.remoteLinks.isEmpty)
        model.keepMachines([devbox])
        model.setRemoteHealth(.connected, machine: devbox, hello: nil, updateAvailable: false)
        #expect(model.remoteLinks.first?.health == .connected)
        model.setRemoteHealth(.revoked("unpaired on devbox"), machine: devbox, hello: nil, updateAvailable: false)
        #expect(model.remoteLinks.first?.health == .revoked("unpaired on devbox"))
    }

    @Test func purgingAMachineLeavesLocalSessionsAlone() {
        model.apply(event(.promptSubmitted))
        model.keepMachines([makeMachine("devbox")])
        model.purge(machine: "devbox")
        #expect(model.sessions.count == 1)
        #expect(model.remoteCursor("devbox") == RemoteCursor())
    }

    @Test func remoteBatchesFromUnpairedMachinesAreDropped() {
        let refused = model.applyRemote([], cursor: RemoteCursor(), from: MachineRef(id: "ghost", label: "Ghost"))
        #expect(refused == 0)
        #expect(model.sessions.isEmpty)
    }

    @Test func setQuietSetsAndClearsTheQuietTime() {
        model.setQuiet(for: 600)
        #expect(model.prefs.isQuiet)
        let until = model.prefs.quietUntil ?? .distantPast
        #expect(until.timeIntervalSinceNow > 590 && until.timeIntervalSinceNow <= 600)
        model.setQuiet(for: nil)
        #expect(model.prefs.quietUntil == nil && !model.prefs.isQuiet)
    }

    @Test func memoryWriteReadListForgetRoundTrip() throws {
        let project = "/src/ambient"
        let write = MemoryWrite(key: "notes/plan", scope: .project(project), value: "ship it")
        guard case let .entry(written) = model.memory.answer(.write(write, callerPids: []), sessions: model.sessions) else {
            Issue.record("write failed"); return
        }
        #expect(written.key == "notes/plan")
        guard case let .entry(read) = model.memory.answer(.read(key: "notes/plan", project: project, scope: nil), sessions: model.sessions) else {
            Issue.record("read failed"); return
        }
        #expect(read.value == "ship it")
        guard case let .entries(list) = model.memory.answer(.list(project: project, scope: nil), sessions: model.sessions) else {
            Issue.record("list failed"); return
        }
        #expect(list.map(\.key) == ["notes/plan"])
        guard case .forgotten = model.memory.answer(.forget(key: "notes/plan", project: project, scope: nil), sessions: model.sessions) else {
            Issue.record("forget failed"); return
        }
        guard case .failed = model.memory.answer(.read(key: "notes/plan", project: project, scope: nil), sessions: model.sessions) else {
            Issue.record("forgotten key still readable"); return
        }
    }

    @Test func memoryRefusesSecrets() {
        let write = MemoryWrite(key: "aws", scope: .global, value: "AKIAABCDEFGHIJKLMNOP")
        guard case .failed = model.memory.answer(.write(write, callerPids: []), sessions: model.sessions) else {
            Issue.record("a secret was shared"); return
        }
    }
}
