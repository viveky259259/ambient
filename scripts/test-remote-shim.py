"""Checks what one run of scripts/test-remote-shim.sh left in a home folder. Everything is parsed as strict JSON."""
import json
import os
import re
import sys
import time

home, name = sys.argv[1:3]
problems = []


def expect(condition, what):
    if not condition:
        problems.append(what)


def read(path):
    with open(os.path.join(home, path), encoding="utf-8") as f:
        return f.read()


def strict(line):
    def no_duplicates(pairs):
        keys = [k for k, _ in pairs]
        if len(keys) != len(set(keys)):
            raise ValueError("duplicate key")
        return dict(pairs)

    return json.loads(line, object_pairs_hook=no_duplicates)


expect(read("version").startswith("ambient-remote "), "version")

status = strict(read("status"))
expect(read("status.err") == "", f"status wrote to stderr: {read('status.err')[:200]}")
expect(status["type"] == "status", "status type")
expect(re.fullmatch(r"(SHA256:[A-Za-z0-9+/]{43}|id:[0-9a-f]{32})", status["identity"]), "identity")
expect(re.fullmatch(r"[0-9a-f]{16}", status["epoch"]), "epoch")
expect(status["spoolPerms"] == "ok", "spool perms")
expect(status["level"] == "full", "level")
expect(status["claude"] == "installed" and status["codex"] == "installed", "hooks installed")
for agent, path, count in [("claude", ".claude/settings.json", 14), ("codex", ".codex/hooks.json", 11)]:
    hooks = strict(read(path))["hooks"]
    expect(len(hooks) == count, f"{agent} has {len(hooks)} hook events")
    entries = [e for groups in hooks.values() for g in groups for e in g["hooks"]]
    expect(all(f'ambient-remote" emit {agent}' in e["command"] for e in entries), f"{agent} hook command")

lines = read("events").splitlines()
events = []
for line in lines:
    if line == "this line is not json":
        continue
    try:
        events.append(strict(line))
    except ValueError as error:
        problems.append(f"invalid spool line ({error}): {line[:120]}")

seqs = [e["seq"] for e in events]
expect(seqs == list(range(1, len(seqs) + 1)), f"seqs aren't contiguous: {len(seqs) - len(set(seqs))} repeat in {len(seqs)}, last {seqs[-1]}")
expect(len(set(e["id"] for e in events)) == len(events), "event ids repeat")
for e in events:
    expect(re.fullmatch(r"[0-9a-f]{32}", e["id"]), f"bad id {e['id']}")
    expect(isinstance(e["ts"], int) and abs(e["ts"] - time.time()) < 600, f"bad time {e['ts']}")
    expect(e["session"] != "../../etc/passwd" and e["session"] != "nested", f"bad session {e['session']}")

tool, prompt, *_ = events
expect(tool["kind"] == "toolStarted" and tool["tool"] == "Bash" and tool["project"] == "api", f"tool event {tool}")
expect(tool["session"] == "s-1", "nested fields must not win")
expect(prompt["kind"] == "needsInput" and prompt["reason"] == "permission", f"prompt event {prompt}")
expect(prompt["project"] == "my proj", f"project {prompt}")
expect('Allow "curl"? café' in prompt["message"], f"message {prompt['message']}")
done = next(e for e in events if e["kind"] == "turnCompleted")
expect(0 < len(done["message"]) <= 160, "a long message is cut to its cap on the machine")
expect(done["message"].endswith("…"), "a cut says so")
expect("�" not in done["message"], "a cut never lands inside a character")
expect(any(e["kind"] == "toolFinished" and e["tool"] == "Read" for e in events), "a huge payload still parses")
# By kind: on Linux the test's own subshell counts as the agent, so `follow` adds an agentExited for this session.
burst = sum(e["session"] == "s-2" and e["kind"] == "toolStarted" for e in events)
expect(burst == 200, f"every parallel emit arrived: {burst} of 200")
expect(read("held").strip() == "0", "a live holder's lock was taken over")
expect(sum(e["session"] == "s-4" for e in events) == 1, "an emit waits out a live holder")
expect(sum(e["session"] == "s-5" for e in events) == 1, "a dead holder's lock is taken over")
expect(any(e["kind"] == "sessionEnded" for e in events), "session end")
expect(any(e["kind"] == "agentExited" and e["session"] == "ghost-1" for e in events), "agent exit reported")
expect(not any(e["session"] == "alive-1" for e in events), "a running agent was reported gone")

stream = read("follow").splitlines()
expect(strict(stream[0])["type"] == "hello", "follow starts with hello")
expect(isinstance(strict(stream[0])["ts"], int), "hello has a time")
expect(sum(line == "this line is not json" for line in stream) == 1, "a malformed line is forwarded once")
seen = [strict(line) for line in stream[1:] if line.startswith("{")]
heard = [e["seq"] for e in seen if "type" not in e]
expect(heard == sorted(heard) and heard[0] == 3, f"follow --since 2 sent {heard[:5]}")
expect(any(e.get("type") == "heartbeat" for e in seen), "heartbeats")
expect(read("follow.err") == "", f"follow wrote to stderr: {read('follow.err')[:200]}")

expect(int(read("spool-bytes").split()[0]) <= 2048 + 200, f"spool over its cap: {read('spool-bytes')}")

# By kind again: `follow` can add an agentExited, as above. Landing before awk starts, a rotation shows the same file
# twice, because `follow` already holds it: that repeat is the proof it does, and the hub drops it by seq.
for moment, want in [("before", [3, 4, 5, 3, 4, 5, 6]), ("between", [3, 4, 5, 6]), ("quiet", [3, 4, 5])]:
    raced = [strict(line) for line in read(f"raced-{moment}").splitlines()]
    heard = [e["seq"] for e in raced if e.get("kind") == "toolStarted"]
    expect(heard == want, f"a rotation {moment} the two files: follow sent {heard}, not {want}")

for problem in problems:
    print(f"  {name}: {problem}")
sys.exit(1 if problems else 0)
