# Live check: Claude, Codex, Antigravity and OpenCode against Ambient 0.10.0

On 2026-11-20 one short headless session was run in each agent, in an empty scratch project
(`ambient-live-check`, two files), on a Mac running the notarized Ambient 0.10.0. Each got the same prompt: run `ls`
and say which agent it is. While each ran, `ambient status --json` was polled every half second, and the hooks logged
with `AMBIENT_DEBUG=1`. The board was read with `ambient tasks --json` right after.

Each agent's chat, and what Ambient showed of it, is in its own file:
[claude.md](claude.md), [codex.md](codex.md), [antigravity.md](antigravity.md), [opencode.md](opencode.md).

## Result

| Agent | Version | Ran | Ambient tracked the session | Events that arrived |
|---|---|---|---|---|
| Claude | Claude Code 2.1.328 | yes | yes | start, prompt, tool (`ls`), turn completed, end |
| Codex | codex-cli 0.164.0 | yes, on `gpt-5.6-terra` | yes | start, prompt, tool (`ls`), turn completed, end |
| Antigravity | agy 1.5.13 | yes | yes | start, prompt, tool (`ls`), turn completed; no end |
| OpenCode | 2.2.6 | yes, on `opencode/beam-free` | yes | prompt, then done; no tool, no end |

Not checked: the island, the notifications and the wallpaper, which nobody looked at during the run. This covers the
hooks, the session list and the board only.

## What it turned up

1. **Every task got the same made-up title.** All 12 board tasks for the folder are titled *Implement JWT refresh
   token rotation*, with the summary *Add automatic token refresh on 401 responses.* No session did anything like
   that. The same text is in this Mac's `~/.ambient/task-skill.json`, so the local model seems to repeat an example
   from the skill pack when a session gives it little to go on. The cause wasn't traced further.
2. **A session that dies before its first reply still makes a task.** Codex's configured model (`gpt-6.1-terra`) is
   refused for a ChatGPT account, and nine guesses at another name were refused too. Each of those ten attempts lasted
   about a second and left a *Done* task of its own, so one folder has 11 Codex tasks for one piece of work.
3. **OpenCode sends no tool or end events from `opencode run`.** The session went from *thinking* to *done* and was
   still listed a minute after the process exited; its task stayed *In progress* with the session linked. The failed
   first attempt stayed *thinking* for at least 40 seconds after it exited. The hook log has one OpenCode line for both
   runs, though the app showed both sessions, which wasn't explained.
4. **Antigravity's print mode sends no end event**, its turn-completed carries no summary, and one 872-byte payload
   was ignored. Its task was left in *Backlog* after the turn finished.
5. **A task's last chat records the app the agent was started from.** These sessions were started from a Claude
   desktop chat, so the Codex and Antigravity tasks' `lastChat.host` is Claude's app with that chat's id. Clicking those
   cards would open the Claude chat, not the agent's. That's the launch setup here, and may not happen from a terminal.
6. **OpenCode's hooks aren't installed on this Mac** (`ambient doctor` says so). The check ran OpenCode with scratch
   `XDG_*` folders holding the plugin that `ambient install opencode --dry-run` prints, so the user's own OpenCode
   config wasn't touched. That dry run says it *would update* `~/.config/opencode/plugins/ambient.js`, a file that
   doesn't exist.

## The board afterwards

`ambient tasks --json`, tasks for this folder (all with the title and summary from finding 1):

| Task | Status | Agents | Linked sessions |
|---|---|---|---|
| task-7a90864d | inProgress | opencode, codex | 1 (OpenCode's) |
| task-68666202 | backlog | antigravity | 0 |
| task-a0e49bce | done | claude, opencode, codex | 0 |
| nine more | done | codex | 0 |

## How it was run

- Claude: `claude -p "<prompt>" --allowedTools "Bash(ls:*)"`
- Codex: `codex exec -m gpt-5.6-terra "<prompt>"` (read-only sandbox, the default)
- Antigravity: `agy -p "<prompt>" --print-timeout 150s`
- OpenCode: `opencode run -m opencode/beam-free "<prompt>"`, with scratch `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
  `XDG_STATE_HOME` and `XDG_CACHE_HOME`. The first try, on `opencode/deepseek-v4.1-flash-free`, hit the free usage limit.

Paths in the transcripts are shortened: `<scratch>` is the temporary folder the project was in.
