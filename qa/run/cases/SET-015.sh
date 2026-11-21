#!/bin/zsh
# SET-015 · Connect Copilot CLI writes a hook file of Ambient's own.
# needs-app: no
# checks: part
# Left to a person: the badge going back to Not connected in Settings › Agents.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent copilot
print -r -- '{"model":"gpt-5"}' > "$HOME/.copilot/config.json"
mkdir -p "$HOME/.copilot/logs" && print -r -- 'x' > "$HOME/.copilot/logs/session.log"
snapshot() { (cd "$HOME/.copilot" && find . -type f ! -path ./hooks/ambient.json -exec shasum {} + | sort) }
before=$(snapshot)
[[ ! -e "$HOME/.copilot/hooks" ]] || fail "setup: hooks folder should not exist yet"

f="$HOME/.copilot/hooks/ambient.json"
ambient install copilot >/dev/null || fail "ambient install copilot exited $?"
assert_file "$f"
events=(sessionStart userPromptSubmitted preToolUse postToolUse postToolUseFailure notification preCompact subagentStart subagentStop agentStop errorOccurred sessionEnd)
assert_eq "$(jq -c 'keys_unsorted' "$f")" '["version","hooks"]' "top-level keys"
assert_json "$f" '.version' 1
assert_eq "$(jq -c '.hooks | keys_unsorted' "$f")" "$(printf '%s\n' $events | jq -R . | jq -sc .)" "Copilot events"
for e in $events; do
  c='[ -x "$HOME/.ambient/bin/ambient" ] && "$HOME/.ambient/bin/ambient" hook copilot '$e' || true'
  want=$(jq -cn --arg c "$c" '[{type:"command",bash:$c,timeoutSec:5}]')
  assert_eq "$(jq -c --arg e $e '.hooks[$e]' "$f")" "$want" "entry under $e"
done
assert_eq "$(snapshot)" "$before" "other files under ~/.copilot"
cp "$f" "$QA_ROOT/installed.json"

ambient uninstall copilot >/dev/null || fail "ambient uninstall copilot exited $?"
assert_no_file "$f"
backups=("$AMBIENT_HOME"/backups/copilot-ambient-*.json(N))
assert_eq "${#backups}" 1 "backups of ambient.json"
cmp -s "${backups[1]}" "$QA_ROOT/installed.json" || fail "the backup is not the removed ambient.json"
assert_eq "$(snapshot)" "$before" "other files under ~/.copilot after removing"
note "file created with its folder, 12 events, removed with a backup"
