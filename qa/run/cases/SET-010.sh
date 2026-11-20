#!/bin/zsh
# SET-010 · Connect Codex shows the /hooks approval step.
# needs-app: no
# checks: part
# Left to a person: the amber /hooks note in Settings › Agents, and that a real Codex sends nothing until its hooks
# are approved with /hooks, then shows on the island. Checked here: the hooks.json Ambient writes.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent codex
f="$HOME/.codex/hooks.json"
out=$(ambient install codex) || fail "ambient install codex exited $?"
assert_contains "$out" "Codex asks you to trust new hooks: run /hooks in Codex once and approve Ambient's." "the CLI's /hooks note"

cmd='[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook codex || true'
events=(SessionStart UserPromptSubmit PreToolUse PostToolUse PermissionRequest PreCompact PostCompact SubagentStart SubagentStop Stop SessionEnd)
assert_eq "$(jq -c '.hooks | keys_unsorted' "$f")" "$(printf '%s\n' $events | jq -R . | jq -sc .)" "Codex events in hooks.json"
for e in $events; do
  if [[ $e == SessionEnd ]]; then want=$(jq -cn --arg c "$cmd" '{type:"command",command:$c,timeout:5}')
  else want=$(jq -cn --arg c "$cmd" '{type:"command",command:$c,async:true,timeout:5}'); fi
  assert_eq "$(jq -c --arg e $e '.hooks[$e]' "$f")" "[{\"hooks\":[$want]}]" "entry under $e"
done
note "11 Codex events; SessionEnd synchronous, the rest async, timeout 5"
