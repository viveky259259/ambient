#!/bin/zsh
# PRM-001 · Answering from the notch is off by default.
# needs-app: yes
# checks: part
# Left to a person: Settings › Alerts › Permission prompts (toggle off, 20 seconds greyed out), and the island blooming needs you with no Allow/Deny card.
# A fresh home: no permissions.json. Claude Code is connected with `ambient install`, then its recorded prompt runs
# through the exact command written into its settings.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

assert_no_file "$AMBIENT_HOME/permissions.json"
fake_agent claude
ambient install claude >/dev/null || fail "ambient install claude failed"
f=$HOME/.claude/settings.json
e='.hooks.PermissionRequest[0].hooks[0]'
assert_json "$f" "$e.async" true
assert_json "$f" "$e.timeout" 5
cmd=$(jq -r "$e.command" "$f")
[[ $cmd == *"\" hook claude || true" ]] || fail "PermissionRequest command: [$cmd]"
assert_not_contains "$(<"$f")" "--answer" "settings.json"

P='{"session_id":"prm-001","transcript_path":"/tmp/t.jsonl","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'/api","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
ask_detached "$QA_ROOT/ask" "$P" hook claude --answer
ask_wait "$QA_ROOT/ask" 5
assert_eq "$ASK_RC" 0 "--answer hook exit code"
assert_eq "$(<"$QA_ROOT/ask")" "" "--answer hook output with answering off"
(( ASK_MS < 1000 )) || fail "the --answer hook waited $ASK_MS ms with answering off"

start=$EPOCHREALTIME
out=$(print -r -- "$P" | /bin/sh -c "$cmd")
ms=$(ms_since $start)
assert_eq "$out" "" "installed hook output"
(( ms < 1000 )) || fail "the installed hook held Claude Code for $ms ms"
note "installed hook returned in $ms ms; --answer hook in $ASK_MS ms"

wait_for 5 sess_is prm-001 .activity.waiting.reason command
assert_eq "$(sess prm-001 .activity.waiting.message)" "rm -rf build" "what the session needs"
