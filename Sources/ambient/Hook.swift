import AmbientCore
import Foundation

/// `ambient hook <agent> [event]`: reads the agent's hook payload from stdin and forwards a
/// normalized event to the app. Always exits 0 and never blocks the agent for long.
enum Hook {
    static func run(arguments: [String], paths: AmbientPaths) {
        guard let name = arguments.first, let agent = AgentKind(rawValue: name) else { return }
        // Gemini parses stdout as JSON; answer with an empty object, whatever happens.
        let reply: @Sendable () -> Void = { if agent == .gemini { FileHandle.standardOutput.write(Data("{}\n".utf8)) } }
        defer { reply() }
        // Never outlive the agent's patience, even if stdin is never closed.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            reply()
            exit(0)
        }

        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = HookPayload(json: input),
              let event = AdapterRegistry.event(agent: agent, payload: payload, eventHint: arguments.dropFirst().first,
                                                host: HostCapture.current())
        else {
            debugLog(paths, "ignored \(agent.rawValue) payload (\(input.count) bytes)")
            return
        }
        do {
            try UnixSocket.send(Wire.encode(.event(event)), to: paths.socket.path, timeout: 0.25)
            debugLog(paths, "sent \(agent.rawValue) \(event.kind)")
        } catch {
            debugLog(paths, "app not reachable: \(error)")
        }
    }

    /// Set `AMBIENT_DEBUG=1` to trace hooks in ~/.ambient/logs/hook.log.
    private static func debugLog(_ paths: AmbientPaths, _ message: String) {
        guard ProcessInfo.processInfo.environment["AMBIENT_DEBUG"] == "1" else { return }
        try? FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        let url = paths.logs.appendingPathComponent("hook.log")
        let line = Data("\(ISO8601DateFormatter().string(from: Date())) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
