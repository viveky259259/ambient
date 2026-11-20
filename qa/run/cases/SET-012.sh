#!/bin/zsh
# SET-012 · Connect Antigravity writes a hook set of its own.
# needs-app: no
# checks: part
# Left to a person: a real `agy` session shows working and finishing on the island and never shows needs you.
# Note: lib.sh's `fake_agent antigravity` makes ~/.gemini/config, which is not how the installer finds
# Antigravity (~/.gemini/antigravity, -ide or -cli), so this script makes those folders itself.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

events=(SessionStart PreInvocation PreToolUse PostToolUse Stop)
f="$HOME/.gemini/config/hooks.json"
for dir in antigravity antigravity-ide antigravity-cli; do
  rm -rf "$HOME/.gemini"
  mkdir -p "$HOME/.gemini/$dir" "$HOME/.gemini/config"
  # Another hook set the user keeps in the same file.
  cat > "$f" <<'JSON'
{
  "mine": {
    "Stop": [
      {
        "type": "command",
        "command": "echo mine",
        "timeout": 3
      }
    ]
  }
}
JSON
  mine_before=$(jq -c '.mine' "$f")
  ambient install antigravity >/dev/null || fail "ambient install antigravity exited $? with ~/.gemini/$dir"
  assert_eq "$(jq -c '.ambient | keys_unsorted' "$f")" "$(printf '%s\n' $events | jq -R . | jq -sc .)" "events in the ambient set ($dir)"
  for e in $events; do
    c='[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook antigravity '$e' || true'
    entry=$(jq -cn --arg c "$c" '{type:"command",command:$c,timeout:5}')
    if [[ $e == PreToolUse || $e == PostToolUse ]]; then want="[{\"matcher\":\"*\",\"hooks\":[$entry]}]"; else want="[$entry]"; fi
    assert_eq "$(jq -c --arg e $e '.ambient[$e]' "$f")" "$want" "ambient.$e ($dir)"
  done
  assert_eq "$(jq -c '.mine' "$f")" "$mine_before" "the user's other hook set ($dir)"
done
note "found by each of its three data folders; the user's set untouched"
