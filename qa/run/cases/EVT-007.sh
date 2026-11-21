#!/bin/zsh
# EVT-007 · Compaction shows, then returns to what it interrupted.
# needs-app: yes
# checks: part
# Left to a person: the collapsed island reading "Compacting".
# Replays Claude Code's PreCompact with PostCompact, or with SessionStart source "compact", after a finished turn and mid-turn.
source "$QA_REPO/qa/run/lib.sh"

status_of() { # agent title: the status text of that row of `ambient status`
  local want="  ● ${(r:11:)1} ${(r:28:)2} " line rest
  for line in "${(@f)$(ambient status)}"; do
    [[ $line == "$want"* ]] || continue
    rest=${line:${#want}}
    print -r -- "${rest%  *}"
    return 0
  done
  return 1
}
expect_status() { # agent title expected [seconds]
  local got end=$(( EPOCHREALTIME + ${4:-3} ))
  while :; do
    got=$(status_of "$1" "$2")
    [[ $got == "$3" ]] && { note "$2 · $got"; return 0; }
    (( EPOCHREALTIME > end )) && fail "$1 $2: expected [$3], got [${got:-no row}]"
    sleep 0.1
  done
}
session() { print -r -- '{"session_id":"'$1'","transcript_path":"'$HOME'/.claude/projects/p/'$1'.jsonl","cwd":"'$QA_ROOT'/'$2'","permission_mode":"default"'; }

# A manual /compact after a finished turn, ending with SessionStart source "compact".
A=$(session evt7-a manual)
hook claude "$A"',"hook_event_name":"UserPromptSubmit","prompt":"x"}'
hook claude "$A"',"hook_event_name":"Stop","last_assistant_message":"Refactor finished"}'
expect_status claude manual "Done · Refactor finished"
hook claude "$A"',"hook_event_name":"PreCompact","trigger":"manual","custom_instructions":""}'
expect_status claude manual "Compacting context"
assert_eq "$(ambient status | head -1)" "Ambient · 1 session · working" "status header while compacting (counts as working)"
hook claude "$A"',"hook_event_name":"SessionStart","source":"compact"}'
expect_status claude manual "Done · Refactor finished"

# The same, ending with PostCompact.
B=$(session evt7-b manual2)
hook claude "$B"',"hook_event_name":"UserPromptSubmit","prompt":"x"}'
hook claude "$B"',"hook_event_name":"Stop","last_assistant_message":"Docs updated"}'
hook claude "$B"',"hook_event_name":"PreCompact","trigger":"manual","custom_instructions":""}'
expect_status claude manual2 "Compacting context"
hook claude "$B"',"hook_event_name":"PostCompact","trigger":"manual"}'
expect_status claude manual2 "Done · Docs updated"

# An automatic compact in the middle of a turn, ending with PostCompact, then with SessionStart source "compact".
C=$(session evt7-c auto)
hook claude "$C"',"hook_event_name":"UserPromptSubmit","prompt":"x"}'
hook claude "$C"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"swift test"}}'
hook claude "$C"',"hook_event_name":"PreCompact","trigger":"auto","custom_instructions":""}'
expect_status claude auto "Compacting context"
hook claude "$C"',"hook_event_name":"PostCompact","trigger":"auto"}'
expect_status claude auto "Thinking"

D=$(session evt7-d auto2)
hook claude "$D"',"hook_event_name":"UserPromptSubmit","prompt":"x"}'
hook claude "$D"',"hook_event_name":"PreCompact","trigger":"auto","custom_instructions":""}'
expect_status claude auto2 "Compacting context"
hook claude "$D"',"hook_event_name":"SessionStart","source":"compact"}'
expect_status claude auto2 "Thinking"
