#!/bin/zsh
# APP-031 · `AMBIENT_HOME` moves everything Ambient keeps.
# needs-app: yes
# timeout: 60
# The runner starts the QA app with AMBIENT_HOME=$QA_ROOT/a (step 1); $HOME/.ambient is the throwaway home's.
source "$QA_REPO/qa/run/lib.sh"

home=$AMBIENT_HOME
assert_file "$home/ambient.sock"
[[ -S $home/ambient.sock ]] || fail "$home/ambient.sock is not a socket"
for d in bin backups logs; do
  [[ -d $home/$d ]] || fail "missing $home/$d"
  assert_mode "$home/$d" 700
done

# After a change: state.json and tasks.json.
ambient emit working --session qa-home --agent Build --tool make >/dev/null || fail "emit failed"
wait_for 5 test -f "$home/state.json"
wait_for 5 test -f "$home/tasks.json"
assert_contains "$(<"$home/state.json")" '"sessionId":"qa-home"' "state.json"

# Step 2: the CLI answers from that copy.
assert_contains "$(ambient status)" "1 session" "ambient status with AMBIENT_HOME set"

# ~/.ambient is untouched.
assert_no_file "$HOME/.ambient"

# An empty AMBIENT_HOME falls back to ~/.ambient: there is no Ambient there.
out=$(AMBIENT_HOME= ambient status 2>&1)
assert_eq "$?" 1 "ambient status with AMBIENT_HOME empty"
assert_contains "$out" "Ambient isn't running" "ambient status with AMBIENT_HOME empty"
assert_contains "$(AMBIENT_HOME= ambient help)" "~/.ambient/logs/hook.log" "the paths with AMBIENT_HOME empty"
assert_no_file "$HOME/.ambient"
