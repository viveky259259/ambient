#!/bin/zsh
# SET-024 · Reinstall replaces stale or old-shape entries without duplicating.
# needs-app: no
# checks: part
# Left to a person: the Agents pane showing Needs update with an Update button (same `partial` state doctor reads).
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
f="$HOME/.claude/settings.json"
cat > "$f" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo mine"
          }
        ]
      }
    ]
  }
}
JSON
ambient install claude >/dev/null || fail "install exited $?"
ambient doctor >/dev/null 2>&1
healthy=$(ambient doctor 2>&1 | tail -1)   # the app isn't running here: one problem already

# One entry moved to an old place, another without "async".
jq '(.hooks.PostToolUse[-1].hooks[0].command) = "/old/place/.ambient/bin/ambient hook claude"
    | (.hooks.Stop[-1].hooks[0]) |= del(.async)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
out=$(ambient doctor 2>&1); code=$?
assert_contains "$out" '! Claude: hooks are incomplete or outdated — run `ambient install claude`' "doctor on stale hooks"
assert_eq "$code" 1 "doctor exit code"
assert_eq "$healthy" "1 problem found." "doctor before the edit (app not running)"
assert_eq "$(print -r -- "$out" | tail -1)" "2 problems found." "doctor counts the stale hooks as a problem"

ambient install claude >/dev/null || fail "reinstall exited $?"
cmd='[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook claude || true'
for e in $(jq -r '.hooks | keys[]' "$f"); do
  if [[ $e == SessionEnd ]]; then want=$(jq -cn --arg c "$cmd" '{type:"command",command:$c,timeout:5}')
  else want=$(jq -cn --arg c "$cmd" '{type:"command",command:$c,async:true,timeout:5}'); fi
  got=$(jq -c --arg e $e '[.hooks[$e][].hooks[] | select(.command | test("bin/ambient\"? hook "))]' "$f")
  assert_eq "$got" "[$want]" "Ambient entries under $e after reinstall"
done
assert_eq "$(jq -c '.hooks.PreToolUse[0]' "$f")" '{"matcher":"Bash","hooks":[{"type":"command","command":"echo mine"}]}' "the user's own group"
note "doctor flags it; reinstall leaves one current entry per event"
