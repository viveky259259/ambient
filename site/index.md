# Ambient: your Mac, aware of your coding agents

> Ambient is a free, native macOS app that makes your Mac the calmest place to work alongside AI coding agents. It turns what Claude Code, Codex and Gemini CLI are doing into signals at the notch, in notifications, along the Dock and across an optional living wallpaper, and one click takes you back to the exact chat, terminal tab or tmux pane where an agent needs you.

**Get it:** [yaml.cafe](https://yaml.cafe/), free, every feature, no account. macOS 14 or later, Apple silicon and Intel. The download starts on the first click.

## Why people run Ambient

Coding agents work for minutes at a time, then stop to ask a question, wait for a permission or finish. Without Ambient you find out by checking terminals. With Ambient your Mac tells you, quietly, at the moment it matters.

- **Glance, don't babysit.** One color at the notch says what every agent is doing: working, needs you, done or error.
- **Back in one click.** A notification, an island row or a menu row opens the exact place the agent runs, not just the app.
- **Alerts only when they matter.** Banners and soft chimes for a question, a finished turn or a failure, and silence while you're already looking at the agent.
- **Every agent in one place.** Claude Code, Codex and Gemini CLI, in any terminal or editor and in the Claude and Codex desktop apps, sorted most urgent first.
- **Private by design.** No accounts, no network requests, no telemetry. Events never leave your Mac.
- **Made for the Mac.** A notch island in macOS glass, a Dock glow, a menu bar list and a living wallpaper. Designed for MacBooks with a notch; on other displays the island sits at the top center of the menu bar.

## What you see

### The notch island

A black pill grows out of the notch and shows your agents' state in one color. When something happens it blooms open into macOS glass for a few seconds. Hover to see every session.

| State | What it looks like | When |
| --- | --- | --- |
| Working | An orb in the agent's color breathes | The agent is thinking and running tools |
| Needs you | An amber pulse | The agent is waiting for a permission or an answer |
| Done | Green, until you look at the session | The turn finished |
| Error | Red, with the reason one hover away | The turn failed |

Across all sessions Ambient shows the most urgent state: needs you, then error, then done, then working.

### Click to return

| The agent runs in | A click opens |
| --- | --- |
| The Claude desktop app | The exact chat |
| The Codex app | The exact thread |
| Terminal or iTerm2 | The exact tab |
| tmux or cmux | The exact pane |
| VS Code, Cursor and other editors | The project's window |

From a terminal, `ambient open` jumps to the session that needs you most.

### Notifications and chimes

Banners and soft two-note chimes, one sound per state, so you know which without looking. Ambient stays quiet while you're already in the app running the agent, skips turns shorter than 20 seconds by default, and withdraws a banner once you've answered.

### The Dock glow

Light rises along the Dock in the color of what your agents are doing: visible from across the room, invisible to your work.

### The living wallpaper

Off until you turn it on in Settings › Wallpaper. Your desktop becomes a scene that follows the time of day (Sky, Harbor, Garden or Solar System, or a new one each day) where every session lives as a star, a boat, a plant or a planet in the color of its state, with the clock, your next calendar event (read on your Mac) and the day's story. Open the island and a black hole forms at the notch, or the Solar System's sun lights up, and the agents orbit it. It follows the time of day, matches macOS light or dark mode, or stays light or dark, and shows on every display and on the lock screen. Your own wallpaper is untouched.

## Works with the agents you use

| Agent | Where |
| --- | --- |
| Claude Code | Terminal, editors and the Claude desktop app |
| Codex | The CLI and the Codex app |
| Gemini CLI | Every session, in any terminal |

## How it works

Ambient listens to the hooks each agent already offers. Nothing wraps your agent, and nothing watches your screen.

1. **Connect.** Open Ambient and click **Connect All**. It adds its own entries to `~/.claude/settings.json`, `~/.codex/hooks.json` and `~/.gemini/settings.json`, after backing each file up.
2. **Listen.** When an agent starts a turn, runs a tool, asks for permission or finishes, its hook runs the bundled `ambient` command, which sends one short line over a Unix socket on your Mac. In about 15 ms, in the background for Claude Code and Codex, and always exiting successfully, so it never slows an agent down.
3. **Show.** Ambient keeps a state for every session and shows the most urgent one.

```
agent hook ──▶ ambient hook <agent> ──▶ ~/.ambient/ambient.sock ──▶ Ambient.app ──▶ island · notifications · menu bar · Dock · wallpaper
```

## Privacy

Ambient collects nothing. It has no accounts, makes no network requests and sends no telemetry. Each hook reduces an event to a few short fields (agent, state, project name, a trimmed message) and sends them to the app on your Mac. Your prompts and tool output are never stored.

## Install

1. Download Ambient from [yaml.cafe](https://yaml.cafe/), open the disk image and drag Ambient to Applications.
2. Open Ambient and click **Connect All**.
3. For Codex, type `/hooks` in Codex once and approve Ambient's hooks. Restart agent sessions that were already open.

From a terminal, once the app has run:

```bash
~/.ambient/bin/ambient doctor      # check the app, the hooks and the connection
~/.ambient/bin/ambient open        # jump to the session that needs you most
~/.ambient/bin/ambient uninstall   # remove only Ambient's hooks
```

## Ambient and the agents' own notifications

| | Built-in notifications | Ambient |
| --- | --- | --- |
| Works in | Some terminals (Claude Code: Ghostty, Kitty, iTerm2; others ring a bell) | Any terminal or editor, and the Claude and Codex apps |
| Status while it works | No | Yes: notch, menu bar, Dock and wallpaper |
| Many sessions | One notification each | Every session at once, most urgent first |
| A click takes you to | Depends on the terminal | The exact tab, tmux pane, chat or thread |
| Agents | One | Claude Code, Codex and Gemini CLI |

Step-by-step guides for each agent's own options:

- [Claude Code notifications on Mac](https://yaml.cafe/guides/claude-code-notifications-mac/)
- [Codex notifications on Mac](https://yaml.cafe/guides/codex-notifications-mac/)
- [Gemini CLI notifications on Mac](https://yaml.cafe/guides/gemini-cli-notifications-mac/)

## Questions

**Is Ambient free?** Yes, every feature. No account, no sign-up to download.

**Will it slow my agent down?** No. Hooks finish in about 15 ms, run in the background for Claude Code and Codex, and always exit successfully. If Ambient isn't running, events are simply dropped.

**Which Macs does it run on?** macOS 14 or later, on Apple silicon and Intel.

**Does it work over SSH?** Ambient needs the agent to run on the same Mac; hooks on a remote machine can't reach it.

**How do I remove it?** Run `ambient uninstall` (your other settings stay exactly as they were), quit Ambient, and delete the app and `~/.ambient`.

**How do I ask for a feature?** Suggest it or vote on the [feature requests board](https://yaml.cafe/requests/), or choose **Suggest a Feature…** from Ambient's menu bar menu.

## More

- [yaml.cafe](https://yaml.cafe/): download and the full page
- [llms.txt](https://yaml.cafe/llms.txt): key facts, and when Ambient is and isn't a fit
- [Feature requests](https://yaml.cafe/requests/)
- [Privacy](https://yaml.cafe/privacy.html) · [Contact](https://yaml.cafe/contact/)

Made by yaml.cafe. Claude, Codex and Gemini are trademarks of their owners; Ambient isn't affiliated with Anthropic, OpenAI or Google.
