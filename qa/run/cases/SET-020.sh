#!/bin/zsh
# SET-020 · Every edit keeps a timestamped backup first.
# needs-app: no
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
f="$HOME/.claude/settings.json"
printf '{\n  "model": "opus"\n}\n' > "$f"
cp "$f" "$QA_ROOT/before.json"
out=$(ambient install claude) || fail "install exited $?"
line=$(print -r -- "$out" | head -1)
[[ $line =~ '^✓ Claude: hooks installed in ~/\.claude/settings\.json \(backup: ~/\.ambient/backups/claude-settings-[0-9]{8}-[0-9]{6}-[0-9]{3}\.json\)$' ]] \
  || fail "install line: [$line]"
name=${${line##*backups/}%\)}
cmp -s "$AMBIENT_HOME/backups/$name" "$QA_ROOT/before.json" || fail "backup $name is not the file before the install"

# A config file that didn't exist gets no backup.
fake_agent codex
out=$(ambient install codex) || fail "codex install exited $?"
assert_not_contains "$out" "backup:" "codex install line"
b=("$AMBIENT_HOME"/backups/codex-*(N))
assert_eq "${#b}" 0 "backups of a file that didn't exist"
note "backup $name equals the original"
