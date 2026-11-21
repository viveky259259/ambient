#!/bin/zsh
# SET-019 · Removing Cursor deletes a hooks file that held only a version.
# needs-app: no
# Known gap: uninstall deletes any Cursor file left holding only "version": 1, including the user's own.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent cursor
f="$HOME/.cursor/hooks.json"

# A file Ambient created goes, with a backup.
ambient install cursor >/dev/null || fail "install exited $?"
cp "$f" "$QA_ROOT/created.json"
ambient uninstall cursor >/dev/null || fail "uninstall exited $?"
assert_no_file "$f"
b=("$AMBIENT_HOME"/backups/cursor-hooks-*.json(N))
assert_eq "${#b}" 1 "backups after removing the file Ambient created"
cmp -s "${b[1]}" "$QA_ROOT/created.json" || fail "backup is not the removed file"
rm -f "$AMBIENT_HOME"/backups/*

# The user's own file holding only a version stays.
print -r -- '{"version": 1}' > "$f"
ambient install cursor >/dev/null || fail "install exited $? over the user's file"
ambient uninstall cursor >/dev/null || fail "uninstall exited $? over the user's file"
assert_file "$f"
assert_eq "$(jq -c . "$f")" '{"version":1}' "the user's hooks.json after install then uninstall"
