#!/bin/zsh
# PRM-025 · Turning it off puts the hook back in the background.
# needs-app: no
# checks: part
# Left to a person: flipping the toggle off in Settings (and the "enabled": false it writes), and that no card appears.
# Answering on, then off; `ambient install` runs the installer the toggle runs, and the permission hook is fed a prompt.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

fake_agent claude; fake_agent codex
prm_settings true 20
ambient install claude codex >/dev/null || fail "install with answering on failed"
assert_json "$HOME/.claude/settings.json" '.hooks.PermissionRequest[0].hooks[0].timeout' 70

prm_settings false 20
ambient install claude codex >/dev/null || fail "install with answering off failed"
for f in .claude/settings.json .codex/hooks.json; do
  e='.hooks.PermissionRequest[0].hooks[0]'
  assert_json "$HOME/$f" '.hooks.PermissionRequest | length' 1
  assert_json "$HOME/$f" "$e.async" true
  assert_json "$HOME/$f" "$e.timeout" 5
  assert_not_contains "$(<"$HOME/$f")" "--answer" "$f after turning off"
done

# The hook Claude Code then runs (and the old --answer one, if still in place) hands the prompt straight back.
fake_island allow "$QA_ROOT/island.log"
P='{"session_id":"prm-025","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
cmd=$(jq -r '.hooks.PermissionRequest[0].hooks[0].command' "$HOME/.claude/settings.json")
for c in "$cmd" "${cmd/ hook claude / hook claude --answer }"; do
  start=$EPOCHREALTIME
  out=$(print -r -- "$P" | /bin/sh -c "$c")
  ms=$(ms_since $start)
  assert_eq "$out" "" "output of [$c]"
  (( ms < 1000 )) || fail "[$c] held the prompt for $ms ms"
done
sleep 0.2
assert_not_contains "$(<"$QA_ROOT/island.log")" '"permissionRequest"' "a prompt asked the island with answering off"
