#!/bin/zsh
# PRM-004 · Turning it on makes only the Claude Code and Codex permission hooks wait.
# needs-app: no
# checks: part
# Left to a person: flipping the toggle in Settings › Alerts (and the permissions.json it writes), Settings › Agents showing Connected.
# The toggle runs PermissionHooks.apply: HookInstaller with the new setting, for agents whose hooks it finds out of
# date. Here the setting is written and `ambient install` runs that installer for every agent.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

for a in claude codex gemini cursor copilot opencode; do fake_agent $a; done
mkdir -p "$HOME/.gemini/antigravity"
files=(.claude/settings.json .codex/hooks.json .gemini/settings.json .cursor/hooks.json .copilot/hooks/ambient.json .config/opencode/plugins/ambient.js .gemini/config/hooks.json)

prm_settings false 20
ambient install >/dev/null || fail "first ambient install failed"
mkdir -p "$QA_ROOT/before"
for f in $files; do cp "$HOME/$f" "$QA_ROOT/before/${f//\//_}"; done
rm -rf "$AMBIENT_HOME/backups"

prm_settings true 20
# What the toggle looks at: only Claude Code and Codex are out of date under the new setting.
doc=$(ambient doctor 2>&1)
assert_contains "$doc" "Claude: hooks are incomplete or outdated" "doctor: Claude Code needs the waiting hook"
assert_contains "$doc" "Codex: hooks are incomplete or outdated" "doctor: Codex needs the waiting hook"
assert_not_contains "$doc" "Gemini CLI: hooks are incomplete" "doctor: Gemini must not change"

ambient install >/dev/null || fail "second ambient install failed"

for agent in claude codex; do
  f=$([[ $agent == claude ]] && print .claude/settings.json || print .codex/hooks.json)
  new=$HOME/$f old=$QA_ROOT/before/${f//\//_}
  # Every other entry is unchanged.
  assert_eq "$(jq -S 'del(.hooks.PermissionRequest)' "$new")" "$(jq -S 'del(.hooks.PermissionRequest)' "$old")" "$f: entries other than PermissionRequest"
  assert_json "$new" '.hooks.PermissionRequest | length' 1
  assert_json "$new" '.hooks.PermissionRequest[0].hooks | length' 1
  e='.hooks.PermissionRequest[0].hooks[0]'
  assert_json "$new" "$e | has(\"async\")" false
  assert_json "$new" "$e.timeout" 70
  assert_json "$new" "$e.type" command
  cmd=$(jq -r "$e.command" "$new")
  [[ $cmd == *"\" hook $agent --answer || true" ]] || fail "$f PermissionRequest command: [$cmd]"
  # SessionEnd is the one entry that never had async; it must still lack --answer.
  assert_eq "$(jq -r '[.hooks | to_entries[] | select(.key != "PermissionRequest") | .value[].hooks[] | select(.command | contains("--answer"))] | length' "$new")" 0 "$f: --answer outside PermissionRequest"
  assert_eq "$(jq -r '[.hooks | to_entries[] | select(.key != "PermissionRequest" and .key != "SessionEnd") | .value[].hooks[] | select(.async != true)] | length' "$new")" 0 "$f: entries that lost async"
  ls "$AMBIENT_HOME/backups" | grep -q "^$agent-" || fail "no backup of $f in backups/"
done

for f in $files[3,-1]; do
  cmp -s "$HOME/$f" "$QA_ROOT/before/${f//\//_}" || fail "$f changed when answering was turned on"
done
ls "$AMBIENT_HOME/backups" | grep -qv '^\(claude\|codex\)-' && fail "backups of other agents' files: $(ls "$AMBIENT_HOME/backups")"

doc=$(ambient doctor 2>&1)
assert_contains "$doc" "Claude: hooks installed" "doctor after: Claude Code connected"
assert_contains "$doc" "Codex: hooks installed" "doctor after: Codex connected"
note "backups: $(ls "$AMBIENT_HOME/backups" | tr '\n' ' ')"
