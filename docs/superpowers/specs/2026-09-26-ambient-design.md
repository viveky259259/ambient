# Ambient — ambient status for coding agents on macOS

Date: 2026-09-26
Status: approved (surfaces, stack, release, agent scope confirmed in chat)

## Problem

Coding agents (Claude Code, Codex, Gemini CLI) run for minutes at a time and then either finish or stop
to ask for permission. Developers either babysit the terminal or miss the moment the agent needs them.
Terminal bells and banner notifications are noisy, easy to miss, and carry no sense of *ongoing* state.

Ambient makes agent state part of the desktop itself: the notch, the Dock, the menu bar, and — only when
it matters — a notification and a soft sound. Inspired by Orb (Dock takes on album colors) and DeskModes
(notch island with agent activity).

## Goals

- Glanceable: know "working / needs me / done / broken" without switching apps.
- Zero cost to the agent: hooks never block or slow the agent, and never fail it.
- Multi-agent, multi-session: several Claude/Codex/Gemini sessions at once, one calm aggregate signal.
- One click back: clicking a session returns you to the app it runs in, and acknowledges it.
- Production-grade setup: safe, reversible, idempotent hook installation; `ambient doctor`; signed and
  notarized DMG.

## Non-goals (v1)

- Window layouts, clipboard, widgets (DeskModes features unrelated to agent state).
- Jumping to a specific terminal *tab* (v1 activates the host app).
- Usage/quota meters.
- Remote/cloud agent sessions.

## Surfaces (priority order)

1. **Notch island** — a black pill that extends the hardware notch (or floats at top-center on displays
   without one). Collapsed: a state glyph on the left wing, a short label/count on the right wing.
   On important transitions it *blooms* for a few seconds ("api-server · Done — Fixed the flaky test").
   Hover expands to a session list; click a row to focus the host app.
2. **Notifications + sound** — `UNUserNotificationCenter` banner plus a soft sound on *needs input*,
   *done* and *error*, only when the session's host app is not frontmost, and for *done* only when the
   turn ran longer than a threshold (default 20 s). Click → focus host app.
3. **Menu bar** — status glyph tinted by aggregate state; menu lists sessions, pause, preferences, setup.
4. **Dock glow** — Orb's technique: a click-through window one level below the Dock, painting a soft
   floor of light along the Dock edge and a brighter feathered layer behind the Dock glass. Color and
   motion encode state. Needs Accessibility for the exact Dock rect; without it, floor-only glow.

## State model

Per session (key = agent + session id):

| Activity | Meaning | Priority |
|---|---|---|
| `waiting` | agent asked for permission / input | 5 |
| `error` | turn failed (API error, rate limit, …) | 4 |
| `done` (unacknowledged) | turn finished, user hasn't looked yet | 3 |
| `working` (`thinking` / `tool` / `compacting`) | agent busy | 2 |
| `done` (acknowledged), `idle` | nothing to do | 0 |

Aggregate state = highest-priority session. Acknowledgement happens when the user activates the
session's host app, clicks the session, or starts a new prompt. Busy sessions with no event for 10 min
become `idle` (killed agents); `SessionEnd` removes the session; idle sessions expire after 2 h.

Events are applied in timestamp order per session; an event older than the last applied one is ignored
for state transitions (async hooks can arrive out of order).

### Normalized events

`sessionStarted`, `promptSubmitted`, `toolStarted(name, detail)`, `toolFinished(name, failed)`,
`needsInput(reason, message)`, `compactStarted`, `compactFinished`, `subagentStarted`,
`subagentFinished`, `turnCompleted(summary)`, `turnFailed(message)`, `sessionEnded`, `notice(message)`.

### Agent mappings

| Normalized | Claude Code | Codex | Gemini CLI |
|---|---|---|---|
| sessionStarted | SessionStart | SessionStart | SessionStart |
| promptSubmitted | UserPromptSubmit | UserPromptSubmit | BeforeAgent |
| toolStarted | PreToolUse | PreToolUse | BeforeTool |
| toolFinished | PostToolUse / PostToolUseFailure | PostToolUse | AfterTool |
| needsInput | PermissionRequest, Notification(permission_prompt, elicitation_dialog, agent_needs_input) | PermissionRequest | Notification(ToolPermission) |
| compactStarted/Finished | PreCompact / PostCompact | PreCompact / PostCompact | PreCompress / — |
| subagent* | SubagentStart / SubagentStop | SubagentStart / SubagentStop | — |
| turnCompleted | Stop | Stop | AfterAgent |
| turnFailed | StopFailure | — | — |
| sessionEnded | SessionEnd | SessionEnd | SessionEnd |

## Architecture

```
agent hook ──▶ ambient CLI (hook) ──▶ unix socket ~/.ambient/ambient.sock ──▶ Ambient.app
   (stdin JSON)   adapter → normalized      one JSON line per connection        SessionStore
                  event, truncated,                                             ├─ Notch island
                  exits 0 always                                                ├─ Notifier + sound
                                                                                ├─ Menu bar
                                                                                └─ Dock glow
```

SwiftPM package:

- `AmbientCore` (Foundation only, fully unit tested): event model, agent adapters, session reducer and
  aggregate, wire format, socket client/server, order-preserving JSON, hook installers, paths.
- `ambient` (CLI): `hook`, `install`, `uninstall`, `status`, `doctor`, `emit`, `demo`, `version`.
- `AmbientApp` (AppKit + SwiftUI): socket server, state store, surfaces, onboarding, preferences.

Bundle layout: `Ambient.app/Contents/MacOS/Ambient` (app), `Ambient.app/Contents/Helpers/ambient` (CLI).
The app maintains `~/.ambient/bin/ambient → <bundle>/Contents/Helpers/ambient` on every launch, so hooks
survive the app being moved.

### Hook command

```
[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook claude || true
```

- Claude: registered with `"async": true` so it never delays a tool call.
- Codex: `"async": true`; Codex requires the user to trust new hooks via `/hooks` — `doctor` explains.
- Gemini: synchronous only; `timeout: 1500` ms. The CLI must stay fast (no work beyond parse + send).

The CLI reads stdin, normalizes, captures host info (`__CFBundleIdentifier`, `TERM_PROGRAM`, parent pid
chain), sends one line with a 250 ms connect/send timeout, and exits 0. It never prints to stdout.

### Privacy

Everything stays on the machine. Only compact fields cross the socket: tool name, a ≤80-char detail
(command head / file name), and a ≤160-char summary of the final message. Prompts and tool output are
never sent. The socket lives in `~/.ambient` (mode 0700).

### Hook installer

Order-preserving JSON edit of `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.gemini/settings.json`.
Our entries are identified by the `.ambient/bin/ambient` marker. Install is idempotent, removes stale
Ambient entries first, never touches other hooks, backs the file up to `~/.ambient/backups/` and writes
atomically. Uninstall removes only our entries and prunes empty containers.

### Focus return

Host app resolved from `__CFBundleIdentifier` (inherited by terminal shells and IDE terminals), falling
back to the first ancestor process that is a GUI app. Activating that app acknowledges its sessions.

## Visual language

- Working: Claude coral `#D97757` (Codex: `#10A37F`-ish teal, Gemini: `#4F8DF7` blue) slow 3.2 s breath.
- Waiting: amber `#F5A524`, faster 1.2 s pulse.
- Done: green `#3FB950`, gentle bloom then steady until acknowledged.
- Error: red `#F85149`, two quick pulses then steady dim.
- Motion respects "Reduce Motion" (no pulsing; static tint).

## Error handling

- App not running → CLI drops the event silently.
- Malformed hook JSON → CLI exits 0, logs only with `AMBIENT_DEBUG=1`.
- Socket path stale → app unlinks and rebinds on launch; second instance exits.
- Hook config unparsable → installer refuses to write and reports the file and error.

## Testing

- Unit: adapters (fixture payloads per agent), reducer sequences, aggregate priority, out-of-order events,
  staleness, JSON round-trip preserving order/formatting, installer install/reinstall/uninstall.
- Integration: socket server + client round trip; CLI end-to-end with a temp home (`AMBIENT_HOME`).
- App: `ambient demo` drives every state; verified visually by screenshot.

## Release

`scripts/build-app.sh` (bundle, icon, sign), `scripts/release.sh` (Developer ID sign with hardened
runtime, notarize, staple, DMG). GitHub Actions: build + test on every push; release workflow on tags.
