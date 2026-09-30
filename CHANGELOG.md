# Changelog

## Unreleased

- **Living wallpaper**: a Sky, Harbor or Garden scene that follows the time of day, where each agent session
  lives as a star, a boat or a plant in the color of what it's doing, with today's story, the latest moments,
  the clock and your next calendar event. It shows at the desk and on the lock screen. Off by default: turn it
  on in Settings › Wallpaper.
- **Every display**: with an extended display, each desktop shows the full scene and moves only while it can be
  seen; the notch effect plays on the display with the island.
- **Look**: the wallpaper follows the time of day, matches macOS's light or dark mode, or stays light or dark
  (Settings › Wallpaper).
- **Solar System**, a fourth world: agents are planets standing in rows; open the island and they orbit the
  notch, lit as the sun.
- **A black hole at the notch** when the island opens, in Sky, Harbor and Garden: agents swing into orbit
  and dust falls in, then everything drifts home. Turn it off in Settings › Wallpaper.

## 0.2.1 — 2026-09-28

- **Real names**: sessions show their chat title from Claude's desktop app or Claude Code, or their
  thread name from Codex, with the project folder as secondary text. Two chats in one repo no longer
  look the same.
- **Times that mean something**: working sessions show how long the turn has run, *needs you* shows how
  long it has been waiting, and finished or failed sessions show how long ago ("5m ago"). The turn's
  length moves to the bloom card and the menu as "took 1m".

## 0.2.0 — 2026-09-26

- **New settings window**: a floating glass sidebar with Welcome, Agents, Notch Island, Alerts, Dock Glow
  and General. The island, notification and Dock glow panes preview the real thing as you change settings.
- First run opens on a Welcome checklist: connect every agent at once, allow notifications, watch the demo.

## 0.1.1 — 2026-09-26

- **Click to return**: notifications, island rows and menu rows now open the exact chat in Claude's
  desktop app, the thread in Codex's app, the Terminal or iTerm2 tab, the tmux or cmux pane, or the
  project's editor window, falling back to the app.
- `ambient open [project]` jumps to a session from the terminal; with no argument, the most urgent one.
- Codex sessions from Codex's app are recognized even though it doesn't pass its bundle id to hooks.

## 0.1.0 — 2026-09-26

First release.

- Notch island that grows out of the hardware notch (or a virtual notch on other displays): state orb,
  per-session dots, blooms on *needs you* / *done* / *error*, hover for every session, click to return.
- Notifications with synthesized chimes, suppressed while you're in the agent's app and for short turns;
  withdrawn once resolved.
- Menu bar status with the session list, quiet modes and a demo.
- Dock glow in the color of the agents' state, with an edge light when the Dock auto-hides and a glow
  behind the Dock's glass with Accessibility access.
- Claude Code, Codex and Gemini CLI support through background hooks; a safe, reversible installer that
  preserves other hooks, key order, symlinks and permissions, with backups.
- `ambient` CLI: install, uninstall, status, doctor, emit, demo, ack.
- Sessions survive app restarts; sessions whose agent exits are cleaned up automatically.
