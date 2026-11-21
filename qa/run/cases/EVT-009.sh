#!/bin/zsh
# EVT-009 · Codex reports working, needs-you and done like Claude Code.
# needs-app: yes
# checks: part
# Left to a person: the rows in Codex green (#10A37F).
# Replays a Codex turn (Claude-compatible hook names): apply_patch over three files asked about, then exec_command `make test`.
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

id=01a14bf7-596a-7523-a9db-e5fe30f2e5c8
S='{"session_id":"'$id'","transcript_path":"'$HOME'/.codex/sessions/2026/11/21/rollout-2026-11-21T03-54-23-'$id'.jsonl","cwd":"'$QA_ROOT'/studio","model":"gpt-6.1-sol","permission_mode":"default"'
T=$S',"turn_id":"01a14bfc-32bd-7531-bd03-7cb378539d76"'
patch='*** Begin Patch\n*** Update File: Sources/a.swift\n@@\n-a\n+b\n*** Update File: Sources/b.swift\n@@\n-a\n+b\n*** Add File: Tests/c.swift\n+test\n*** End Patch'

hook codex "$S"',"hook_event_name":"SessionStart","source":"startup"}'
hook codex "$T"',"hook_event_name":"UserPromptSubmit","prompt":"fix it and run the tests"}'
expect_status codex studio "Thinking"
hook codex "$T"',"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"input":"'$patch'"}}'
expect_status codex studio "Patch · a.swift +2 more"
hook codex "$T"',"hook_event_name":"PermissionRequest","tool_name":"apply_patch","tool_input":{"input":"'$patch'"}}'
expect_status codex studio "Review a change · a.swift +2 more"
hook codex "$T"',"hook_event_name":"PostToolUse","tool_name":"apply_patch","tool_input":{"input":"'$patch'"},"tool_response":"Success"}'
expect_status codex studio "Thinking"
hook codex "$T"',"hook_event_name":"PreToolUse","tool_name":"exec_command","tool_input":{"cmd":"make test","workdir":"'$QA_ROOT'/studio"}}'
expect_status codex studio "Shell · make test"
hook codex "$T"',"hook_event_name":"PostToolUse","tool_name":"exec_command","tool_input":{"cmd":"make test"},"tool_response":"ok"}'
hook codex "$T"',"hook_event_name":"PreToolUse","tool_name":"shell","tool_input":{"command":"make lint"}}'
expect_status codex studio "Shell · make lint"
hook codex "$T"',"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Patched a.swift, b.swift and c.swift; make test passes."}'
expect_status codex studio "Done · Patched a.swift, b.swift and c.swift; make test passes."
