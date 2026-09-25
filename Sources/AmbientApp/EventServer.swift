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
                DispatchQueue.main.async { model.value.apply(event) }
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
            case .ping:
                return try? Wire.encode(.pong(version: AmbientVersion.current))
            case .status, .pong, .opened:
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
