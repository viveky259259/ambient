#!/bin/zsh
# SET-042 · Hooks are re-checked every ten minutes.
# needs-app: yes
# timeout: 900
# Holds the app lock for about twelve minutes. Every hook check rewrites agents.json, which is how the script
# knows the first one ran. A real Claude Code update on this Mac during the wait would trigger an early check.
source "$QA_REPO/qa/run/lib.sh"

get_ns() { python3 -I -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$1"; }
set_ns() { python3 -I -c 'import os,sys; n=int(sys.argv[2]); os.utime(sys.argv[1], ns=(n, n))' "$1" "$2"; }

fake_agent claude
f="$HOME/.claude/settings.json"
ambient install claude >/dev/null || fail "install exited $?"
m=$(stat -f %Fm "$AMBIENT_HOME/agents.json")
wait_for 90 sh -c "[ \"\$(stat -f %Fm '$AMBIENT_HOME/agents.json')\" != '$m' ]"
sleep 1
checked=$SECONDS

ns=$(get_ns "$f")
jq '(.hooks.Stop[-1].hooks[0]) |= del(.async)' "$f" > "$QA_ROOT/partial.json"
cat "$QA_ROOT/partial.json" > "$f"
set_ns "$f" "$ns"
assert_contains "$(ambient doctor 2>&1)" "! Claude: hooks are incomplete or outdated" "doctor after the edit"

wait_for 720 sh -c "[ \"\$(jq '.hooks.Stop[-1].hooks[0].async' '$f')\" = true ]"
took=$((SECONDS - checked))
note "hooks rewritten $took s after the previous check"
(( took >= 540 )) || fail "rewritten after only $took s: something other than the ten-minute check ran"
found=0
for b in "$AMBIENT_HOME"/backups/claude-settings-*.json(N); do cmp -s "$b" "$QA_ROOT/partial.json" && found=1; done
assert_eq "$found" 1 "a backup holding the edited file"
