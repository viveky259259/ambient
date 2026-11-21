#!/bin/zsh
# BRD-021 · Sessions that ended while Ambient was closed are unlinked on launch.
# needs-app: no
# Starts the QA app itself (see qa/run/board-lib.sh). A small Python process stands in for Claude Code: it sends the
# recorded hooks, so Ambient takes it for the agent, and stays until it is stopped while Ambient is closed.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"
board_app

mkdir -p "$QA_ROOT/qa-board-a"
/usr/bin/python3 -I - "$QA_APP/Contents/Helpers/ambient" "$QA_ROOT/qa-board-a" "$QA_ROOT/agent-ready" <<'PY' &
import subprocess, sys, time
ambient, cwd, ready = sys.argv[1:4]
base = '{"session_id":"brd021-claude","cwd":"%s",' % cwd
for rest in ['"hook_event_name":"UserPromptSubmit","prompt":"go"}',
             '"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"sleep 100"}}']:
    subprocess.run([ambient, "hook", "claude"], input=(base + rest).encode())
open(ready, "w").close()
time.sleep(300)
PY
AGENT=$!
wait_for 10 test -f "$QA_ROOT/agent-ready"
wait_for 5 test "$(task_get qa-board-a .status)" = inProgress
# Saved to disk (about a second after the change), then Ambient goes away, then the agent exits.
wait_for 5 grep -q inProgress "$AMBIENT_HOME/tasks.json"
wait_for 5 grep -q brd021-claude "$AMBIENT_HOME/state.json"
sleep 1.5
board_stop
kill $AGENT; wait $AGENT 2>/dev/null
board_app
assert_eq "$(task_get qa-board-a .status)" done "status after relaunch"
assert_eq "$(task_get qa-board-a '.sessionIds | length')" 0 "linked sessions after relaunch"
