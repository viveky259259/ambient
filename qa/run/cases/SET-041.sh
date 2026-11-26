#!/bin/zsh
# SET-041 · An agent update triggers a hook re-check.
# needs-app: yes
# timeout: 240
# A stand-in Claude Code executable at $HOME/.local/bin/claude (the first place AgentExecutable looks) is "updated"
# by moving its modification time. Every hook check rewrites agents.json, which is how the script knows one ran.
source "$QA_REPO/qa/run/lib.sh"

get_ns() { python3 -I -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "$1"; }
set_ns() { python3 -I -c 'import os,sys; n=int(sys.argv[2]); os.utime(sys.argv[1], ns=(n, n))' "$1" "$2"; }
agents_mtime() { stat -f %Fm "$AMBIENT_HOME/agents.json"; }

mkdir -p "$HOME/.local/bin"
exe="$HOME/.local/bin/claude"
printf '#!/bin/sh\nexit 0\n' > "$exe" && chmod +x "$exe"
fake_agent claude
f="$HOME/.claude/settings.json"
ambient install claude >/dev/null || fail "install exited $?"
# Let the app's first check see the new file and the executable.
m=$(agents_mtime)
wait_for 90 sh -c "[ \"\$(stat -f %Fm '$AMBIENT_HOME/agents.json')\" != '$m' ]"
sleep 1

# Partial hooks, with the file's modification time put back exactly.
ns=$(get_ns "$f")
jq '(.hooks.Stop[-1].hooks[0]) |= del(.async)' "$f" > "$QA_ROOT/partial.json"
cat "$QA_ROOT/partial.json" > "$f"
set_ns "$f" "$ns"
assert_eq "$(get_ns "$f")" "$ns" "settings.json modification time after the edit"
assert_contains "$(ambient doctor 2>&1)" "! Claude: hooks are incomplete or outdated" "doctor after the edit"

# The "update".
now_ns=$(python3 -I -c 'import time; print(time.time_ns() + 120 * 10**9)')
set_ns "$exe" "$now_ns"
start=$SECONDS
wait_for 80 sh -c "[ \"\$(jq '.hooks.Stop[-1].hooks[0].async' '$f')\" = true ]"
note "hooks rewritten $((SECONDS - start)) s after the executable changed"
