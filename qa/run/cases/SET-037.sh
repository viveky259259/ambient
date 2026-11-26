#!/bin/zsh
# SET-037 · An unreadable settings file shows Show File and is never rewritten.
# needs-app: yes
# timeout: 150
# checks: part
# Checked: the running app's hook check meets the unreadable file and leaves it byte-for-byte alone, with no backup.
# Every check rewrites ~/.ambient/agents.json, which is how the script knows one ran.
# Left to a person: the menu item *Can't read Codex's settings — Show File*, the !, Finder revealing the file, and
# the problem clearing once the file is fixed.
source "$QA_REPO/qa/run/lib.sh"

agents_mtime() { stat -f %Fm "$AMBIENT_HOME/agents.json" 2>/dev/null || print none; }
fake_agent codex
f="$HOME/.codex/hooks.json"
ambient install codex >/dev/null || fail "install exited $?"
backups_before=$(ls "$AMBIENT_HOME/backups" 2>/dev/null | wc -l | tr -d ' ')
{ print -n ','; cat "$f" } > "$QA_ROOT/bad.json" && cat "$QA_ROOT/bad.json" > "$f"
jq . "$f" >/dev/null 2>&1 && fail "setup: the file is still valid JSON"
m=$(agents_mtime)
wait_for 90 sh -c "[ \"\$(stat -f %Fm '$AMBIENT_HOME/agents.json')\" != '$m' ]"
sleep 1
cmp -s "$f" "$QA_ROOT/bad.json" || fail "the app rewrote the unreadable hooks.json"
assert_eq "$(ls "$AMBIENT_HOME/backups" 2>/dev/null | wc -l | tr -d ' ')" "$backups_before" "backups after the check"
assert_contains "$(ambient doctor 2>&1)" "✗ Codex: can't read ~/.codex/hooks.json" "doctor on the same file"
note "a hook check ran and left the file alone"
