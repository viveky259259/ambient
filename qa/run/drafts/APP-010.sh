#!/bin/zsh
# APP-010 · Sessions whose agent exited while Ambient was closed don't come back.
# needs-app: yes
# timeout: 90
# Each "agent" is a perl process that sends its session's event through the CLI and stays alive until killed, in
# place of a Claude Code session in a terminal; it is detached from this script, so it is the session's only process.
source "$QA_REPO/qa/run/lib.sh"

CLI=$QA_APP/Contents/Helpers/ambient
AGENTS=()
gone() { local s; s=$(ps -o stat= -p $1 2>/dev/null); [[ -z $s || $s == Z* ]]; }
up() { ambient status >/dev/null 2>&1; }
cleanup() {
  [[ -n ${APP_PID:-} ]] && kill $APP_PID 2>/dev/null
  for p in $AGENTS; do kill $p 2>/dev/null; done
}
trap cleanup EXIT
# agent SESSION: starts an agent process that reports SESSION working, and prints its pid.
agent() {
  local pidfile=$QA_ROOT/.agent.$1
  ( /usr/bin/perl -e 'open(F, ">", shift) or die; print F $$; close F; select(undef, undef, undef, 0.3);
                       system(@ARGV) == 0 or exit 1; sleep 600' \
      $pidfile "$CLI" emit working --session $1 --agent Build --tool make >/dev/null 2>&1 & )
  wait_for 5 test -s $pidfile
  AGENTS+=($(<$pidfile))
}
ids() { ambient status --json | jq -r '[.[].sessionId] | sort | join(" ")'; }
have() { [[ $(ids) == "$1" ]]; }

agent qa-alive
agent qa-exited
agent qa-root
( ( sleep 0.2; "$CLI" emit working --session qa-nopid --agent Build >/dev/null 2>&1 ) & )
wait_for 5 have "qa-alive qa-exited qa-nopid qa-root"
sleep 2   # state is written about a second after a change
assert_eq "$(jq -r '.sessions[] | select(.sessionId=="qa-exited") | .host.agentPid' "$AMBIENT_HOME/state.json")" "${AGENTS[2]}" "qa-exited's agent pid"
assert_eq "$(jq -r '.sessions[] | select(.sessionId=="qa-nopid") | .host.agentPid' "$AMBIENT_HOME/state.json")" "null" "qa-nopid has no agent pid"

# Quit Ambient, end one agent, and make another session's process one owned by another user (launchd, root).
kill $QA_APP_PID
wait_for 10 gone $QA_APP_PID
kill ${AGENTS[2]}
wait_for 5 gone ${AGENTS[2]}
jq -c '(.sessions[] | select(.sessionId=="qa-root") | .host.agentPid) = 1' "$AMBIENT_HOME/state.json" > $QA_ROOT/state.tmp
mv $QA_ROOT/state.tmp "$AMBIENT_HOME/state.json"

"$QA_APP/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
APP_PID=$!
wait_for 15 up
sleep 6
assert_eq "$(ids)" "qa-alive qa-nopid qa-root" "sessions 6 s after relaunch"
