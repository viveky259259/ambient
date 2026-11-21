#!/bin/zsh
# SET-011 · Connect Gemini CLI adds hooks named ambient, timed in milliseconds.
# needs-app: no
# checks: part
# Left to a person: a real Gemini CLI session runs without a hook JSON error and shows on the island.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent gemini
f="$HOME/.gemini/settings.json"
ambient install gemini >/dev/null || fail "ambient install gemini exited $?"
cmd='[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook gemini || true'
want=$(jq -cn --arg c "$cmd" '{name:"ambient",type:"command",command:$c,timeout:1500}')
events=(SessionStart BeforeAgent BeforeTool AfterTool Notification PreCompress AfterAgent SessionEnd)
assert_eq "$(jq -c '.hooks | keys_unsorted' "$f")" "$(printf '%s\n' $events | jq -R . | jq -sc .)" "Gemini events"
for e in $events; do
  assert_eq "$(jq -c --arg e $e '[.hooks[$e][].hooks[]]' "$f")" "[$want]" "entry under $e"
done
note "8 Gemini events, each named ambient with a 1500 ms timeout"
