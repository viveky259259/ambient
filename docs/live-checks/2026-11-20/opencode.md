# OpenCode live check

OpenCode 2.2.6, against Ambient 0.10.0.

```
start 2026-11-20T18:29:12Z
exit 0
end 2026-11-20T18:29:15Z
model opencode/beam-free
```

## Command

```
opencode run -m opencode/beam-free "<prompt>"
```

## Prompt

> Run `ls` in the current directory, then reply in one sentence saying which coding agent you are and which files you saw. Do not change anything.

## Reply (stdout)

```
I'm Claude (Beam), a coding agent in OpenCode, and I saw README.md and hello.txt in the current directory.
```

## The rest of the chat (stderr)

```
> build · beam-free
$ ls
README.md
hello.txt
> build · beam-free
```

## What Ambient showed

`ambient status --json`, polled every half second while the agent ran (changes only):

```
opencode:ses_e05c7c051ffe1wDEpXMx6e2HQI  {"thinking": {}}
```

Hook log (`AMBIENT_DEBUG=1`, `~/.ambient/logs/hook.log`), every line for this agent in the test window, failed attempts included:

```
2026-11-20T18:28:17Z sent opencode promptSubmitted
```

## The first attempt, which failed

```
start 2026-11-20T18:28:16Z
exit 1
end 2026-11-20T18:28:18Z
```

```
> build · deepseek-v4.1-flash-free
Error: Free usage limit reached. Connect a provider or subscribe to OpenCode Go to keep going, or switch models.
```
