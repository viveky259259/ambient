#!/bin/zsh
# EVT-029 · A hook never blocks the agent when Ambient isn't running.
# needs-app: no
# Replays a Claude Code and a Codex hook with no app listening, in place of the real agents.
source "$QA_REPO/qa/run/lib.sh"

for agent in claude codex; do
  start=$EPOCHREALTIME
  out=$(print -r -- '{"session_id":"x","hook_event_name":"UserPromptSubmit","cwd":"/tmp"}' | ambient hook $agent)
  code=$?
  ms=$(( (EPOCHREALTIME - start) * 1000 ))
  assert_eq "$code" 0 "$agent hook exit code"
  assert_eq "$out" "" "$agent hook output"
  (( ms < 1000 )) || fail "$agent hook took ${ms%.*} ms with nothing listening (want well under 1000)"
  note "$agent hook returned in ${ms%.*} ms"
done
