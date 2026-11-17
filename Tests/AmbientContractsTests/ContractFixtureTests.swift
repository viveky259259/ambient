import Foundation
import Testing
@testable import AmbientContracts

/// The shared values other modules pass around, and save inside Ambient's files and socket messages.
@Suite struct ContractFixtureTests {
    @Test func agentKind() throws { try Fixture.roundTrip("AgentKind.v1.json", AgentKind.allCases) }
    @Test func mood() throws { try Fixture.roundTrip("Mood.v1.json", Mood.allCases) }
    @Test func activity() throws { try Fixture.roundTrip("Activity.v1.json", Samples.activities) }
    @Test func eventKind() throws { try Fixture.roundTrip("EventKind.v1.json", Samples.eventKinds) }
    @Test func hostInfo() throws { try Fixture.roundTrip("HostInfo.v1.json", [Samples.host, HostInfo()]) }
    @Test func agentEvent() throws { try Fixture.roundTrip("AgentEvent.v1.json", [Samples.event, Samples.customEvent]) }
    @Test func session() throws { try Fixture.roundTrip("Session.v1.json", Samples.sessions) }
    @Test func taskStatus() throws { try Fixture.roundTrip("TaskStatus.v1.json", TaskStatus.allCases) }

    @Test func taskSummarySource() throws {
        try Fixture.roundTrip("TaskSummarySource.v1.json", [TaskSummarySource.heuristic, .localLLM, .manual])
    }

    @Test func agentTask() throws { try Fixture.roundTrip("AgentTask.v1.json", Samples.tasks) }
    @Test func machineRef() throws { try Fixture.roundTrip("MachineRef.v1.json", Samples.machine) }

    @Test func remoteOrigin() throws {
        try Fixture.roundTrip("RemoteOrigin.v1.json", [Samples.origin, RemoteOrigin(machine: Samples.machine)])
    }

    @Test func remoteCursor() throws {
        try Fixture.roundTrip("RemoteCursor.v1.json", [Samples.cursor, RemoteCursor()])
    }

    @Test func dayMark() throws {
        try Fixture.roundTrip("DayMark.v1.json", [DayMark(agent: .claude, outcome: .done, at: Samples.t1),
                                                  DayMark(agent: .cursor, outcome: .failed, at: Samples.t2)])
    }

    @Test func dayMoment() throws {
        try Fixture.roundTrip("DayMoment.v1.json", [
            DayMoment(kind: .neededYou, agent: .codex, place: "Codex on Studio", at: Samples.t1, machine: "a1b2c3d4"),
            DayMoment(kind: .done, agent: .claude, place: "Write fixtures", at: Samples.t2),
            DayMoment(kind: .failed, agent: .gemini, place: "ambient", at: Samples.t2),
        ])
    }

    @Test func dayLog() throws {
        let day = Samples.day
        #expect(!day.marks.isEmpty && !day.moments.isEmpty, "the sample day should cover marks and moments")
        try Fixture.roundTrip("DayLog.v1.json", day)
    }

    /// `Need` isn't `Codable`, but its raw values are on the wire: remote lines carry `permission` and `question`, and
    /// `EventKind.needsInput`'s `reason` names one.
    @Test func needRawValues() throws {
        let fixture = try Fixture.check("Need.v1.json", matches: JSONEncoder().encode(Need.allCases.map(\.rawValue)))
        let names = try JSONDecoder().decode([String].self, from: fixture)
        #expect(names.compactMap(Need.init(rawValue:)) == Need.allCases)
    }
}
