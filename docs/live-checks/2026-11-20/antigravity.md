# Antigravity live check

agy 1.5.13, against Ambient 0.10.0.

```
start 2026-11-20T18:28:16Z
exit 0
end 2026-11-20T18:28:57Z
```

## Command

```
agy -p "<prompt>" --print-timeout 150s
```

## Prompt

> Run `ls` in the current directory, then reply in one sentence saying which coding agent you are and which files you saw. Do not change anything.

## Reply (stdout)

```
I am Antigravity, and running `ls` in the current directory showed [README.md](file://<scratch>/ambient-live-check/README.md) and [hello.txt](file://<scratch>/ambient-live-check/hello.txt).
```

## What Ambient showed

`ambient status --json`, polled every half second while the agent ran (changes only):

```
antigravity:065905c5-59c4-4c10-a9db-0fdada62ee18  {"idle": {}}
antigravity:065905c5-59c4-4c10-a9db-0fdada62ee18  {"thinking": {}}
antigravity:065905c5-59c4-4c10-a9db-0fdada62ee18  {"done": {}}
```

Hook log (`AMBIENT_DEBUG=1`, `~/.ambient/logs/hook.log`), every line for this agent in the test window, failed attempts included:

```
2026-11-20T18:28:24Z sent antigravity sessionStarted
2026-11-20T18:28:24Z sent antigravity promptSubmitted
2026-11-20T18:28:31Z sent antigravity toolStarted(name: "run_command", detail: Optional("ls"))
2026-11-20T18:28:31Z sent antigravity toolFinished(name: "run_command", failed: false)
2026-11-20T18:28:31Z ignored antigravity payload (872 bytes)
2026-11-20T18:28:56Z sent antigravity turnCompleted(summary: nil)
```
