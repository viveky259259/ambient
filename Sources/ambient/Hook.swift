import AmbientCore
import Foundation

/// `ambient hook <agent> [event] [--answer]`: reads the agent's hook payload from stdin and forwards a
/// normalized event to the app. Always exits 0 and never blocks the agent for long, except the permission
/// hook installed with answering from the island on, which waits for the user's answer.
enum Hook {
    static func run(arguments: [String], paths: AmbientPaths) {
        guard let args = HookArguments(arguments) else { return }
        let agent = args.agent
        // Gemini and Antigravity parse stdout as JSON; always answer, whatever happens.
        let answer = AdapterRegistry.reply(agent: agent, event: args.eventHint)
        let reply: @Sendable () -> Void = { if let answer { FileHandle.standardOutput.write(Data(answer.utf8)) } }
        defer { reply() }
        let permissions = args.answer ? PermissionSettings.load(paths) : PermissionSettings()
        // Never outlive the agent's patience, even if stdin is never closed.
        DispatchQueue.global().asyncAfter(deadline: .now() + (permissions.enabled ? TimeInterval(permissions.wait + 5) : 3)) {
            reply()
            exit(0)
        }

        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let payload = HookPayload(json: input),
              let event = AdapterRegistry.event(agent: agent, payload: payload, eventHint: args.eventHint,
                                                host: HostCapture.current())
        else {
            debugLog(paths, "ignored \(agent.rawValue) payload (\(input.count) bytes)")
            return
        }
        if permissions.enabled, PermissionReply.agents.contains(agent), let ask = PermissionAsk.make(event: event, payload: payload) {
            askIsland(ask, wait: permissions.wait, paths: paths)
            return
        }
        do {
            try UnixSocket.send(Wire.encode(.event(event)), to: paths.socket.path, timeout: 0.25)
            debugLog(paths, "sent \(agent.rawValue) \(event.kind)")
        } catch {
            debugLog(paths, "app not reachable: \(error)")
        }
    }

    /// Hands a permission prompt to the island and prints the user's answer for the agent. No answer, an
    /// unreachable app or anything unexpected prints nothing, and the agent asks in its own way.
    private static func askIsland(_ ask: PermissionAsk, wait: Int, paths: AmbientPaths) {
        do {
            let data = try UnixSocket.send(Wire.encode(.permissionRequest(ask)), to: paths.socket.path,
                                           timeout: TimeInterval(wait + 3), expectReply: true)
            guard let data, case let .permissionAnswer(answer) = try Wire.decode(data) else { return }
            debugLog(paths, "island answered \(answer.rawValue) for \(ask.event.agent.rawValue) \(ask.toolName)")
            if let out = PermissionReply.stdout(answer) { FileHandle.standardOutput.write(Data(out.utf8)) }
        } catch {
            debugLog(paths, "no answer from the island: \(error)")
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
