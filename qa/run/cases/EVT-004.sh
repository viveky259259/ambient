#!/bin/zsh
# EVT-004 · Claude's follow-up notification doesn't replace a more precise prompt.
# needs-app: yes
# checks: part
# Left to a person: one banner and one chime only (the notification doesn't alert a second time).
# Replays Claude Code's PermissionRequest for `rm -rf build`, then its permission_prompt Notification a few seconds later.
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

S='{"session_id":"evt4-run","transcript_path":"'$HOME'/.claude/projects/api/evt4-run.jsonl","cwd":"'$QA_ROOT'/api","permission_mode":"default"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"clean"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
hook claude "$S"',"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
expect_status claude api "Approve a command · rm -rf build"
since=$(ambient status --json | jq -r '.[] | select(.id=="claude:evt4-run") | .activitySince')

sleep 2
hook claude "$S"',"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}'
sleep 1
expect_status claude api "Approve a command · rm -rf build" 0
assert_eq "$(ambient status --json | jq -r '.[] | select(.id=="claude:evt4-run") | .activitySince')" "$since" \
  "the prompt's start time (a new prompt would restart its clock and alert again)"
