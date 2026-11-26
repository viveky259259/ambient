#!/bin/zsh
# SET-040 · Hook-silence scan records nothing about processes but pid, path, start and CPU.
# needs-app: yes
# timeout: 150
# checks: part
# Checked: after a hook check with a Claude Code executable to fingerprint ($HOME/.local/bin/claude), agents.json
# holds only {"connected": [...]} and no file under AMBIENT_HOME holds that executable's path (a fingerprint).
# Left to a person: reading ProcessTree.interactiveAgents() and AgentExecutable.fingerprint.
source "$QA_REPO/qa/run/lib.sh"

mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/claude" && chmod +x "$HOME/.local/bin/claude"
fake_agent claude
ambient install claude >/dev/null || fail "install exited $?"
m=$(stat -f %Fm "$AMBIENT_HOME/agents.json")
wait_for 90 sh -c "[ \"\$(stat -f %Fm '$AMBIENT_HOME/agents.json')\" != '$m' ]"
sleep 1
assert_eq "$(jq -c 'keys' "$AMBIENT_HOME/agents.json")" '["connected"]' "agents.json keys"
assert_eq "$(jq -c '.connected' "$AMBIENT_HOME/agents.json")" '["claude"]' "agents.json connected"
hits=$(grep -rl -e '.local/bin/claude' -e 'cpuSeconds' -e 'fingerprint' "$AMBIENT_HOME" 2>/dev/null)
assert_eq "$hits" "" "files under AMBIENT_HOME naming the agent executable or scan fields"
note "files under AMBIENT_HOME: $(cd "$AMBIENT_HOME" && find . -type f | sort | tr '\n' ' ')"
