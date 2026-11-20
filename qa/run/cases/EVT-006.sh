#!/bin/zsh
# EVT-006 · A failed Claude Code turn is an error, with its message.
# needs-app: yes
# checks: part
# Left to a person: the row in red (#F85149).
# Sends Claude Code's StopFailure hook as the case does, then with each fallback field.
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

hook claude '{"session_id":"evt6","hook_event_name":"StopFailure","cwd":"'$QA_ROOT'/api","error_message":"API Error: 529 overloaded"}'
expect_status claude api "Failed · API Error: 529 overloaded"
assert_eq "$(ambient status | head -1)" "Ambient · 1 session · failed" "status header"

hook claude '{"session_id":"evt6b","hook_event_name":"StopFailure","cwd":"'$QA_ROOT'/web","error":"Request timed out","error_type":"timeout"}'
expect_status claude web "Failed · Request timed out"
hook claude '{"session_id":"evt6c","hook_event_name":"StopFailure","cwd":"'$QA_ROOT'/cli","error_type":"rate_limit"}'
expect_status claude cli "Failed · rate_limit"
hook claude '{"session_id":"evt6d","hook_event_name":"StopFailure","cwd":"'$QA_ROOT'/docs"}'
expect_status claude docs "Failed"
