# Ambient

**Your Mac, aware of your coding agents.**

Ambient turns what Claude Code, Codex, Gemini CLI, Antigravity, Cursor, Copilot CLI and OpenCode (or any agent or
script you point at it) are doing into calm, glanceable signals on your
desktop, so you can stop babysitting terminals and still never miss the moment an agent needs you.

- **Notch island** — a black pill that grows out of the notch. A coral orb breathes while Claude works,
  an amber pulse means *it needs you*, green means *done*, red means *it hit an error*. When something
  happens it blooms open for a few seconds; hover to see your latest sessions, or *View all* for every one;
  click to jump back to it.
- **Desktop pet** — an optional pixel-art blob, crab or cat that you drag anywhere. It types while your agent works,
  waves when it needs you, cheers when it's done and sleeps when nothing needs you, with a speech bubble saying what's
  going on and a pip per session underneath. Hover it for your sessions, click it for a quick look at all of them,
  click a session to jump to it. Works with or without the notch island; turn it
  on in Settings › Desktop Pet.
- **Read aloud** — select part of a reply in Claude, Codex or your terminal and press ⌥⎋ (or Read Selection Aloud in the menu bar, or, in apps that support it, the app's menu ›
  Services › Speak with Ambient): Ambient reads it to you, with markdown, paths and code blocks turned into something
  worth hearing. Use a Mac voice, Kokoro running offline on your Mac (a one-time download), or OpenAI, ElevenLabs or
  your own server with your key. The island shows it speaking, with pause, continue and stop; the keyboard's ⏯ key
  and AirPods or other headphones pause and continue it too. Set it up in Settings › Voice.
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
- **Living wallpaper** — a sky, a harbor, a garden or a solar system that follows the time of day, where each
  session lives as a star, a boat, a plant or a planet glowing in the color of what it's doing. Around them: today's story (agent
  time, tools, turns, how often they needed you), the latest moments, the clock and your next event. On the
  desktop of every display, and on the lock screen while you're away. Light by day and dark at night, or set it to match macOS
  or stay light or dark. Off until you turn it on in Settings › Wallpaper.
- **When you open the island, the wallpaper answers** — in Sky, Harbor and Garden the notch collapses into a
  black hole: your agents lift off as light and swing into orbits while loose dust falls in, then drift home
  when it closes. In Solar System the notch lights up as the sun and the six most urgent planets orbit it; the
  rest fall into the sun until it closes. Real gravity drives both. They follow Reduce Motion, stay off in Low
  Power Mode, and the black hole can be turned off in Settings › Wallpaper.

Everything stays on your Mac. No accounts and no telemetry. Ambient goes online only when you ask it to: the one-time
offline voice download, and the text you select when you choose an online voice.

## Install

1. Download `Ambient-<version>.dmg` from [Releases](../../releases), open it and drag **Ambient** to Applications.
2. Open Ambient. Settings opens on **Welcome**: click **Connect All** to hook up every agent it found
   (or connect them one at a time under **Agents**).
3. Click **Play Demo** to see every state, then **Get Started**.

Or from a terminal, once the app has run once:

```bash
~/.ambient/bin/ambient install   # every agent found
~/.ambient/bin/ambient doctor    # check the whole chain
```

**Codex** asks you to trust new hooks: run `/hooks` inside Codex once and approve Ambient's.

### Supported agents

| Agent | How Ambient connects | What Ambient sees |
| --- | --- | --- |
| Claude Code (terminal, editors, Claude desktop app) | Hooks in `~/.claude/settings.json` | Everything, including *needs you* |
| Codex (CLI and the Codex app) | Hooks in `~/.codex/hooks.json`, after you approve them with `/hooks` | Everything, including *needs you* |
| Gemini CLI | Hooks in `~/.gemini/settings.json` | Everything, including *needs you* |
| Antigravity | A hook set in `~/.gemini/config/hooks.json` | Prompts, tools, finished or failed turns. Never *needs you*: Antigravity has no permission hook. Tested with the `agy` CLI |
| Cursor, the editor's agent | Hooks in `~/.cursor/hooks.json` | Prompts, tools as they finish (including shell/file/MCP after-hooks), finished turns, compaction. Never *needs you*, see below |
| GitHub Copilot CLI (beta) | Its own hook file, `~/.copilot/hooks/ambient.json` | Prompts, tools, *needs you* for permission prompts and questions, subagents, errors, compaction |
| OpenCode (beta) | A plugin, `~/.config/opencode/plugins/ambient.js` | Prompts, tools, *needs you* for permission requests, finished or failed turns, compaction |
| Anything else | [`ambient emit` or `ambient hook custom`](#any-other-agent) | Whatever it reports |

*Beta* connections follow each agent's documented hooks but haven't yet been run against the agent itself.

Cursor reads the reply of a before-tool hook as a permission decision, so Ambient registers none: it only
uses hooks that can't block or approve anything (`postToolUse`, `afterShellExecution`, `afterFileEdit`,
`afterMCPExecution`, and lifecycle hooks). Tools show up as Cursor finishes them, and Cursor's permission
prompts don't reach Ambient. The `cursor-agent` CLI fires only some of Cursor's hooks so far.

**Task board** — Settings › Board (or *Task Board…* in the menu bar) groups sessions into local tasks by
project and title. Needs-you sessions land in *Blocked*. Turn on **Summarize tasks with local LLM** to call
this Mac's local-agent MCP gateway at `http://127.0.0.1:5051/mcp` (LaunchAgent `com.local-agent.mcp`;
see `local-agents/docs/local-model-mcp.md`). Default model: `hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit`
under `/Volumes/Models` (run `models-on` after plugging in the SSD). Transcript reading is a separate
opt-in; cloud-tagged models are refused. Optional one-shot `ambient task skill-bootstrap` learns a few-shot
pack into `~/.ambient/task-skill.json` using Anthropic from the login Keychain, then the live path stays
local-only. If the gateway or disk is missing, the board keeps metadata heuristics and shows a calm status.
`ambient tasks` / `ambient task upsert` / `ambient task open` talk to the same board.

Aider, Amp and other agents without command hooks can drive Ambient themselves; see
[Any other agent](#any-other-agent).

Requirements: macOS 14 or later. Designed for notched MacBooks; on other displays the island sits at the
top center of the menu bar.

## How it works

```
agent hook ──▶ ambient hook <agent> ──▶ ~/.ambient/ambient.sock ──▶ Ambient.app ──▶ island · notifications · menu bar · Dock
```

Ambient registers a hook for each lifecycle event of your agents (prompt submitted, tool started and
finished, permission requested, turn finished or failed, compaction, subagents, session start and end), or
for OpenCode, which has no command hooks, a small plugin that does the same.
The hook runs the bundled `ambient` command, which reads the event, reduces it to a few short fields,
sends one line over a private Unix socket, and exits — in about 15 ms, always with success, and in the
background for Claude Code and Codex, so it never slows your agent down. If Ambient isn't running,
the event is simply dropped.

The app folds events into a state per session and picks the most urgent across all of them:
**needs you** › **error** › **done** › **working** › **idle**. A finished session stays green until you
look at it — switch to its terminal or editor, or click it — and then settles. Sessions whose agent
process exits disappear on their own.

### Keeping hooks working

Agents change: an update can rewrite their settings or the shape of their hooks. Ambient re-checks every
connected agent's hooks when it starts, every ten minutes, and as soon as an agent's executable or settings
file changes. Out-of-date hooks are rewritten on the spot (with the usual backup). What it can't fix shows in
the menu bar, which gets a **!** and an item with a one-click fix:

- **Hooks were removed** — you connected the agent, but its hooks are gone. *Reconnect* puts them back.
- **Can't read the settings** — the file isn't valid JSON; *Show File* opens it in Finder. Ambient never
  overwrites a file it can't read.
- **Hooks stopped firing** — a session has been busy in a terminal for two minutes, started after its hooks
  were in place, yet not one hook reached Ambient. For Codex that usually means its hooks await approval
  (`/hooks`); otherwise restart the session, since agents read their hooks when they start.

`ambient doctor` runs the same checks from a terminal.

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
| `~/.gemini/config/hooks.json` | A hook set named `ambient` for Antigravity, one hook per event running `~/.ambient/bin/ambient hook antigravity <event>`. Antigravity has no permission event, so its sessions never show *needs you* |
| `~/.cursor/hooks.json` | One entry per Cursor event, running `~/.ambient/bin/ambient hook cursor`, next to your own (and `"version": 1` if the file is new) |
| `~/.copilot/hooks/ambient.json` | A hook file of Ambient's own for Copilot CLI, one entry per event running `~/.ambient/bin/ambient hook copilot <event>`; removed on uninstall |
| `~/.config/opencode/plugins/ambient.js` | A plugin of Ambient's own for OpenCode that starts `~/.ambient/bin/ambient hook opencode` for each event without waiting for it; removed on uninstall |
| `~/.ambient/` | The socket, a link to the bundled CLI, config backups, saved session state, today's story for the living wallpaper, and `agents.json`: which agents you connected |
| `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` | Only with the lock screen option on: while the Mac is locked the scene is set as your wallpaper, so macOS's own lock-screen controls stay on top, and on unlock the store is put back from a backup in `~/.ambient/backups/` |

Every edit keeps your other hooks and settings byte-for-byte, follows symlinked dotfiles, preserves file
permissions, and writes a backup to `~/.ambient/backups/` first. `ambient uninstall` removes only
Ambient's entries.

### Any other agent

Anything that can run a command can drive the island: another agent, a build script, a long job. Give each
session an id and send its state as it changes:

```bash
ambient emit start   --session nightly --agent Build
ambient emit working --session nightly --tool make --detail "make release"
make release && ambient emit done  --session nightly --message "Release built" \
             || ambient emit error --session nightly --message "make failed"
```

Or pipe one JSON object per event to `ambient hook custom`, the way agent hooks do:

```bash
echo '{"session_id":"nightly","event":"done","agent":"Build","message":"Release built"}' | ambient hook custom
```

| Field (`emit` flag) | Meaning |
| --- | --- |
| `session_id` (`--session`) | Required. Any id up to 128 characters, stable for the session |
| `event` (first argument) | `start`, `working`, `waiting`, `done`, `error`, or `end` (`idle` means `end`) |
| `agent` (`--agent`) | The name shown on the island, up to 24 characters. Default: *Agent* |
| `cwd` (`--cwd`) | The project folder; the island shows its name. `emit` uses the current folder |
| `tool`, `detail` (`--tool`, `--detail`) | With `working`: what it's running, e.g. `make` and `make release` |
| `message` (`--message`) | With `waiting`, `done` or `error`: up to 160 characters for the island and the banner |
| `reason` (`--reason`) | With `waiting`: `permission`, or anything else for a question |

The return address is wherever the command runs: clicking the session brings back that terminal tab, tmux
pane or app, and the session disappears once the process that ran the command exits (the nearest one that
isn't a shell). Fields may be added to this interface but are never renamed or removed.

For example, Aider can say when it's waiting for you:

```bash
aider --notifications --notifications-command 'ambient emit done --session "aider-$PPID" --agent Aider --message "Aider is waiting for you"'
```

### Privacy

Only these fields ever leave the hook process, and only to the local socket: the agent, session id,
working directory, event kind, tool name, the return address above, an 80-character hint (a command's first words, a file name, a
host), a 160-character summary of the agent's final message or permission prompt, and which app the agent
runs in. Your prompts and tool output are never read beyond that and never stored.

To notice hooks that stopped firing, Ambient looks once a minute at the processes on your Mac that are agent
sessions in a terminal (Claude Code, Codex, `agy`): their process id, executable path, start time, CPU time used
and whether a terminal is attached. Nothing else about them, never their arguments, environment or output, and
only to compare with the hooks it has heard from. To notice updates it checks each agent's executable path, size and
modification date, and keeps those in memory only. `~/.ambient/agents.json` keeps which agents you connected. None
of it leaves your Mac.

The living wallpaper keeps today's counts and a timeline of what happened, where and when, in
`~/.ambient/day.json` — never prompts, summaries or commands — and starts fresh at midnight. On the lock
screen it hides messages and event titles unless you turn them on. Its calendar line reads only your next
timed event today, and only after you allow Calendar access. On the lock screen the scene is set as your
wallpaper while the Mac is locked, so the password field and login options always stay on top. (An experimental
live layer drawn above the lock screen with a private macOS window API is off: it can cover those controls.)

Reading aloud uses only the text you select, and only when you press the shortcut or choose Speak with Ambient. The shortcut reads the selection through Accessibility, which you allow once; Ambient uses it for nothing else. With
a Mac voice or the offline model it never leaves your Mac. With an online voice, each selection is sent to the service
you chose, with your key, which is kept in your login Keychain. The offline model (Kokoro-82M, about 330 MB, and a
small helper) downloads only when you click Download, from Hugging Face and this repository's releases, and every file
is checked against a hash built into Ambient before it's used.

## Command line

```
ambient install [AGENT …] [--dry-run]                  Add Ambient's hooks (default: every agent found)
ambient uninstall [AGENT …] [--dry-run]                Remove them, leaving everything else alone
ambient status [--json]                                The sessions Ambient is tracking
ambient tasks [--json]                                 The agent task board
ambient task upsert --title TEXT […]                   Create or update a board task
ambient task open ID                                   Jump to a task's linked session
ambient doctor                                         Check the app, the hooks and the connection
ambient emit <working|waiting|done|error|idle>         Send a demo event (--agent, --project, --message)
ambient emit <start|working|waiting|done|error|end> --session ID   Drive a session from any agent or script
ambient demo                                           Walk through every state
ambient open [PROJECT|SESSION]                         Jump to a session's chat, tab or window (default: most urgent)
ambient ack                                            Mark every finished session as seen
```

`AGENT` is `claude`, `codex`, `gemini`, `antigravity`, `cursor`, `copilot` or `opencode`. Add `~/.ambient/bin`
to your `PATH` to use it anywhere. Set `AMBIENT_DEBUG=1` in an agent's environment to
log every hook to `~/.ambient/logs/hook.log`.

## Troubleshooting

- **Nothing happens when an agent runs** — run `ambient doctor`. For Codex, approve the hooks with `/hooks`.
  Agents read hook settings at startup, so restart sessions that were already open.
- **No banners** — allow notifications in Ambient's settings (or System Settings › Notifications › Ambient).
  Ambient deliberately stays quiet while you're in the app running the agent, and for turns shorter than
  the threshold in settings (20 seconds by default).
- **The Dock glow is only a line along the edge** — that's the no-permission mode (and what an
  auto-hiding Dock looks like). Enable *Light up behind the Dock's glass* to grant Accessibility access.
- **The living wallpaper isn't on the lock screen** — Settings › Wallpaper says whether it's shown as your
  wallpaper while locked, or not available on this Mac. If Ambient ever quits while the Mac is locked, it
  puts your wallpaper back the next time it opens; *Restore my wallpaper* shows in Settings until it has.
- **Uninstall** — `ambient uninstall`, quit Ambient from the menu bar, delete the app and `~/.ambient`.

## Build from source

```bash
swift test                      # the core: adapters, state machine, socket, installer
scripts/build-app.sh --run      # build/Ambient.app, ad-hoc signed, and launch it
scripts/release.sh              # universal, Developer ID signed, notarized DMG in dist/
```

`build-app.sh` signs ad-hoc by default, and macOS ties Accessibility access to the signature, so after a
rebuild you may need `tccutil reset Accessibility com.viveky259259.Ambient`.

Ad-hoc builds are dev builds: they add **Settings › Performance**, which shows what Ambient costs the Mac over the
last hour or day (CPU, memory, wallpaper and notch-effect frame rate, hook event delays) and copies or saves a
report. It's measured locally and kept in memory. Developer ID–signed release builds leave it out, and measure
nothing.

| Path | Purpose |
| --- | --- |
| `Sources/AmbientCore` | Everything testable: event model, agent adapters, session reducer, policies, wire format, socket, order-preserving JSON, hook installer |
| `Sources/ambient` | The CLI, including the hot `hook` path |
| `Sources/AmbientApp` | The app: socket server, island, notifications and chimes, menu bar, Dock glow, living wallpaper, setup |
| `scripts/` | App bundle, icon rendering, release |
| `docs/superpowers/` | Design spec and implementation plan |

## License

[MIT](LICENSE). The Dock glow adapts techniques from Orb — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
