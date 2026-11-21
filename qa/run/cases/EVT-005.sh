#!/bin/zsh
# EVT-005 · A finished Claude Code turn is done, with a trimmed summary.
# needs-app: yes
# timeout: 90
# checks: part
# Left to a person: the row turning green (#3FB950); no new alert for the idle reminder.
# Replays a Claude Code turn ending in a long reply, then the idle_prompt Notification Claude sends a minute later.
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
    [[ $got == "$3" ]] && { note "$2 · ${got[1,60]}…"; return 0; }
    (( EPOCHREALTIME > end )) && fail "$1 $2: expected [$3], got [${got:-no row}]"
    sleep 0.1
  done
}

# A reply of about 400 characters over several lines, as Claude ends a turn.
reply='All 42 tests pass.\n\nI changed three files:\n- Sources/Session.swift: the clock now counts from the prompt\n- Sources/Describe.swift: just now for the first ten seconds\n- Tests/DescribeTests.swift: covers both\n\nNothing else changed. The build is clean and the linter reports no warnings. Ready for review whenever you are; tell me if you want the commits squashed before you look.'
words=${(j: :)${=${(g:e:)reply}}}           # what Ambient shows: whitespace runs collapsed to one space
(( ${#words} > 160 )) || { echo "the test reply is too short" >&2; exit 2; }
want="Done · ${words[1,159]}…"

S='{"session_id":"evt5-run","transcript_path":"'$HOME'/.claude/projects/api/evt5-run.jsonl","cwd":"'$QA_ROOT'/api","permission_mode":"default"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"make the clock right"}'
hook claude "$S"',"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"'$reply'"}'
expect_status claude api "$want"
summary=$(ambient status --json | jq -r '.[] | select(.id=="claude:evt5-run") | .activity.done.summary')
assert_eq "${#summary}" 160 "summary length in characters"
assert_eq "$(clock_of claude api)" "just now" "clock right after the turn"

sleep 11
clock=$(clock_of claude api)
[[ $clock == <10-14>s\ ago ]] || fail "clock 11 s after the turn: expected [<n>s ago], got [$clock]"
note "clock: $clock"

hook claude "$S"',"hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input"}'
sleep 1
expect_status claude api "$want" 0
