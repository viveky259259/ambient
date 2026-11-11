import Foundation

/// The plugin `ambient install opencode` writes to ~/.config/opencode/plugins/ambient.js. OpenCode has no
/// command hooks, so the plugin turns its events into payloads for `ambient hook opencode` (`OpenCodeAdapter`),
/// starting the command without waiting for it.
///
/// One file serves both of OpenCode's plugin APIs, through a single default export: `{ id, server, setup }`.
/// - OpenCode 1.4 to 1.19 call `server` with the project and send events to its `event` hook: `session.status` and
///   `session.idle` for runs, `session.error` (which OpenCode follows with `session.idle`), `permission.asked` and
///   `question.asked` for prompts, and their `.replied`. `permission.updated` is what 1.0 called a permission request.
/// - OpenCode 2 calls `setup` with a context whose `event.subscribe()` streams every project's events, so each
///   project's copy passes on only its own sessions: `session.execution.started` to `.succeeded`, `.failed` or
///   `.interrupted` for runs, `session.tool.*` for tools, `permission.asked` and `form.created` for prompts. In 2,
///   plugins run in OpenCode's background service rather than the terminal, which is the process Ambient sees.
/// 1.0 to 1.3 call every export as a function and can't load it.
enum OpenCodePlugin {
    enum CLI: Equatable {
        /// A path under the user's home, resolved by the plugin, so a synced config works on every Mac.
        case home(String)
        case absolute(String)
    }

    static func source(cli: CLI) -> String {
        let path = switch cli {
        case let .home(relative): "join(homedir(), \(literal(relative)))"
        case let .absolute(path): literal(path)
        }
        return #"""
        // Ambient (https://yaml.cafe) shows what OpenCode is doing at the notch, in notifications and on the Dock.
        // `ambient install opencode` wrote this file and `ambient uninstall opencode` removes it. Edits are overwritten.
        // Each event hands a few fields to the local `ambient` command, which never holds OpenCode up.
        import { spawn } from "node:child_process"
        import { existsSync } from "node:fs"
        import { homedir } from "node:os"
        import { join } from "node:path"

        const cli = \#(path)

        // What Ambient shows of a tool call: the command, the file, the URL. Never a file's contents or a prompt.
        const KEEP = ["command", "description", "filePath", "filepath", "path", "pattern", "query", "url", "subagent_type", "parentDir", "tool"]

        const brief = (value, nested = false) => {
          const out = {}
          if (!value || typeof value !== "object") return out
          for (const key of KEEP) if (typeof value[key] === "string") out[key] = value[key].slice(0, 400)
          // A patch's file lines, without the changes.
          if (typeof value.patchText === "string")
            out.patchText = value.patchText.split("\n").filter((line) => line.startsWith("*** ")).join("\n").slice(0, 4000)
          if (Array.isArray(value.directories)) out.directories = value.directories.filter((d) => typeof d === "string").slice(0, 3)
          if (!nested && value.input && typeof value.input === "object") out.input = brief(value.input, true)
          return out
        }

        // What both versions share: where events go, and which sessions are subagents. `extra` goes with every event.
        const relay = (directory, extra = {}) => {
          // Subagent sessions are part of their parent's turn. Their prompts are the parent's to answer.
          const parents = new Map()
          // Each event goes to its own process, so they can arrive out of order. Their times only go up.
          let last = 0
          const top = (session) => {
            for (let i = 0; i < 8 && parents.has(session); i++) session = parents.get(session)
            return session
          }
          const send = (session, event, fields = {}, at) => {
            if (!session || parents.has(session) || !existsSync(cli)) return false
            last = Math.max(typeof at === "number" ? at : Date.now(), last + 1)
            try {
              const child = spawn(cli, ["hook", "opencode"], { stdio: ["pipe", "ignore", "ignore"] })
              child.on("error", () => {})
              child.stdin.on("error", () => {})
              child.stdin.end(JSON.stringify({ session_id: session, hook_event_name: event, cwd: directory, ts: last, ...extra, ...fields }))
              child.unref()
            } catch {}
            return true
          }
          const ask = (session, permission, patterns, metadata, at) =>
            send(top(session), "Permission", {
              permission,
              patterns: [patterns ?? []].flat().filter((p) => typeof p === "string").slice(0, 20),
              metadata: brief(metadata),
            }, at)
          const question = (session, questions, at) =>
            send(top(session), "Question", {
              questions: (questions ?? []).slice(0, 10).map((q) => ({
                question: String(q?.question ?? "").slice(0, 400),
                header: String(q?.header ?? "").slice(0, 60),
              })),
            }, at)
          return { parents, top, send, ask, question }
        }

        // OpenCode 1.4 to 1.19.
        const server = async ({ directory }) => {
          const { parents, top, send, ask, question } = relay(directory)
          // Sessions in a run, and those whose run just failed: OpenCode goes idle after an error too.
          const running = new Set()
          const failed = new Set()
          const go = (session, event, fields) => {
            // Anything after an error means the run went on.
            if (event !== "StopFailure") failed.delete(session)
            send(session, event, fields)
          }
          const start = (session) => {
            if (!session || parents.has(session)) return
            running.add(session)
            go(session, "UserPromptSubmit")
          }
          return {
            event: async ({ event }) => {
              const p = event?.properties ?? {}
              switch (event?.type) {
                case "session.created":
                  if (p.info?.parentID) parents.set(p.info.id, p.info.parentID)
                  else go(p.info?.id, "SessionStart", { cwd: p.info?.directory || directory })
                  break
                case "session.status":
                  // A run that didn't start with a message, such as a shell command typed in the TUI.
                  if (p.status?.type === "busy" && !running.has(p.sessionID)) start(p.sessionID)
                  break
                case "session.idle":
                  running.delete(p.sessionID)
                  // An error ended the run already.
                  if (!failed.delete(p.sessionID)) go(p.sessionID, "Stop")
                  break
                case "session.error":
                  if (!p.sessionID) break
                  if (p.error?.name === "MessageAbortedError") go(p.sessionID, "Stop")
                  else if (send(p.sessionID, "StopFailure", { error_message: p.error?.data?.message || p.error?.name }))
                    failed.add(p.sessionID)
                  break
                case "session.compacted":
                  go(p.sessionID, "PostCompact")
                  break
                case "session.deleted":
                  go(p.info?.id, "SessionEnd")
                  parents.delete(p.info?.id)
                  break
                case "permission.asked":
                  ask(p.sessionID, p.permission, p.patterns, p.metadata)
                  break
                case "permission.updated":
                  ask(p.sessionID, p.type, p.pattern, p.metadata)
                  break
                case "question.asked":
                  question(p.sessionID, p.questions)
                  break
                case "permission.replied":
                case "question.replied":
                case "question.rejected":
                  go(top(p.sessionID), "Answered")
                  break
              }
            },
            "chat.message": async (input) => start(input?.sessionID),
            "tool.execute.before": async (input, output) =>
              go(input?.sessionID, "PreToolUse", { tool_name: input?.tool, tool_input: brief(output?.args) }),
            "tool.execute.after": async (input) => go(input?.sessionID, "PostToolUse", { tool_name: input?.tool }),
          }
        }

        // OpenCode 2.
        const setup = async (ctx) => {
          const directory = ctx?.location?.directory
          // Plugins run in OpenCode's background service, which isn't where the session is: Ambient keeps no return address.
          const { parents, top, send, ask, question } = relay(directory, { service: true })
          // Every project's copy of the plugin sees every project's events: each passes on its own sessions.
          const mine = new Set()
          const others = new Set()
          // A run's start says nothing of where it is, so one that comes first waits for its session to say.
          const early = new Map()
          // A tool call's name comes before its input.
          const tools = new Map()
          const handle = (event) => {
            const d = event?.data ?? {}
            const session = d.sessionID ?? d.form?.sessionID
            if (typeof session !== "string") return
            const place = event.location?.directory ?? d.location?.directory
            if (place) {
              if (place !== directory) return void others.add(session)
              if (!mine.has(session)) {
                mine.add(session)
                const first = early.get(session)
                early.delete(session)
                if (first) handle(first)
              }
            } else if (!mine.has(session)) {
              if (!others.has(session) && event.type === "session.execution.started" && early.size < 100) early.set(session, event)
              return
            }
            const at = event.created
            switch (event.type) {
              case "session.created":
                if (d.parentID) parents.set(session, d.parentID)
                else send(session, "SessionStart", { cwd: place }, at)
                break
              case "session.execution.started":
                send(session, "UserPromptSubmit", {}, at)
                break
              case "session.execution.succeeded":
                send(session, "Stop", {}, at)
                break
              case "session.execution.interrupted":
                // A new message superseded it: the next run starts at once.
                if (d.reason !== "superseded") send(session, "Stop", {}, at)
                break
              case "session.execution.failed":
                send(session, "StopFailure", { error_message: d.error?.message || d.error?.type }, at)
                break
              case "session.tool.input.started":
                tools.set(d.id, d.name)
                break
              case "session.tool.called":
                send(session, "PreToolUse", { tool_name: tools.get(d.id) ?? "tool", tool_input: brief(d.input) }, at)
                break
              case "session.tool.success":
              case "session.tool.failed":
                send(session, event.type === "session.tool.success" ? "PostToolUse" : "PostToolUseFailure",
                  { tool_name: tools.get(d.id) ?? "tool" }, at)
                tools.delete(d.id)
                break
              case "session.compaction.started":
                send(session, "PreCompact", {}, at)
                break
              case "session.compaction.ended":
              case "session.compaction.failed":
                send(session, "PostCompact", {}, at)
                break
              case "session.deleted":
                send(session, "SessionEnd", {}, at)
                parents.delete(session)
                break
              case "permission.asked":
                ask(session, d.action, d.resources, d.metadata, at)
                break
              case "form.created":
                question(session, (d.form?.fields ?? []).map((f) => ({ question: f?.description || f?.title, header: f?.title })), at)
                break
              case "permission.replied":
              case "form.replied":
              case "form.cancelled":
                send(top(session), "Answered", {}, at)
                break
            }
          }
          const events = ctx.event.subscribe()[Symbol.asyncIterator]()
          ;(async () => {
            try {
              for (;;) {
                const next = await events.next()
                if (next.done) break
                try { handle(next.value) } catch {}
              }
            } catch {}
          })()
          return () => events.return?.()
        }

        export default { id: "ambient", server, setup }

        """#
    }

    /// A JavaScript string literal: JSON's string syntax is valid JavaScript.
    private static func literal(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
