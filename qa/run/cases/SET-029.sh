#!/bin/zsh
# SET-029 · Dry runs show the change and write nothing.
# needs-app: no
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
f="$HOME/.claude/settings.json"
printf '{\n  "model": "opus"\n}\n' > "$f"
cp -p "$f" "$QA_ROOT/original.json"
state() { print -r -- "$(shasum "$f" 2>/dev/null) $(ls -A "$AMBIENT_HOME/backups" 2>/dev/null | tr '\n' ' ') $(cat "$AMBIENT_HOME/agents.json" 2>/dev/null)"; }

before=$(state)
out=$(ambient install claude --dry-run) || fail "install --dry-run exited $?"
assert_eq "$(state)" "$before" "files after install --dry-run"
assert_no_file "$AMBIENT_HOME/agents.json"
assert_eq "$(print -r -- "$out" | head -1)" "• Claude: would update ~/.claude/settings.json" "install dry-run line"
preview=$(print -r -- "$out" | tail -n +2)

ambient install claude >/dev/null || fail "install exited $?"
assert_eq "$preview" "$(<"$f")" "the dry run's preview vs the file a real install writes"

before=$(state)
out=$(ambient uninstall claude --dry-run) || fail "uninstall --dry-run exited $?"
assert_eq "$(state)" "$before" "files after uninstall --dry-run"
assert_eq "$(print -r -- "$out" | head -1)" "✓ Claude: would remove hooks from ~/.claude/settings.json" "uninstall dry-run line"
assert_eq "$(print -r -- "$out" | tail -n +2)" "$(<"$QA_ROOT/original.json")" "uninstall preview"

out=$(ambient install claude --dry-run) || fail "up-to-date install --dry-run exited $?"
assert_eq "$out" "✓ Claude: already up to date ~/.claude/settings.json" "dry run on an up-to-date agent"
note "previews match the real result; nothing written"
