import Foundation

/// The plugin `ambient install opencode` writes to ~/.config/opencode/plugins/ambient.js. OpenCode has no
/// command hooks, so the plugin turns its events into Claude-style payloads for `ambient hook opencode`,
/// starting the command without waiting for it. OpenCode loads every export of a plugin file as a plugin,
/// so the file exports exactly one function.
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
        return """
        // Ambient (https://yaml.cafe) shows what OpenCode is doing at the notch, in notifications and on the Dock.
        // `ambient install opencode` wrote this file and `ambient uninstall opencode` removes it. Edits are overwritten.
        // Each event hands a few fields to the local `ambient` command, which never holds OpenCode up.
        import { spawn } from "node:child_process"
        import { existsSync } from "node:fs"
        import { homedir } from "node:os"
        import { join } from "node:path"

        export const AmbientPlugin = async ({ directory }) => {
          const cli = \(path)
          // Subagent sessions are part of their parent's turn.
          const children = new Set()
          const send = (session, event, fields = {}) => {
            if (!session || children.has(session) || !existsSync(cli)) return
            try {
              const child = spawn(cli, ["hook", "opencode"], { stdio: ["pipe", "ignore", "ignore"] })
              child.on("error", () => {})
              child.stdin.on("error", () => {})
              child.stdin.end(JSON.stringify({ session_id: session, hook_event_name: event, cwd: directory, ...fields }))
              child.unref()
            } catch {}
          }
          return {
            event: async ({ event }) => {
              const p = event?.properties ?? {}
              switch (event?.type) {
                case "session.created":
                  if (p.info?.parentID) children.add(p.info.id)
                  else send(p.info?.id, "SessionStart", { cwd: p.info?.directory || directory })
                  break
                case "session.idle":
                  send(p.sessionID, "Stop")
                  break
                case "session.error":
                  if (p.error?.name === "MessageAbortedError") send(p.sessionID, "Stop")
                  else send(p.sessionID, "StopFailure", { error_message: p.error?.data?.message || p.error?.name })
                  break
                case "session.compacted":
                  send(p.sessionID, "PostCompact")
                  break
                case "session.deleted":
                  send(p.info?.id, "SessionEnd")
                  break
                case "permission.updated":
                case "permission.asked":
                  send(p.sessionID, "Notification", { notification_type: "permission_prompt", message: p.title })
                  break
              }
            },
            "chat.message": async (input) => send(input?.sessionID, "UserPromptSubmit"),
            "tool.execute.before": async (input, output) =>
              send(input?.sessionID, "PreToolUse", { tool_name: input?.tool, tool_input: output?.args }),
            "tool.execute.after": async (input) => send(input?.sessionID, "PostToolUse", { tool_name: input?.tool }),
          }
        }

        """
    }

    /// A JavaScript string literal: JSON's string syntax is valid JavaScript.
    private static func literal(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
