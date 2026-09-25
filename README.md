# Ambient

**Your Mac, aware of your coding agents.**

Ambient turns what Claude Code, Codex and Gemini CLI are doing into calm, glanceable signals on your
desktop, so you can stop babysitting terminals and still never miss the moment an agent needs you.

- **Notch island** — a black pill that grows out of the notch. A coral orb breathes while Claude works,
  an amber pulse means *it needs you*, green means *done*, red means *it hit an error*. When something
  happens it blooms open for a few seconds; hover to see every session; click to jump back to it.
- **Click to return** — a notification, an island row or a menu row takes you to the exact place the
  agent runs: the chat in Claude's desktop app, the thread in Codex's app, the Terminal or iTerm2 tab,
  the tmux or cmux pane, or the editor window for the project.
- **Notifications and chimes** — only for moments that need you, and only when you're not already
  looking at the app the agent runs in. Soft, synthesized two-note chimes, one per state.
  Banners withdraw themselves once the prompt is answered.
- **Menu bar** — a status orb and the session list, plus *Quiet alerts* for an hour, three, or until tomorrow.
- **Dock glow** — light along the Dock's edge of the screen in the color of what your agents are doing
  (the technique from [Orb](https://github.com/nithish6541/orbdock)). With Accessibility access it lights
  up behind the Dock's glass itself.

Everything stays on your Mac. No accounts, no network, no telemetry.

## Install

1. Download `Ambient-<version>.dmg` from [Releases](../../releases), open it and drag **Ambient** to Applications.
2. Open Ambient. The setup window lists the agents it found — click **Connect** for each.
3. Click **Play Demo** to see every state, then **Get Started**.

Or from a terminal, once the app has run once:

```bash
~/.ambient/bin/ambient install   # every agent found
~/.ambient/bin/ambient doctor    # check the whole chain
```

**Codex** asks you to trust new hooks: run `/hooks` inside Codex once and approve Ambient's.

Requirements: macOS 14 or later. Designed for notched MacBooks; on other displays the island sits at the
top center of the menu bar.

## How it works

```
agent hook ──▶ ambient hook <agent> ──▶ ~/.ambient/ambient.sock ──▶ Ambient.app ──▶ island · notifications · menu bar · Dock
```

Ambient registers a hook for each lifecycle event of your agents (prompt submitted, tool started and
finished, permission requested, turn finished or failed, compaction, subagents, session start and end).
The hook runs the bundled `ambient` command, which reads the event, reduces it to a few short fields,
sends one line over a private Unix socket, and exits — in about 15 ms, always with success, and in the
background for Claude Code and Codex, so it never slows your agent down. If Ambient isn't running,
the event is simply dropped.

The app folds events into a state per session and picks the most urgent across all of them:
**needs you** › **error** › **done** › **working** › **idle**. A finished session stays green until you
look at it — switch to its terminal or editor, or click it — and then settles. Sessions whose agent
process exits disappear on their own.

### Click to return

Each hook also records a return address — the agent's terminal, Claude desktop's session id, the tmux
pane, the cmux surface — and Ambient uses the most precise route the host supports:

| Agent runs in | A click opens | Needs |
| --- | --- | --- |
| Claude desktop app | the exact chat (`claude://code/continue?session=…`) | nothing |
| Codex app | the exact thread (`codex://threads/…`) | nothing |
| Terminal, iTerm2 | the exact tab | Automation — macOS asks once per terminal |
| tmux, cmux | the exact pane | nothing |
| VS Code, Cursor, other apps | the window for the project | Accessibility (optional) |

Anything that can't be reached precisely falls back to bringing the app forward. `ambient open [project]`
does the same from a terminal or a hotkey; without a project it opens the session that needs you most.

### What Ambient changes on your system

| Where | What |
| --- | --- |
| `~/.claude/settings.json` | One hook group per Claude Code event, all running `~/.ambient/bin/ambient hook claude` |
| `~/.codex/hooks.json` | The same for Codex |
| `~/.gemini/settings.json` | The same for Gemini CLI (hooks named `ambient`) |
| `~/.ambient/` | The socket, a link to the bundled CLI, config backups, saved session state |

Every edit keeps your other hooks and settings byte-for-byte, follows symlinked dotfiles, preserves file
permissions, and writes a backup to `~/.ambient/backups/` first. `ambient uninstall` removes only
Ambient's entries.

### Privacy

Only these fields ever leave the hook process, and only to the local socket: the agent, session id,
working directory, event kind, tool name, the return address above, an 80-character hint (a command's first words, a file name, a
host), a 160-character summary of the agent's final message or permission prompt, and which app the agent
runs in. Your prompts and tool output are never read beyond that and never stored.

## Command line

```
ambient install [claude|codex|gemini …] [--dry-run]    Add Ambient's hooks (default: every agent found)
ambient uninstall [claude|codex|gemini …] [--dry-run]  Remove them, leaving everything else alone
ambient status [--json]                                The sessions Ambient is tracking
ambient doctor                                         Check the app, the hooks and the connection
ambient emit <working|waiting|done|error|idle>         Send a demo event (--agent, --project, --message)
ambient demo                                           Walk through every state
ambient open [PROJECT|SESSION]                         Jump to a session's chat, tab or window (default: most urgent)
ambient ack                                            Mark every finished session as seen
```

Add `~/.ambient/bin` to your `PATH` to use it anywhere. Set `AMBIENT_DEBUG=1` in an agent's environment to
log every hook to `~/.ambient/logs/hook.log`.

## Troubleshooting

- **Nothing happens when an agent runs** — run `ambient doctor`. For Codex, approve the hooks with `/hooks`.
  Agents read hook settings at startup, so restart sessions that were already open.
- **No banners** — allow notifications in Ambient's settings (or System Settings › Notifications › Ambient).
  Ambient deliberately stays quiet while you're in the app running the agent, and for turns shorter than
  the threshold in settings (20 seconds by default).
- **The Dock glow is only a line along the edge** — that's the no-permission mode (and what an
  auto-hiding Dock looks like). Enable *Light up behind the Dock's glass* to grant Accessibility access.
- **Uninstall** — `ambient uninstall`, quit Ambient from the menu bar, delete the app and `~/.ambient`.

## Build from source

```bash
swift test                      # the core: adapters, state machine, socket, installer
scripts/build-app.sh --run      # build/Ambient.app, ad-hoc signed, and launch it
scripts/release.sh              # universal, Developer ID signed, notarized DMG in dist/
```

`build-app.sh` signs ad-hoc by default, and macOS ties Accessibility access to the signature, so after a
rebuild you may need `tccutil reset Accessibility com.viveky259259.Ambient`.

| Path | Purpose |
| --- | --- |
| `Sources/AmbientCore` | Everything testable: event model, agent adapters, session reducer, policies, wire format, socket, order-preserving JSON, hook installer |
| `Sources/ambient` | The CLI, including the hot `hook` path |
| `Sources/AmbientApp` | The app: socket server, island, notifications and chimes, menu bar, Dock glow, setup |
| `scripts/` | App bundle, icon rendering, release |
| `docs/superpowers/` | Design spec and implementation plan |

## License

[MIT](LICENSE). The Dock glow adapts techniques from Orb — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
