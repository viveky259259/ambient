#!/bin/zsh
# SET-014 · Connect Cursor uses only hooks that can't block it.
# needs-app: no
# checks: part
# Left to a person: Cursor's own approval prompt appears and works as before.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent cursor
f="$HOME/.cursor/hooks.json"
cmd='[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook cursor || true'
want=$(jq -cn --arg c "$cmd" '{command:$c,timeout:5}')
events=(sessionStart beforeSubmitPrompt postToolUse postToolUseFailure afterShellExecution afterFileEdit afterMCPExecution preCompact stop sessionEnd)

check_ambient() { # label
  for e in $events; do
    assert_eq "$(jq -c --arg e $e --argjson w "$want" '[.hooks[$e][] | select(. == $w)] | length' "$f")" 1 "Ambient's flat entry under $e ($1)"
  done
  for e in preToolUse beforeShellExecution beforeMCPExecution beforeReadFile; do
    n=$(jq --arg e $e '[.hooks[$e][]? | select(.command | test("bin/ambient\"? hook "))] | length' "$f")
    assert_eq "$n" 0 "Ambient entries under $e ($1)"
  done
  n=$(jq '[.hooks[][] | select(has("hooks"))] | length' "$f")
  assert_eq "$n" 0 "grouped entries ($1)"
}

# A new file.
ambient install cursor >/dev/null || fail "ambient install cursor exited $?"
assert_eq "$(jq -c 'keys_unsorted[0]' "$f")" '"version"' "first key of a new file"
assert_json "$f" '.version' 1
check_ambient "new file"

# An existing file with the user's own entries, including a blocking one of theirs.
cat > "$f" <<'JSON'
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      {
        "command": "./guard.sh"
      }
    ],
    "stop": [
      {
        "command": "say done"
      }
    ]
  }
}
JSON
ambient install cursor >/dev/null || fail "ambient install cursor exited $? on an existing file"
check_ambient "existing file"
assert_eq "$(jq -c '.hooks.beforeShellExecution' "$f")" '[{"command":"./guard.sh"}]' "the user's beforeShellExecution entry"
assert_eq "$(jq -c '.hooks.stop[0]' "$f")" '{"command":"say done"}' "the user's stop entry, first"
note "flat entries, no blocking events, version first, user's entries kept"
