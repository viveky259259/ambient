import AmbientCore
import Foundation
import os

/// Receives hook events and CLI requests on the Unix socket.
final class EventServer {
    private let server: UnixSocketServer
    private let model: AppModel
    private let permissions: PermissionDesk
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "server")

    init(paths: AmbientPaths, model: AppModel, permissions: PermissionDesk) {
        // Room for a shared-memory write: 32 KB of text, however much escaping JSON adds.
        self.server = UnixSocketServer(path: paths.socket.path, maxMessageSize: 256 * 1024)
        self.model = model
        self.permissions = permissions
    }

    func start() throws {
        let snapshot = model.snapshot
        let memory = model.memory
        let model = MainThreadBox(model)
        let permissions = MainThreadBox(permissions)
        let log = self.log
        try server.start { data in
            let message: WireMessage
            do { message = try Wire.decode(data) } catch {
                log.error("Dropped an undecodable message (\(data.count) bytes)")
                return nil
            }
            switch message {
            case let .event(event):
                DispatchQueue.main.async {
                    PerfMonitor.shared.hookEvent(sent: event.timestamp)
                    model.value.apply(event)
                }
                return nil
            case .statusRequest:
                let (sessions, mood) = snapshot.get()
                return try? Wire.encode(.status(sessions: sessions, mood: mood))
            case .acknowledgeAll:
                DispatchQueue.main.async { model.value.acknowledgeAll() }
                return try? Wire.encode(.pong(version: AmbientVersion.current))
            case let .open(query, from):
                let (sessions, _) = snapshot.get()
                if let match = SessionMatcher.find(query, in: sessions) {
                    DispatchQueue.main.async { model.value.open(match, from: from) }
                    return try? Wire.encode(.opened(sessionID: match.id))
                }
                // Not running any more: its chat usually still is, in its app. Another Mac's board asks for these.
                guard let query else { return try? Wire.encode(.opened(sessionID: nil)) }
                let box = ReplyBox<String?>()
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    box.value = model.value.openEndedChat(sessionID: query, from: from)?.id
                    done.signal()
                }
                _ = done.wait(timeout: .now() + 2)
                return try? Wire.encode(.opened(sessionID: box.value ?? nil))
            case .listTasks:
                return try? Wire.encode(.tasks(snapshot.getTasks()))
            case let .upsertTask(draft):
                let box = ReplyBox<AgentTask>()
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    box.value = model.value.upsertTask(draft)
                    done.signal()
                }
                _ = done.wait(timeout: .now() + 2)
                return try? Wire.encode(.upsertTaskResult(box.value ?? draft))
            case let .openTask(id):
                let box = ReplyBox<String?>()
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    box.value = model.value.openTask(id)
                    done.signal()
                }
                _ = done.wait(timeout: .now() + 2)
                return try? Wire.encode(.opened(sessionID: box.value ?? nil))
            case .taskModelRequest, .setTaskModel:
                let box = ReplyBox<TaskLLMConfig>()
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    if case let .setTaskModel(change) = message {
                        box.value = model.value.setTaskModel(change)
                    } else {
                        box.value = model.value.prefs.taskLLMConfig
                    }
                    done.signal()
                }
                // The CLI waits longer than all of this, so it hears either the settings or that they may still change.
                guard done.wait(timeout: .now() + 2) == .success, let config = box.value else {
                    return try? Wire.encode(.taskModelTimedOut)
                }
                // Resolved here: the app's PATH and Pythons decide how the board runs the model, not the CLI's.
                let made = ReplyBox<TaskModelReport>()
                let resolved = DispatchSemaphore(value: 0)
                Task.detached {
                    made.value = await TaskModelReport.make(config)
                    resolved.signal()
                }
                guard resolved.wait(timeout: .now() + 20) == .success, let report = made.value else {
                    return try? Wire.encode(.taskModel(config))
                }
                return try? Wire.encode(.taskModelReport(report))
            case let .memory(request):
                // Right here, not on the main thread, which can be busy drawing for longer than an agent waits.
                return try? Wire.encode(.memoryReply(memory.answer(request, sessions: snapshot.get().0)))
            case .ping:
                return try? Wire.encode(.pong(version: AmbientVersion.current))
            case let .permissionRequest(ask):
                DispatchQueue.main.async { model.value.apply(ask.event) }
                // Holds this connection's thread until the user answers or the prompt goes back to the agent.
                return try? Wire.encode(.permissionAnswer(permissions.value.answer(for: ask)))
            case .status, .pong, .opened, .tasks, .upsertTaskResult, .taskModelReport, .taskModel, .taskModelTimedOut, .memoryReply,
                 .permissionAnswer:
                return nil
            }
        }
    }

    func stop() {
        server.stop()
    }
}

/// Carries a main-thread object through a background closure that only hops back to main to use it.
private struct MainThreadBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Holds a value written from the main thread for a socket reply.
private final class ReplyBox<T>: @unchecked Sendable {
    var value: T?
}
