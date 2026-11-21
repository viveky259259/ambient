#!/bin/zsh
# SET-025 · A malformed settings file is never overwritten.
# needs-app: no
# checks: part
# Left to a person: the red Config unreadable badge in Settings › Agents with no Connect button.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
f="$HOME/.claude/settings.json"
print -r -- '{ "model": "opus",' > "$f"
cp -p "$f" "$QA_ROOT/before.json"
ambient install claude >"$QA_ROOT/out" 2>"$QA_ROOT/err"; code=$?
assert_eq "$code" 1 "exit code"
err=$(<"$QA_ROOT/err")
[[ $err == "✗ Claude: Couldn't parse $f: "*". It was left untouched." ]] || fail "stderr: [$err]"
assert_not_contains "$(<"$QA_ROOT/out")" "Couldn't parse" "stdout"
cmp -s "$f" "$QA_ROOT/before.json" || fail "settings.json changed"
b=("$AMBIENT_HOME"/backups/*(N))
assert_eq "${#b}" 0 "backups written"
note "$err"
