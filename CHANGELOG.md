# Changelog

## Unreleased

- **Homebrew cask**: `scripts/update-cask.sh` writes the cask for a published release into the tap, with the checksum
  from the GitHub release, and the cask downloads from yaml.cafe with `?ref=brew` so Homebrew installs are counted on
  their own.
- **Answer permission prompts from the island** (off by default; Settings › Island): Claude Code and Codex tool
  requests open a card at the notch with the agent, the project and the command, file or host, and *Allow once*
  or *Deny*. Ambient never answers for you: a prompt you don't answer within the wait you choose (20 seconds by
  default), or one you'd rather answer in the agent's own app, goes back to the agent, which asks as usual.
  Several prompts queue in order, and the buttons ignore clicks for the first moment so a card that appears under
  the pointer can't be approved by accident. Only the permission hook waits, and only with the setting on;
  Codex asks you to approve the changed hook once with `/hooks`.
- **Hooks that keep working**: Ambient re-checks each connected agent's hooks at launch, every ten minutes, and as
  soon as the agent updates or its settings change, and rewrites out-of-date hooks with the usual backup. What it
  can't fix gets a **!** in the menu bar and a one-click fix: hooks an update removed (*Reconnect*), settings it
  can't read (*Show File*), and a terminal session that's been busy for two minutes without a single hook reaching
  Ambient (for Codex, usually hooks awaiting `/hooks` approval). `ambient doctor` reports removed hooks too.
- **Fix**: the task board kept re-rendering every card on every agent event, even after you closed it, which could
  take a whole CPU core with a long-lived board. Closing it now frees it, and only the cards on screen are drawn:
  with 1,626 tasks, 97% of a core and 590 MB became 1.6% and 90 MB.
- **Performance, measured**: the README now lists what Ambient costs, feature by feature: 0.1% CPU with the island
  alone when nothing happens, 0.5% while agents work, 1.2% with everything on (Apple M5 Max). `scripts/measure-perf.sh`
  reproduces the numbers on any Mac with a separate copy of the app, leaving yours and its settings alone.
- **Remote agents**: follow Claude Code and Codex on your other machines from this Mac, over your own `ssh` or any
  other transport, with no accounts, no relay and no open ports. `ambient remote add NAME` copies a small POSIX `sh`
  shim from the app, checks its SHA-256, installs hooks and pins the machine's identity; `remove`, `purge`, `list` and
  `ambient doctor --remote NAME` look after it, and Settings › Remote shows each link. Sessions carry their machine's
  label in the island, menu bar, pet, notifications and board. Redaction (`metadata`, `standard` by default, or `full`)
  happens on the machine; remote text never reaches online voices or any non-loopback address. Remote events go
  through their own strict decoder and can't touch the app's socket, focus routes or pid checks. Events wait in a
  bounded spool while your Mac sleeps; old prompts show as *missed* with no chime, and sessions on an unreachable
  machine show as *unknown*. A local audit log records what happened, with no event content.

## 0.7.0 — 2026-10-23

- **Task board**: Settings › Board and a dedicated **Task Board** window (menu *Task Board…*) show a local Kanban of
  agent work — backlog, in progress, blocked, done — grouped from session metadata (project, titles, same-day
  sessions; needs-you → blocked). Optional **local LLM** summaries via the local-agent MCP gateway
  (`http://127.0.0.1:5051/mcp` only — non-loopback URLs refused; default model
  `hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit` on `/Volumes/Models`). LLM options collapse by default in Settings.
  Transcript reading is opt-in; cloud-tagged models are blocked; heuristics remain the fallback when the gateway or
  SSD is unavailable. Optional **wallpaper board cues** (Settings › Wallpaper / Board; off by default) draw soft
  title + status chips on the living wallpaper when tasks are blocked or in progress. Persist to
  `~/.ambient/tasks.json`. Optional one-shot `ambient task skill-bootstrap` writes a few-shot skill pack to
  `~/.ambient/task-skill.json` (Anthropic from Keychain only; never the live path). CLI: `ambient tasks`,
  `ambient task upsert`, `ambient task open`, `ambient task skill-bootstrap`, `ambient task skill-status`.
- **Cursor (first-class)**: no longer beta. Installs after-the-fact tool hooks (`afterShellExecution`,
  `afterFileEdit`, `afterMCPExecution`) so the island shows tools while Cursor works; still never uses
  permission-style hooks. Click-to-return prefers the Cursor editor window for the project.
- **More agents (beta)**: connect **GitHub Copilot CLI** and **OpenCode** in Settings › Agents or with
  `ambient install`, and `ambient doctor` checks each one. They're marked beta until they've run against the
  real agents; Settings › Agents and the README say what each one shows.
- **Antigravity**: checked against a real `agy` 1.4 session: sessions, prompts, tools and finished turns all arrive.
  Turns that end with reasons spelled in capitals (as agy sends them) are now read correctly. Copilot CLI gets a hook file of Ambient's own
  (`~/.copilot/hooks/ambient.json`), OpenCode a small plugin (`~/.config/opencode/plugins/ambient.js`), and both
  show *needs you* for permission prompts. Cursor's hooks go next to yours in `~/.cursor/hooks.json`; Ambient uses
  only hooks that can't block or approve anything, so Cursor sessions show tools as they finish and never show
  *needs you*.
- **Any other agent**: `ambient emit <start|working|waiting|done|error|end> --session ID [--agent NAME]` and
  `ambient hook custom` (one JSON object per event) let any agent or script drive the island, with its own name,
  a return address to the terminal it runs in, and a session that ends with its process. The README documents
  the fields, with an example for Aider.
- **Read aloud**: select part of a reply in Claude, Codex or a terminal and press ⌥⎋ (Option-Escape; change it in Settings › Voice), or choose Services › Speak
  with Ambient, to hear it. Markdown symbols are dropped, links read by their label, long paths shortened and code
  blocks summarized (or read out, if you prefer). The first time, Ambient asks which voice to use: a Mac voice, the
  offline Kokoro model (a one-time download, Apple silicon and macOS 15 or later), or an online voice from OpenAI,
  ElevenLabs or your own server with your key. The island, menu bar and pet show it speaking with pause, continue
  and stop (the keyboard's ⏯ key and AirPods or headphones work too), and say why if it can't. Change it any time
  in Settings › Voice.
- **Antigravity**: connect Google Antigravity in Settings › Agents (or `ambient install antigravity`). Ambient adds a
  hook set named `ambient` to `~/.gemini/config/hooks.json` and follows each conversation through prompts, tool calls
  and finished or failed turns. Antigravity has no permission hook, so its sessions never show *needs you*.
- **View all**: with more than five sessions, the hovered island offers *View all*, which lists every session and
  scrolls past ten.
- **Fix**: `ambient status` and `ambient open` no longer say Ambient isn't running when it tracks many sessions. The
  app cut off any reply longer than 8 KB.

## 0.6.0 — 2026-10-10

- **Desktop pet**: an optional pixel-art companion (a blob, a crab or a cat) that you drag anywhere on your desktop.
  It acts out your most urgent agent session: typing while it works, waving with a "!" when it needs you, cheering
  when it's done, sweating when it fails, and sleeping when nothing needs you. Its speech bubble says what that
  session is doing. Hover the pet for your sessions and the island's actions; click it and it reacts with a burst of
  pixels and pins a quick look at every session; click a session to jump to it. With several sessions, pips under the
  pet show each one at a glance, the bubble says when another one needs you, and the pet holds up how many are
  waiting. It shows only sessions worth your attention, and works with or without the notch island.
  Turn it on in Settings › Desktop Pet or from the menu bar.

## 0.5.1 — 2026-10-03

- **Fixed**: with the living wallpaper on the lock screen, the password field and login options could be hidden.
  While the Mac is locked the scene is now set as your wallpaper, under macOS's own lock-screen controls, and your
  wallpaper comes back when you unlock.
- **Macs without a notch** (Mac Studio, Mac mini, external displays): the island now sits on the display with the
  menu bar and follows it when you move the menu bar; hovering the top center of the menu bar opens it even when no
  agent is running; and the black hole and the sun are drawn as large as on a MacBook.

## 0.5.0 — 2026-10-01

- **Suggest a Feature…**: a new item in the menu bar menu opens the feature-request board on yaml.cafe, where you
  can tell us what Ambient should bring you next and vote for other people's ideas. No account needed, and the app
  itself still makes no network requests.
- **About**: Settings › General now links to yaml.cafe and the feature-request board.
- **Development builds** gain Settings › Performance: CPU, memory, wallpaper and notch-effect frame rate, and hook
  event delays over the last hour or day, with a report to copy or save. Release builds leave it out.

## 0.4.0 — 2026-09-30

- Maintenance release: no changes from 0.3.0.

## 0.3.0 — 2026-09-30

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
- **Glass island**: the open island and its cards are macOS glass; only the notch itself stays black.

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
