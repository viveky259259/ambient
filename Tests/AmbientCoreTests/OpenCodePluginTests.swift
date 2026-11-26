import Foundation
import Testing
@testable import AmbientCore

/// Node, when it's on this Mac. OpenCode runs plugins with Bun, but the plugin uses only what both provide.
private let node: String? = (ProcessInfo.processInfo.environment["PATH"] ?? "")
    .split(separator: ":").map { "\($0)/node" }
    .first { FileManager.default.isExecutableFile(atPath: $0) }

/// The plugin `ambient install opencode` writes, run against a fake OpenCode, and what it hands `ambient hook
/// opencode` read back by `OpenCodeAdapter`: the two halves have to agree. The 2 events are shaped as OpenCode 2.2.6
/// sent them in a live run.
@Suite(.enabled(if: node != nil, "needs Node")) struct OpenCodePluginTests {
    /// OpenCode 1.4 to 1.19: a prompt, a file write, a subagent's edit and its answer, a question, an error and the
    /// idle OpenCode sends after it, then a shell command typed in the TUI, which starts a run with no message.
    private static let one = #"""
    const { server } = (await import(process.argv[2])).default
    const hooks = await server({ directory: "/src/app" })
    const ev = (type, properties) => hooks.event({ event: { id: "e", type, properties } })
    await hooks["chat.message"]({ sessionID: "A" }, {})
    await ev("session.status", { sessionID: "A", status: { type: "busy" } })
    await ev("session.created", { sessionID: "C", info: { id: "C", parentID: "A", directory: "/src/app" } })
    await hooks["tool.execute.before"]({ tool: "write", sessionID: "A", callID: "1" },
      { args: { filePath: "/src/app/README.md", content: "SECRET ".repeat(10000) } })
    await ev("permission.asked", { id: "p", sessionID: "C", permission: "edit", patterns: ["src/a.ts", "src/b.ts"],
      metadata: { filepath: "src/a.ts, src/b.ts", diff: "DIFF ".repeat(10000) }, always: ["*"] })
    await ev("permission.replied", { sessionID: "C", requestID: "p", reply: "once" })
    await hooks["tool.execute.before"]({ tool: "bash", sessionID: "C", callID: "2" }, { args: { command: "ls" } })
    await ev("question.asked", { id: "q", sessionID: "A", questions: [{ question: "Which database?", header: "DB", options: [] }] })
    await ev("session.error", { sessionID: "A", error: { name: "ProviderAuthError", data: { message: "Invalid API key" } } })
    await ev("session.idle", { sessionID: "A" })
    await ev("session.status", { sessionID: "A", status: { type: "busy" } })
    await ev("session.idle", { sessionID: "A" })
    await new Promise((resolve) => setTimeout(resolve, 1500))
    """#

    /// OpenCode 2: the same run through `setup`, whose events arrive for every project, the ends of a run with no
    /// location, and the first of them before its session has said where it is.
    private static let two = #"""
    const { setup } = (await import(process.argv[2])).default
    const queue = []
    let wake
    let created = Date.now()
    const push = (type, data, directory = "/src/app") => {
      queue.push({ id: "e", created: created++, type, ...(directory ? { location: { directory } } : {}), data })
      wake?.()
    }
    const events = {
      next: async () => {
        while (!queue.length) await new Promise((resolve) => (wake = resolve))
        return { done: false, value: queue.shift() }
      },
      return: async () => ({ done: true }),
    }
    const stop = await setup({ location: { directory: "/src/app" }, event: { subscribe: () => ({ [Symbol.asyncIterator]: () => events }) } })
    push("session.created", { sessionID: "X", location: { directory: "/src/other" } }, "/src/other")
    push("session.execution.started", { sessionID: "X" }, null)
    push("session.execution.started", { sessionID: "A" }, null)
    push("session.inbox.enqueued", { sessionID: "A", item: { type: "user", payload: { text: "SECRET prompt" } } })
    push("session.created", { sessionID: "C", parentID: "A", location: { directory: "/src/app" } })
    push("session.tool.input.started", { sessionID: "A", id: "t1", name: "write" })
    push("session.tool.called", { sessionID: "A", id: "t1", input: { path: "README.md", content: "SECRET ".repeat(10000) } })
    push("permission.asked", { id: "p", sessionID: "C", action: "edit", resources: ["src/a.ts", "src/b.ts"],
      metadata: { files: [{ file: "src/a.ts", patch: "DIFF ".repeat(10000) }] } })
    push("permission.replied", { sessionID: "C", requestID: "p", reply: "once" })
    push("session.tool.called", { sessionID: "C", id: "t9", input: { command: "ls" } })
    push("form.created", { form: { id: "f", sessionID: "A", title: "Questions", metadata: { kind: "question" },
      fields: [{ key: "q0", title: "DB", description: "Which database?", type: "string" }] } })
    push("form.replied", { id: "f", sessionID: "A", answer: { q0: "pg" } })
    push("session.tool.success", { sessionID: "A", id: "t1" })
    push("permission.asked", { id: "p2", sessionID: "A", action: "shell", resources: ["rm -rf build"], save: ["rm *"] })
    push("session.execution.failed", { sessionID: "A", error: { type: "provider.no-route", message: "Model unavailable" } }, null)
    push("session.execution.started", { sessionID: "A" }, null)
    // A new message superseded the run: the next one starts at once.
    push("session.execution.interrupted", { sessionID: "A", reason: "superseded" }, null)
    push("session.execution.started", { sessionID: "A" }, null)
    push("session.execution.succeeded", { sessionID: "A" }, null)
    push("session.tool.called", { sessionID: "X", id: "x", input: { command: "make" } }, "/src/other")
    await new Promise((resolve) => setTimeout(resolve, 1500))
    await stop()
    """#

    @Test func opencodeOne() throws {
        let (kinds, payloads) = try run(Self.one)
        #expect(payloads.allSatisfy { $0.raw["service"] == nil })
        #expect(kinds == [
            .promptSubmitted,
            .toolStarted(name: "write", detail: "README.md"),
            // The subagent's edit is its parent's to answer.
            .needsInput(reason: "edit", message: "a.ts +1 more"),
            .answered,
            .needsInput(reason: "question", message: "Which database?"),
            // The idle after the error isn't a finished turn.
            .turnFailed(message: "Invalid API key"),
            .promptSubmitted,
            .turnCompleted(summary: nil),
        ])
    }

    @Test func opencodeTwo() throws {
        let (kinds, payloads) = try run(Self.two)
        // From OpenCode's background service, which says nothing of where the session is.
        #expect(payloads.allSatisfy { $0.raw["service"] as? Bool == true })
        #expect(kinds == [
            .promptSubmitted,
            .toolStarted(name: "write", detail: "README.md"),
            .needsInput(reason: "edit", message: "a.ts +1 more"),
            .answered,
            .needsInput(reason: "question", message: "Which database?"),
            .answered,
            .toolFinished(name: "write", failed: false),
            .needsInput(reason: "command", message: "rm -rf build"),
            .turnFailed(message: "Model unavailable"),
            .promptSubmitted,
            .promptSubmitted,
            .turnCompleted(summary: nil),
        ])
    }

    /// Runs a driver against the plugin, with a stand-in for `ambient hook opencode`, and returns what each call says,
    /// in OpenCode's order. Every call is for session A in /src/app, in its own order, and says nothing it shouldn't.
    private func run(_ driver: String) throws -> (kinds: [EventKind?], payloads: [HookPayload]) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ambient-opencode-\(UUID().uuidString)")
        let events = dir.appendingPathComponent("events")
        try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cli = dir.appendingPathComponent("ambient")
        try "#!/bin/sh\ncat > \"\(events.path)/$$.json\"\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let plugin = dir.appendingPathComponent("ambient.mjs")
        try OpenCodePlugin.source(cli: .absolute(cli.path)).write(to: plugin, atomically: true, encoding: .utf8)
        let script = dir.appendingPathComponent("driver.mjs")
        try driver.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(node))
        process.arguments = [script.path, plugin.absoluteString]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let files = try FileManager.default.contentsOfDirectory(at: events, includingPropertiesForKeys: nil)
        let sent = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(!sent.contains { $0.contains("SECRET") || $0.contains("DIFF") })
        #expect(sent.allSatisfy { $0.utf8.count < 1_000 })

        let payloads = try files.compactMap { try HookPayload(json: Data(contentsOf: $0)) }
            .sorted { ($0.number("ts") ?? 0) < ($1.number("ts") ?? 0) }
        #expect(Set(payloads.compactMap { $0.number("ts") }).count == payloads.count)
        #expect(payloads.allSatisfy { $0.string("session_id") == "A" && $0.string("cwd") == "/src/app" })
        return (payloads.map { AdapterRegistry.event(agent: .opencode, payload: $0, eventHint: nil)?.kind }, payloads)
    }
}
