# Codex live check

codex-cli 0.164.0, against Ambient 0.10.0.

```
start 2026-11-20T18:29:46Z
exit 0
end 2026-11-20T18:29:58Z
model gpt-5.6-terra
```

## Command

```
codex exec -m gpt-5.6-terra "<prompt>"
```

## Prompt

> Run `ls` in the current directory, then reply in one sentence saying which coding agent you are and which files you saw. Do not change anything.

## Reply (stdout)

```
I’m Codex, and I saw `README.md` and `hello.txt`.
```

## The rest of the chat (stderr)

```
Reading additional input from stdin...
OpenAI Codex v0.164.0
--------
workdir: <scratch>/ambient-live-check
model: gpt-5.6-terra
provider: openai
approval: never
sandbox: read-only
reasoning effort: low
reasoning summaries: none
session id: 01a1fa38-c508-7c13-9446-7a0d15fe6ee7
--------
user
Run `ls` in the current directory, then reply in one sentence saying which coding agent you are and which files you saw. Do not change anything.
warning: clamping SessionEnd hook timeout to 3s in ~/.codex/hooks.json
hook: SessionStart
hook: SessionStart Completed
codex
I’ll inspect the current directory without making any changes.
exec
/bin/zsh -lc ls in <scratch>/ambient-live-check
 succeeded in 0ms:
README.md
hello.txt

codex
I’m Codex, and I saw `README.md` and `hello.txt`.
hook: Stop
hook: Stop Completed
tokens used
14,012
```

## What Ambient showed

`ambient status --json`, polled every half second while the agent ran (changes only):

```
codex:01a1fa38-c508-7c13-9446-7a0d15fe6ee7  {"thinking": {}}
```

Hook log (`AMBIENT_DEBUG=1`, `~/.ambient/logs/hook.log`), every line for this agent in the test window, failed attempts included:

```
2026-11-20T18:28:18Z sent codex sessionStarted
2026-11-20T18:28:18Z sent codex promptSubmitted
2026-11-20T18:28:19Z sent codex sessionEnded
2026-11-20T18:29:14Z sent codex sessionStarted
2026-11-20T18:29:14Z sent codex promptSubmitted
2026-11-20T18:29:15Z sent codex sessionEnded
2026-11-20T18:29:17Z sent codex sessionStarted
2026-11-20T18:29:17Z sent codex promptSubmitted
2026-11-20T18:29:18Z sent codex sessionEnded
2026-11-20T18:29:20Z sent codex sessionStarted
2026-11-20T18:29:20Z sent codex promptSubmitted
2026-11-20T18:29:20Z sent codex sessionEnded
2026-11-20T18:29:23Z sent codex sessionStarted
2026-11-20T18:29:23Z sent codex promptSubmitted
2026-11-20T18:29:23Z sent codex sessionEnded
2026-11-20T18:29:25Z sent codex sessionStarted
2026-11-20T18:29:26Z sent codex promptSubmitted
2026-11-20T18:29:26Z sent codex sessionEnded
2026-11-20T18:29:28Z sent codex sessionStarted
2026-11-20T18:29:28Z sent codex promptSubmitted
2026-11-20T18:29:29Z sent codex sessionEnded
2026-11-20T18:29:31Z sent codex sessionStarted
2026-11-20T18:29:31Z sent codex promptSubmitted
2026-11-20T18:29:31Z sent codex sessionEnded
2026-11-20T18:29:34Z sent codex sessionStarted
2026-11-20T18:29:34Z sent codex promptSubmitted
2026-11-20T18:29:34Z sent codex sessionEnded
2026-11-20T18:29:36Z sent codex sessionStarted
2026-11-20T18:29:36Z sent codex promptSubmitted
2026-11-20T18:29:37Z sent codex sessionEnded
2026-11-20T18:29:48Z sent codex sessionStarted
2026-11-20T18:29:48Z sent codex promptSubmitted
2026-11-20T18:29:55Z sent codex toolStarted(name: "Bash", detail: Optional("ls"))
2026-11-20T18:29:55Z sent codex toolFinished(name: "Bash", failed: false)
2026-11-20T18:29:56Z sent codex turnCompleted(summary: Optional("I’m Codex, and I saw `README.md` and `hello.txt`."))
2026-11-20T18:29:56Z sent codex sessionEnded
```

## The first attempt, which failed

```
start 2026-11-20T18:28:16Z
exit 1
end 2026-11-20T18:28:19Z
```

```
Reading additional input from stdin...
OpenAI Codex v0.164.0
--------
workdir: <scratch>/ambient-live-check
model: gpt-6.1-terra
provider: openai
approval: never
sandbox: read-only
reasoning effort: low
reasoning summaries: none
session id: 01a1fa37-6592-7fb2-bf5d-052177964709
--------
user
Run `ls` in the current directory, then reply in one sentence saying which coding agent you are and which files you saw. Do not change anything.
warning: clamping SessionEnd hook timeout to 3s in ~/.codex/hooks.json
warning: Model metadata for `gpt-6.1-terra` not found. Defaulting to fallback metadata; this can degrade performance and cause issues.
hook: SessionStart
hook: SessionStart Completed
ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The 'gpt-6.1-terra' model is not supported when using Codex with a ChatGPT account.","code":"model_not_found"}}
ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The 'gpt-6.1-terra' model is not supported when using Codex with a ChatGPT account.","code":"model_not_found"}}
```
