#!/bin/zsh
# SET-009 · Connect Claude Code adds one background hook per event.
# needs-app: no
# checks: part
# Left to a person: the Connected badge and Remove button in Settings › Agents, and a real Claude Code session
# showing on the island. The CLI's `ambient install claude` stands in for the Connect button (same HookInstaller).
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"   # the default layout, so the hook command reads $HOME/.ambient/bin/ambient

fake_agent claude
f="$HOME/.claude/settings.json"
# The user's own settings and hooks, four-space indented.
cat > "$f" <<'JSON'
{
    "model": "opus",
    "permissions": {
        "allow": [
            "Bash(ls:*)"
        ]
    },
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
        ],
        "Stop": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": "say done"
                    }
                ]
            }
        ]
    },
    "theme": "dark"
}
JSON
cp "$f" "$QA_ROOT/before.json"

ambient install claude >/dev/null || fail "ambient install claude exited $?"

cmd='[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook claude || true'
events=(SessionStart UserPromptSubmit PreToolUse PostToolUse PostToolUseFailure PermissionRequest Notification PreCompact PostCompact SubagentStart SubagentStop Stop StopFailure SessionEnd)
for e in $events; do
  if [[ $e == SessionEnd ]]; then
    want=$(jq -cn --arg c "$cmd" '{type:"command",command:$c,timeout:5}')
  else
    want=$(jq -cn --arg c "$cmd" '{type:"command",command:$c,async:true,timeout:5}')
  fi
  # Ambient's group is the last one, holding exactly its one entry.
  assert_eq "$(jq -c --arg e $e '.hooks[$e][-1]' "$f")" "{\"hooks\":[$want]}" "Ambient's group under $e"
  # Exactly one Ambient entry under the event.
  n=$(jq --arg e $e '[.hooks[$e][].hooks[]? | select(.command | test("bin/ambient\"? hook "))] | length' "$f")
  assert_eq "$n" 1 "Ambient entries under $e"
  # The user's own groups come first, unchanged.
  assert_eq "$(jq -c --arg e $e '.hooks[$e][:-1]' "$f")" "$(jq -c --arg e $e '.hooks[$e] // []' "$QA_ROOT/before.json")" "the user's own groups under $e"
done
# Nothing else gained: only these events under hooks.
assert_eq "$(jq -c '.hooks | keys | sort' "$f")" "$(printf '%s\n' $events | jq -R . | jq -sc 'sort')" "events under hooks"
# Other settings unchanged, in the same order.
assert_eq "$(jq -c 'del(.hooks)' "$f")" "$(jq -c 'del(.hooks)' "$QA_ROOT/before.json")" "settings other than hooks"
assert_eq "$(jq -c 'keys_unsorted' "$f")" "$(jq -c 'keys_unsorted' "$QA_ROOT/before.json")" "top-level key order"
# The file keeps its own four-space indentation: every indented line is a multiple of four spaces, no tabs.
bad=$(grep -nE '^( {4})* {1,3}[^ ]|^	' "$f" | head -3)
assert_eq "$bad" "" "lines not indented in fours"
# Lines that were there before are still there, in the same order (the user's part is untouched text).
head -2 "$f" | tail -1 | grep -q '^    "model": "opus",$' || fail "second line is not the user's four-space \"model\" line"
note "14 events, one background entry each, user's groups first"
