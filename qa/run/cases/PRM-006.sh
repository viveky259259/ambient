#!/bin/zsh
# PRM-006 · Changing the wait doesn't change the hook.
# needs-app: no
# checks: part
# Left to a person: changing Wait for an answer in Settings, Codex not asking to approve the hooks again, the card counting down from 10s.
# Settings rewrites a hook only when HookInstaller finds it out of date; here the wait changes and the installer runs.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

fake_agent claude; fake_agent codex
prm_settings true 20
ambient install claude codex >/dev/null || fail "ambient install failed"
c0=$(<"$HOME/.codex/hooks.json")
m0=$(stat -f %m "$HOME/.codex/hooks.json")
l0=$(<"$HOME/.claude/settings.json")
sleep 1.1

for wait in 60 10; do
  prm_settings true $wait
  doc=$(ambient doctor 2>&1)
  assert_contains "$doc" "Codex: hooks installed" "wait $wait: Codex's hook must still count as current"
  assert_contains "$doc" "Claude: hooks installed" "wait $wait: Claude Code's hook must still count as current"
  out=$(ambient install claude codex 2>&1)
  assert_contains "$out" "Codex: already set up" "wait $wait: install output for Codex"
  assert_eq "$(<"$HOME/.codex/hooks.json")" "$c0" "wait $wait: ~/.codex/hooks.json contents"
  assert_eq "$(<"$HOME/.claude/settings.json")" "$l0" "wait $wait: ~/.claude/settings.json contents"
  assert_eq "$(stat -f %m "$HOME/.codex/hooks.json")" "$m0" "wait $wait: ~/.codex/hooks.json modification time"
  assert_json "$HOME/.codex/hooks.json" '.hooks.PermissionRequest[0].hooks[0].timeout' 70
  assert_json "$AMBIENT_HOME/permissions.json" '.wait' $wait
done
