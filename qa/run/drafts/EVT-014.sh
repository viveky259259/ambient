#!/bin/zsh
# EVT-014 · Antigravity's required decision defers to its own permission rules.
# needs-app: no
# checks: part
# Left to a person: agy still showing its own confirmation for a command its rules say to confirm.
# Runs the hook exactly as the case does, with no app (the reply doesn't depend on it).
source "$QA_REPO/qa/run/lib.sh"

reply() { # event: stdout with a '|' after it, then the exit code
  local out code
  out=$(print -r -- '{}' | ambient hook antigravity "$1"; code=$?; print -rn -- "|$code")
  print -r -- "$out"
}
for event in PreToolUse Stop; do
  assert_eq "$(reply $event)" $'{"decision":"allow"}\n|0' "reply to $event"
done
for event in PostToolUse PreInvocation SessionStart; do
  assert_eq "$(reply $event)" $'{}\n|0' "reply to $event"
done
note 'PreToolUse and Stop: {"decision":"allow"}; others: {}; exit 0'
