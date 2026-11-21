#!/bin/zsh
# SET-028 · ambient install for a named agent that isn't installed fails.
# needs-app: no
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

err=$(ambient install gemini 2>&1 >/dev/null); code=$?
assert_eq "$code" 1 "exit code for gemini"
assert_eq "$err" "✗ Gemini: Gemini doesn't appear to be installed (no ~/.gemini)." "message for gemini"
assert_no_file "$HOME/.gemini"
for name in foo custom; do
  err=$(ambient install $name 2>&1 >/dev/null); code=$?
  assert_eq "$code" 64 "exit code for $name"
  assert_eq "$err" "✗ Unknown agent '$name'. Use claude, codex, gemini, antigravity, cursor, copilot, opencode." "message for $name"
done
note "missing agent exits 1, unknown and custom exit 64"
