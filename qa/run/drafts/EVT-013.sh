#!/bin/zsh
# EVT-013 · Antigravity reports prompts, tools and finished or failed turns.
# needs-app: yes
# checks: part
# Left to a person: the row in purple (#A371F7).
# Replays agy's hooks (`ambient hook antigravity <Event>`, camelCase payloads as in AntigravityAdapterTests.realAgyPayloads).
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
moods=()
agy() { # event json
  print -r -- "$2" | ambient hook antigravity "$1" >/dev/null
  sleep 0.2
  moods+=("$(ambient status | head -1)")
}

W='"workspacePaths":["'$QA_ROOT'/web","'$QA_ROOT'/lib"],"modelName":"gemini-3.8-flash-medium","artifactDirectoryPath":"'$QA_ROOT'/b"'
C='{"conversationId":"63d70cb9-agy",'$W

agy SessionStart "$C}"
agy PreInvocation "$C"',"invocationNum":0,"initialNumSteps":0}'
expect_status antigravity web "Thinking"
json=$(ambient status --json | jq -c '.[] | select(.agent=="antigravity") | {sessionId, cwd}')
assert_eq "$json" '{"sessionId":"63d70cb9-agy","cwd":"'$QA_ROOT'/web"}' "session named after the conversation, project the first workspace"

agy PreToolUse "$C"',"stepIdx":2,"toolCall":{"name":"run_command","args":{"CommandLine":"npm test","Cwd":"'$QA_ROOT'/web","toolAction":"Running tests","toolSummary":"Run tests"}}}'
expect_status antigravity web "Shell · npm test"
agy PostToolUse "$C"',"stepIdx":2,"toolCall":{"name":"run_command","args":{}},"error":""}'
expect_status antigravity web "Thinking"
# A later model call in the same turn is not a new prompt.
agy PreToolUse "$C"',"stepIdx":3,"toolCall":{"name":"replace_file_content","args":{"TargetFile":"'$QA_ROOT'/web/src/app.ts","toolAction":"Editing app.ts"}}}'
expect_status antigravity web "Edit · app.ts"
agy PreInvocation "$C"',"invocationNum":1,"initialNumSteps":4}'
sleep 0.3
expect_status antigravity web "Edit · app.ts" 0
turn=$(ambient status --json | jq -r '.[] | select(.agent=="antigravity") | .turnStartedAt')
agy PostToolUse "$C"',"stepIdx":3,"toolCall":{"name":"replace_file_content","args":{}},"error":""}'
agy Stop "$C"',"error":"","executionNum":0,"fullyIdle":true,"terminationReason":"NO_TOOL_CALL"}'
expect_status antigravity web "Done"
assert_eq "$(ambient status --json | jq -r '.[] | select(.agent=="antigravity") | .turnStartedAt')" "$turn" \
  "turn start (only invocationNum 0 starts a turn)"

agy PreInvocation "$C"',"invocationNum":0,"initialNumSteps":5}'
agy Stop "$C"',"executionNum":1,"fullyIdle":true,"terminationReason":"error","error":"Quota exceeded"}'
expect_status antigravity web "Failed · Quota exceeded"

agy PreInvocation "$C"',"invocationNum":0,"initialNumSteps":7}'
agy Stop "$C"',"error":"","executionNum":2,"fullyIdle":true,"terminationReason":"MAX_STEPS_EXCEEDED"}'
expect_status antigravity web "Failed · Reached its step limit"

for m in $moods; do assert_not_contains "$m" "needs you" "status header during the Antigravity session"; done
note "never needs you (${#moods} headers read)"
