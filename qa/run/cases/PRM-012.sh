#!/bin/zsh
# PRM-012 · An unreachable app means no wait at all.
# needs-app: no
# Answering is on; the permission hook runs with no app, then with a socket file the quit app left behind.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

prm_settings true 20
P='{"session_id":"prm-012","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'

check() { # label
  local start=$EPOCHREALTIME out code ms
  out=$(print -r -- "$P" | ambient hook claude --answer)
  code=$?
  ms=$(ms_since $start)
  assert_eq "$code" 0 "hook exit code ($1)"
  assert_eq "$out" "" "hook output ($1): nothing may be answered"
  (( ms < 1000 )) || fail "$1: the hook waited $ms ms for an app that isn't there"
  note "$1: returned in $ms ms with no output"
}

check "no socket"
/usr/bin/python3 -I -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$AMBIENT_HOME/ambient.sock"
assert_file "$AMBIENT_HOME/ambient.sock"
check "stale socket"
