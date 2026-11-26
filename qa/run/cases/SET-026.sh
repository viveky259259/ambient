#!/bin/zsh
# SET-026 · Valid JSON of the wrong shape is refused with a reason.
# needs-app: no
# checks: part
# The CLI shows the same InstallerError text the Agents row shows. Left to a person: the red message under the
# name in Settings › Agents and the row staying Not connected.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
f="$HOME/.claude/settings.json"
try() { # contents reason
  print -r -- "$1" > "$f"
  cp "$f" "$QA_ROOT/before.json"
  local err; err=$(ambient install claude 2>&1 >/dev/null); local code=$?
  assert_eq "$code" 1 "exit code for $1"
  assert_eq "$err" "✗ Claude: $f has an unexpected shape ($2). It was left untouched." "message for $1"
  cmp -s "$f" "$QA_ROOT/before.json" || fail "file changed for $1"
}
try '[]' "the top level isn't an object"
try '{"hooks": []}' '"hooks" isn'"'"'t an object'
try '{"hooks": {"Stop": "x"}}' "hooks.Stop isn't a list"
assert_eq "$(jq '.connected | length' "$AMBIENT_HOME/agents.json" 2>/dev/null || echo 0)" 0 "agents recorded as connected"

for blank in '' '   ' $'\n\n'; do
  printf '%s' "$blank" > "$f"
  ambient install claude >/dev/null 2>&1 || fail "install into a blank file [${(q)blank}] exited $?"
  assert_eq "$(jq '.hooks | length' "$f")" 14 "events after connecting a blank file [${(q)blank}]"
done
note "three shapes refused with the reason; blank files connect"
