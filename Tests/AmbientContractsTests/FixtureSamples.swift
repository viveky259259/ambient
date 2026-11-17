import Foundation
@testable import AmbientContracts

/// Known values for the fixture tests. Every optional field is set somewhere and left out somewhere else, and dates
/// are whole seconds, so each one encodes exactly.
///
/// Each test target keeps its own copy of this file (AmbientContractsTests, AmbientCoreTests): there is no shared
/// testing library.
enum Samples {
    static let t0 = Date(timeIntervalSinceReferenceDate: 784_900_000)
    static let t1 = t0.addingTimeInterval(90)
    static let t2 = t0.addingTimeInterval(300)

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let machine = MachineRef(id: "a1b2c3d4", label: "Studio")
    static let origin = RemoteOrigin(machine: machine, project: "ambient", lastSeq: 42, missed: true, unreachable: false)
    static let cursor = RemoteCursor(seq: 42, epoch: "e-1")

    static let host = HostInfo(bundleId: "com.apple.Terminal", termProgram: "Apple_Terminal", pids: [501, 77],
                               agentPid: 900, appServer: false, tty: "/dev/ttys004", hostSessionId: "host-1",
                               tmuxSocket: "/tmp/tmux-501/default", tmuxPane: "%3", cmuxWorkspace: "ws-1",
                               cmuxSurface: "sf-1", cmuxSocket: "/tmp/cmux.sock")

    static let activities: [Activity] = [
        .idle, .thinking, .tool(name: "Bash", detail: "swift test"), .tool(name: "Read", detail: nil), .compacting,
        .waiting(reason: "command", message: "rm -rf build"), .waiting(reason: "question", message: nil),
        .done(summary: "Added fixtures"), .done(summary: nil), .error(message: "Rate limited"), .error(message: nil),
    ]

    static let eventKinds: [EventKind] = [
        .sessionStarted, .promptSubmitted, .toolStarted(name: "Edit", detail: "Package.swift"),
        .toolStarted(name: "Edit", detail: nil), .toolFinished(name: "Edit", failed: false),
        .toolFinished(name: "Bash", failed: true), .needsInput(reason: "permission", message: "Allow Bash?"),
        .needsInput(reason: "question", message: nil), .answered, .compactStarted, .compactFinished,
        .subagentStarted, .subagentFinished, .turnCompleted(summary: "Done"), .turnCompleted(summary: nil),
        .turnFailed(message: "Overloaded"), .turnFailed(message: nil), .sessionEnded, .notice(message: "Hello"),
    ]

    static let event = AgentEvent(agent: .claude, sessionId: "s-1", cwd: "/Users/me/ambient",
                                  kind: .toolStarted(name: "Bash", detail: "swift test"), timestamp: t1, host: host)
    static let customEvent = AgentEvent(agent: .custom, sessionId: "aider-7", cwd: nil, kind: .promptSubmitted,
                                        timestamp: t0, host: nil, agentName: "Aider")

    static var localSession: Session {
        var s = Session(agent: .claude, sessionId: "s-1", at: t0)
        s.cwd = "/Users/me/ambient"
        s.host = host
        s.activity = .tool(name: "Bash", detail: "swift test")
        s.activitySince = t1
        s.lastEventAt = t2
        s.turnStartedAt = t0
        s.toolCount = 7
        s.subagents = 1
        s.title = "Write fixtures"
        s.beforeCompaction = .thinking
        return s
    }

    static var remoteSession: Session {
        var s = Session(agent: .codex, sessionId: "t-9", at: t0, origin: origin)
        s.activity = .waiting(reason: "command", message: "make test")
        s.turnStartedAt = t0
        s.turnEndedAt = t2
        s.acknowledged = true
        s.beforeWaiting = .tool(name: "Bash", detail: nil)
        return s
    }

    static var customSession: Session {
        var s = Session(agent: .custom, sessionId: "aider-7", at: t0)
        s.agentName = "Aider"
        s.activity = .done(summary: nil)
        return s
    }

    static var sessions: [Session] { [localSession, remoteSession, customSession] }

    static let task = AgentTask(id: "task-1", title: "Write fixtures", status: .inProgress, summary: "Golden files",
                                summarySource: .localLLM, summarizedAt: t1, project: "ambient",
                                cwd: "/Users/me/ambient", agents: [.claude, .codex], sessionIds: ["claude:s-1"],
                                manual: false, createdAt: t0, updatedAt: t2, lastSessionId: "claude:s-1",
                                machine: machine)
    static let manualTask = AgentTask(id: "task-2", title: "Plan phase 2", createdAt: t0, updatedAt: t0)

    static var tasks: [AgentTask] { [task, manualTask] }

    /// A day with a finished turn, a failed one and a prompt that needed the user.
    static var day: DayLog {
        var day = DayLog(now: t0, calendar: utc)
        var done = Session(agent: .claude, sessionId: "s-1", at: t0)
        done.title = "Write fixtures"
        done.turnStartedAt = t0
        done.turnEndedAt = t1
        done.activity = .done(summary: "ok")
        day.apply(SessionChange(session: done, previous: .thinking, event: .turnCompleted(summary: "ok"), removed: false),
                  now: t1, calendar: utc)
        var failed = Session(agent: .gemini, sessionId: "g-2", at: t0)
        failed.turnStartedAt = t0
        failed.turnEndedAt = t2
        failed.activity = .error(message: nil)
        day.apply(SessionChange(session: failed, previous: .thinking, event: .turnFailed(message: nil), removed: false),
                  now: t2, calendar: utc)
        var asking = remoteSession
        asking.acknowledged = false
        day.apply(SessionChange(session: asking, previous: .thinking, event: .needsInput(reason: "command", message: nil),
                                removed: false),
                  now: t2, calendar: utc)
        return day
    }
}
