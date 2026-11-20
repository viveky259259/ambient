# Claude live check

Claude Code 2.1.328, against Ambient 0.10.0.

```
start 2026-11-20T18:28:16Z
exit 0
end 2026-11-20T18:28:25Z
```

## Command

```
claude -p "<prompt>" --allowedTools "Bash(ls:*)"
```

## Prompt

> Run `ls` in the current directory, then reply in one sentence saying which coding agent you are and which files you saw. Do not change anything.

## Reply (stdout)

```
I'm Claude Code, Anthropic's coding agent (running on Claude Opus 5.5), and `ls` shows two files here, `README.md` and `hello.txt`; I didn't change anything.
```

## What Ambient showed

`ambient status --json`, polled every half second while the agent ran (changes only):

```
claude:d42dcc45-9070-47e6-9c0c-4363eb4f6d41  {"idle": {}}
claude:d42dcc45-9070-47e6-9c0c-4363eb4f6d41  {"thinking": {}}
```

Hook log (`AMBIENT_DEBUG=1`, `~/.ambient/logs/hook.log`), every line for this agent in the test window, failed attempts included:

```
2026-11-20T18:28:16Z sent claude sessionStarted
2026-11-20T18:28:19Z sent claude promptSubmitted
2026-11-20T18:28:20Z sent claude toolStarted(name: "Bash", detail: Optional("ls"))
2026-11-20T18:28:20Z sent claude toolFinished(name: "Bash", failed: false)
2026-11-20T18:28:24Z sent claude turnCompleted(summary: Optional("I\'m Claude Code, Anthropic\'s coding agent (running on Claude Opus 5.5), and `ls` shows two files here, `README.md` and `hello.txt`; I didn\'t change anything."))
2026-11-20T18:28:24Z sent claude sessionEnded
```
