#!/bin/zsh
# EVT-010 · Codex app's hidden suggestion threads never show as sessions.
# needs-app: yes
# timeout: 60
# Replays the Codex desktop app's hooks from a stand-in process whose arguments say `app-server` (as `codex app-server`
# does), and a `codex exec --ephemeral` run from one whose arguments say `exec --ephemeral`. Payloads as Codex Desktop
# 26.1013 sent them (CodexAdapterTests). Each stand-in stays alive like the agent, and is stopped by its pid.
source "$QA_REPO/qa/run/lib.sh"

typeset -a agents
trap 'for p in $agents; do kill $p 2>/dev/null; done' EXIT
# Runs `ambient hook codex` for each payload line of a file, as a child of a process started with ARGS, then stays alive.
codex_process() { # payload-file args...
  local file=$1; shift
  /usr/bin/python3 -I -c '
import subprocess, sys, time
ambient, file = sys.argv[1], sys.argv[2]
for line in open(file):
    if line.strip():
        subprocess.run([ambient, "hook", "codex"], input=line.encode())
open(file + ".sent", "w").close()
time.sleep(50)
' "$QA_APP/Contents/Helpers/ambient" "$file" "$@" &
  agents+=$!
  wait_for 10 test -e "$file.sent"
}
codex_rows() { ambient status --json | jq -r '[.[] | select(.agent=="codex") | .sessionId] | sort | join(" ")'; }

studio=$QA_ROOT/studio
saved=01a14bf7-596a-7523-a9db-e5fe30f2e5c8
hidden=01a14c04-a2b1-77e3-bfd7-3c12bb48e9c9
gone=01a14be7-7fce-77a1-aea0-1b954fa0a392
fork=01a14c10-0000-7000-8000-000000000001
eph=01a14c20-0000-7000-8000-000000000002
rollout() { print -r -- "$HOME/.codex/sessions/2026/11/21/rollout-2026-11-21T03-54-23-$1.jsonl"; }

# The app: a turn in a saved thread ends; the app forks an unsaved thread to suggest the next prompt; a hidden thread
# Ambient never saw ends.
cat > $QA_ROOT/app.jsonl <<EOF
{"session_id":"$saved","turn_id":"01a14bfc-32bd-7531-bd03-7cb378539d76","transcript_path":"$(rollout $saved)","cwd":"$studio","hook_event_name":"UserPromptSubmit","model":"gpt-6.1-sol","permission_mode":"default","prompt":"bench it"}
{"session_id":"$saved","turn_id":"01a14bfc-32bd-7531-bd03-7cb378539d76","transcript_path":"$(rollout $saved)","cwd":"$studio","hook_event_name":"Stop","model":"gpt-6.1-sol","permission_mode":"default","stop_hook_active":false,"last_assistant_message":"The benchmark is downloading."}
{"session_id":"$hidden","transcript_path":null,"cwd":"$studio","hook_event_name":"SessionStart","model":"gpt-6.1-sol","permission_mode":"bypassPermissions","source":"fork"}
{"session_id":"$hidden","turn_id":"01a14c04-a2c6-7633-a390-6b536c980c8b","transcript_path":null,"cwd":"$studio","hook_event_name":"UserPromptSubmit","model":"gpt-6.1-sol","permission_mode":"bypassPermissions","prompt":"suggest"}
{"session_id":"$hidden","turn_id":"01a14c04-a2c6-7633-a390-6b536c980c8b","transcript_path":null,"cwd":"$studio","hook_event_name":"Stop","model":"gpt-6.1-sol","permission_mode":"bypassPermissions","stop_hook_active":false,"last_assistant_message":"{\"suggestion\":\"Run the benchmark again\"}"}
{"session_id":"$gone","transcript_path":null,"cwd":"$studio","hook_event_name":"SessionEnd","reason":"other"}
EOF
codex_process $QA_ROOT/app.jsonl app-server
sleep 0.5
assert_eq "$(codex_rows)" "$saved" "Codex rows after a turn and its suggestion thread (only the saved thread)"
note "suggestion thread: no row; its end: no row"

# The hidden thread ends later: still nothing.
cat > $QA_ROOT/app2.jsonl <<EOF
{"session_id":"$hidden","transcript_path":null,"cwd":"$studio","hook_event_name":"SessionEnd","reason":"other"}
EOF
codex_process $QA_ROOT/app2.jsonl app-server
sleep 0.5
assert_eq "$(codex_rows)" "$saved" "Codex rows after the suggestion thread ended"

# A fork someone makes in the app has a transcript, so it shows.
cat > $QA_ROOT/fork.jsonl <<EOF
{"session_id":"$fork","transcript_path":"$(rollout $fork)","cwd":"$studio","hook_event_name":"SessionStart","model":"gpt-6.1-sol","permission_mode":"default","source":"fork"}
{"session_id":"$fork","turn_id":"t1","transcript_path":"$(rollout $fork)","cwd":"$studio","hook_event_name":"UserPromptSubmit","model":"gpt-6.1-sol","permission_mode":"default","prompt":"try another way"}
EOF
codex_process $QA_ROOT/fork.jsonl app-server

# `codex exec --ephemeral` saves nothing either, but doesn't run under the app server.
cat > $QA_ROOT/exec.jsonl <<EOF
{"session_id":"$eph","transcript_path":null,"cwd":"$studio","hook_event_name":"SessionStart","model":"gpt-6.1-sol","permission_mode":"bypassPermissions","source":"startup"}
{"session_id":"$eph","turn_id":"t","transcript_path":null,"cwd":"$studio","hook_event_name":"UserPromptSubmit","model":"gpt-6.1-sol","permission_mode":"bypassPermissions","prompt":"echo hi"}
EOF
codex_process $QA_ROOT/exec.jsonl exec --ephemeral "echo hi"
sleep 0.5
assert_eq "$(codex_rows)" "${(j: :)${(o)=:-$saved $fork $eph}}" "Codex rows with a fork and an ephemeral exec run (each its own session)"
note "fork and exec --ephemeral each show"
