# Focus return: click → the exact chat, tab or window

Date: 2026-09-26
Status: approved in chat ("build all of it", ship as v0.1.1)

## Problem

Clicking a notification, an island row or a menu row brings the agent's *app* forward, not the
agent's *chat, tab or window*. With several sessions in one app (Claude desktop tabs, Terminal tabs,
VS Code windows) the user still has to hunt.

## Design

The hook captures a precise return address; the app turns it into an ordered list of routes and
tries them until one works, always ending by bringing the app forward.

### Captured (HostInfo, all optional, backward compatible)

| Field | Source |
| --- | --- |
| `tty` | controlling terminal of the agent process (`kinfo_proc.e_tdev` → `devname`) |
| `hostSessionId` | `CLAUDE_CODE_HOST_SESSION_ID` (Claude desktop's id for a Code session, `local_…`) |
| `tmuxSocket`, `tmuxPane` | `TMUX` (socket path before the first comma), `TMUX_PANE` |
| `cmuxWorkspace`, `cmuxSurface`, `cmuxSocket` | `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`, `CMUX_SOCKET_PATH` |

### Routes (planned in AmbientCore, pure and tested)

1. Claude desktop (`com.anthropic.claudefordesktop`) with a valid `hostSessionId`
   (`^local_[A-Za-z0-9-]{1,64}$`, the app's own validator) → `claude://code/continue?session=<id>&source=ambient`.
2. Codex app (`com.openai.codex`) running a Codex session → `codex://threads/<sessionId>`.
3. tmux pane → `tmux select-window/select-pane`, then the outer terminal's tab by the tmux *client* tty.
4. cmux surface → `cmux focus-panel --panel <surface> --workspace <workspace>`.
5. Terminal.app / iTerm2 with a tty → AppleScript selects the tab/session whose `tty` matches.
6. Any app with a known project → Accessibility: raise the window whose title contains the project
   name (cwd basename, then its parents up to the home directory).
7. Bring the app forward (today's behavior).

Every value interpolated into a script or command is validated in the planner (tty
`^/dev/ttys?[0-9]+$`, tmux pane `^%[0-9]+$`, ids `^[A-Za-z0-9_-]+$`), so nothing from a hook can inject.

### Execution (AmbientApp)

`Focuser` runs routes off the main thread (AppleScript through `osascript`, tmux and cmux through
`Process`, deep links through `NSWorkspace.open`), stops at the first success, and always finishes
by activating the host app via LaunchServices. Used by notification clicks, island rows and menu rows.

### Permissions

- Terminal/iTerm focusing: Automation (Apple Events). Adds `NSAppleEventsUsageDescription` and the
  `com.apple.security.automation.apple-events` hardened-runtime entitlement. macOS asks once per app.
- Window matching: Accessibility (already optional for the Dock glow). Without it, route 6 is skipped.
- A denied or failed route falls through to the next.

## Tasks

1. Capture: `ProcessTree.tty(of:)`, new `HostInfo` fields, `HostCapture` env mapping — tests.
2. Planner: `FocusRoute`, `FocusPlanner.routes(for:)` with validation — tests per host.
3. Executor: `Focuser` + AppleScript/tmux/cmux/AX/deep link runners; wire into `AppModel.open`.
4. Entitlements + Info.plist usage string; build script signs with entitlements.
5. Verify live (Claude desktop deep link, Terminal tab), release v0.1.1.
