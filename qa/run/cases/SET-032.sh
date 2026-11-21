#!/bin/zsh
# SET-032 · ambient doctor reports a healthy setup.
# needs-app: yes
# The QA app is build/AmbientQA.app, so the hook command points into it rather than /Applications/Ambient.app.
source "$QA_REPO/qa/run/lib.sh"

fake_agent claude
fake_agent codex
fake_agent cursor   # installed, never connected
wait_for 5 test -L "$AMBIENT_HOME/bin/ambient"
ambient install claude codex >/dev/null || fail "install exited $?"
out=$(ambient doctor 2>&1); code=$?
lines=("${(@f)out}")
assert_eq "${lines[1]}" "Ambient doctor" "first line"
[[ ${lines[2]} == "✓ App is running ("*")" ]] || fail "second line: [${lines[2]}]"
target=$(readlink "$AMBIENT_HOME/bin/ambient")
assert_eq "$target" "${QA_APP:A}/Contents/Helpers/ambient" "hook command target"
assert_contains "$out" "✓ Hook command: $AMBIENT_HOME/bin/ambient → $target" "hook command line"
assert_contains "$out" "✓ Claude: hooks installed" "claude"
assert_contains "$out" "✓ Codex: hooks installed
  Codex runs new hooks only after you approve them with /hooks." "codex"
assert_contains "$out" '! Cursor: hooks not installed — run `ambient install cursor`' "cursor, installed but never connected"
for name in Gemini Antigravity Copilot OpenCode; do assert_contains "$out" "– $name: not found" "$name"; done
assert_eq "${lines[-1]}" "Everything looks good." "last line"
assert_eq "$code" 0 "exit code"
note "${lines[2]}"
