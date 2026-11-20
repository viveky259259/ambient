#!/bin/zsh
# SET-027 · ambient install with no arguments connects what it finds.
# needs-app: no
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
fake_agent codex
out=$(ambient install 2>&1); code=$?
assert_eq "$code" 0 "exit code"
want="✓ Claude: hooks installed in ~/.claude/settings.json
✓ Codex: hooks installed in ~/.codex/hooks.json
  Codex asks you to trust new hooks: run /hooks in Codex once and approve Ambient's.
– Gemini: not found, skipped
– Antigravity: not found, skipped
– Cursor: not found, skipped
– Copilot: not found, skipped
– OpenCode: not found, skipped
  Open Ambient.app to see sessions light up."
assert_eq "$out" "$want" "install output"
link="$AMBIENT_HOME/bin/ambient"
[[ -L $link ]] || fail "$link is not a symlink"
assert_eq "$(readlink "$link")" "${QA_APP:A}/Contents/Helpers/ambient" "link target"
assert_no_file "$HOME/.gemini"
note "two agents connected, five skipped, link to the bundled CLI"
