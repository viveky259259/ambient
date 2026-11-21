#!/bin/zsh
# EVT-015 · Cursor shows tools as they finish and how the turn ended.
# needs-app: yes
# checks: part
# Left to a person: the label "Cursor" in cyan (#39C5CF) on the island; Cursor's own permission prompts never reaching Ambient (no hook carries them).
# Replays Cursor's after-the-fact hooks (payload shapes from CursorAdapterTests), with a Codex model selected.
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

C='{"conversation_id":"c-evt15","generation_id":"g-1","model":"gpt-5.3-codex","agent":"Codex","cursor_version":"3.1.0","workspace_roots":["'$QA_ROOT'/site","'$QA_ROOT'/other"]'
hook cursor "$C"',"hook_event_name":"sessionStart","session_id":"c-evt15"}'
hook cursor "$C"',"hook_event_name":"beforeSubmitPrompt","prompt":"edit index and build"}'
expect_status cursor site "Thinking"
row=$(ambient status --json | jq -c '.[] | select(.sessionId=="c-evt15") | {id, agent, agentName}')
assert_eq "$row" '{"id":"cursor:c-evt15","agent":"cursor","agentName":null}' "Cursor session: agent and label override"
assert_eq "$(ambient status --json | jq '[.[] | select(.agent=="codex")] | length')" 0 "Codex rows (a Codex model must not relabel Cursor)"

hook cursor "$C"',"hook_event_name":"afterFileEdit","file_path":"'$QA_ROOT'/site/index.html","edits":[{"old_string":"a","new_string":"b"}]}'
expect_status cursor site "Edit · index.html"
hook cursor "$C"',"hook_event_name":"afterShellExecution","command":"npm run build","output":"built","duration":1200}'
expect_status cursor site "npm run build"
hook cursor "$C"',"hook_event_name":"postToolUse","tool_name":"Shell","tool_input":{"command":"npm run lint"}}'
expect_status cursor site "Shell · npm run lint"
hook cursor "$C"',"hook_event_name":"stop","status":"completed","loop_count":0}'
expect_status cursor site "Done"

hook cursor "$C"',"hook_event_name":"beforeSubmitPrompt","prompt":"again"}'
hook cursor "$C"',"hook_event_name":"stop","status":"aborted","loop_count":0}'
expect_status cursor site "Done"
hook cursor "$C"',"hook_event_name":"beforeSubmitPrompt","prompt":"again"}'
hook cursor "$C"',"hook_event_name":"stop","status":"error","loop_count":0}'
expect_status cursor site "Failed"
