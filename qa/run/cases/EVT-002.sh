#!/bin/zsh
# EVT-002 · A Claude Code permission prompt for a command needs you, naming the command.
# needs-app: yes
# checks: part
# Left to a person: the island blooming amber (#F5A524) with the same text; the collapsed island and menu bar saying "Approve command"; Claude Code's own prompt still on screen.
# Replays Claude Code's PermissionRequest hook for `rm -rf build`, with the permission hook off (no --answer).
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
clock_of() { # agent title: the clock of that row
  local want="  ● ${(r:11:)1} ${(r:28:)2} " line
  for line in "${(@f)$(ambient status)}"; do
    [[ $line == "$want"* ]] && { print -r -- "${line##*  }"; return 0; }
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

S='{"session_id":"evt2-run","transcript_path":"'$HOME'/.claude/projects/api/evt2-run.jsonl","cwd":"'$QA_ROOT'/api","permission_mode":"default"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"clean the build"}'
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"Remove build"}}'
sleep 3
out=$(hook claude "$S"',"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build","description":"Remove build"}}')
assert_eq "$out" "" "what the hook printed back to Claude Code (an answer would approve or deny)"

expect_status claude api "Approve a command · rm -rf build"
assert_eq "$(ambient status | head -1)" "Ambient · 1 session · needs you" "status header"
clock=$(clock_of claude api)
[[ $clock == <0-1>s ]] || fail "the clock should count from when the prompt appeared, not the turn (3 s earlier): got [$clock]"
sleep 2
clock=$(clock_of claude api)
[[ $clock == <2-3>s ]] || fail "the clock should keep counting while it waits: got [$clock] 2 s later"
note "clock $clock, 2 s after the prompt"
