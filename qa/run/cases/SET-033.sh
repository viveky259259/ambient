#!/bin/zsh
# SET-033 · ambient doctor names each problem and exits 1.
# needs-app: no
# Step 4 uses a 100-character AMBIENT_HOME inside this case's folder rather than /tmp.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
ambient install claude >/dev/null || fail "install exited $?"
doctor() { ambient doctor >"$QA_ROOT/out" 2>"$QA_ROOT/err"; code=$?; out=$(<"$QA_ROOT/out"); err=$(<"$QA_ROOT/err"); }

# 1. The app isn't running.
doctor
assert_contains "$err" "✗ App isn't running — open Ambient.app" "step 1 stderr"
assert_eq "$(print -r -- "$out" | tail -1)" "1 problem found." "step 1 last line"
assert_eq "$code" 1 "step 1 exit"

# 2. Ambient's entries deleted by hand.
jq 'del(.hooks)' "$HOME/.claude/settings.json" > "$QA_ROOT/s" && mv "$QA_ROOT/s" "$HOME/.claude/settings.json"
doctor
assert_contains "$err" '✗ Claude: its hooks were removed since you connected it — run `ambient install claude`' "step 2"
assert_contains "$err" '✗ No agent is connected — run `ambient install`' "step 2"
assert_eq "$(print -r -- "$out" | tail -1)" "3 problems found." "step 2 last line"
assert_eq "$code" 1 "step 2 exit"

# 3. Codex's hooks.json isn't JSON.
fake_agent codex
print -r -- '{ "hooks": {}, }' > "$HOME/.codex/hooks.json"
doctor
assert_contains "$err" "✗ Codex: can't read ~/.codex/hooks.json: " "step 3"
assert_eq "$(print -r -- "$out" | tail -1)" "4 problems found." "step 3 last line"
assert_eq "$code" 1 "step 3 exit"

# 4. A socket path too long for macOS.
long="$QA_ROOT/$(printf 'x%.0s' {1..100})"
AMBIENT_HOME=$long ambient doctor >"$QA_ROOT/out" 2>"$QA_ROOT/err"; code=$?; out=$(<"$QA_ROOT/out"); err=$(<"$QA_ROOT/err")
assert_contains "$err" "✗ Socket path is too long for macOS: $long/ambient.sock. Set AMBIENT_HOME to a shorter path." "step 4"
assert_contains "$err" "✗ Hook command missing at $long/bin/ambient — open Ambient.app or run \`ambient install\`" "step 4"
[[ $(print -r -- "$out" | tail -1) == <2->" problems found." ]] || fail "step 4 last line: $(print -r -- "$out" | tail -1)"
assert_eq "$code" 1 "step 4 exit"
note "each problem named; counts 1, 3, 4 and $(print -r -- "$out" | tail -1)"
