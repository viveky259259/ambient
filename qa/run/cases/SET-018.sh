#!/bin/zsh
# SET-018 · An empty hooks object survives connect then remove.
# needs-app: no
# Known gap: uninstall drops a hooks object it empties.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
f="$HOME/.claude/settings.json"
printf '{\n  "model": "opus",\n  "hooks": {}\n}\n' > "$f"
cp "$f" "$QA_ROOT/before.json"
ambient install claude >/dev/null || fail "install exited $?"
ambient uninstall claude >/dev/null || fail "uninstall exited $?"
d=$(diff "$QA_ROOT/before.json" "$f") || fail "settings.json differs after install then uninstall:
$d"
