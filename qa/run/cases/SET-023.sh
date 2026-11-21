#!/bin/zsh
# SET-023 · Reconnecting is a no-op that writes nothing.
# needs-app: no
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
f="$HOME/.claude/settings.json"
printf '{\n  "model": "opus"\n}\n' > "$f"
ambient install claude >/dev/null || fail "first install exited $?"
mtime=$(stat -f %Fm "$f")
count=$(ls "$AMBIENT_HOME/backups" | wc -l | tr -d ' ')
sleep 1.1
out=$(ambient install claude) || fail "second install exited $?"
assert_eq "$(print -r -- "$out" | head -1)" "✓ Claude: already set up in ~/.claude/settings.json" "reinstall line"
assert_not_contains "$out" "backup" "reinstall output"
assert_eq "$(stat -f %Fm "$f")" "$mtime" "settings.json modification time"
assert_eq "$(ls "$AMBIENT_HOME/backups" | wc -l | tr -d ' ')" "$count" "backup count"
note "no write, no backup"
