import AmbientCore
import Foundation
import os

/// Receives hook events and CLI requests on the Unix socket.
final class EventServer {
    private let server: UnixSocketServer
    private let model: AppModel
    private let log = Logger(subsystem: "com.viveky259259.Ambient", category: "server")

    init(paths: AmbientPaths, model: AppModel) {
        self.server = UnixSocketServer(path: paths.socket.path)
        self.model = model
    }

    func start() throws {
        let snapshot = model.snapshot
        let model = MainThreadBox(model)
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
            case let .open(query):
                let (sessions, _) = snapshot.get()
                let match = SessionMatcher.find(query, in: sessions)
                if let match { DispatchQueue.main.async { model.value.open(match) } }
                return try? Wire.encode(.opened(sessionID: match?.id))
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
                    box.value = model.value.openTask(id)?.id
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
                _ = done.wait(timeout: .now() + 2)
                return box.value.flatMap { try? Wire.encode(.taskModel($0)) }
            case .ping:
                return try? Wire.encode(.pong(version: AmbientVersion.current))
            case .status, .pong, .opened, .tasks, .upsertTaskResult, .taskModel:
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
