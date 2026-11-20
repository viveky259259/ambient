#!/bin/zsh
# MEM-019 · With Ambient not running, agents are told to open it, and a slow write isn't retried blind.
# needs-app: no
# timeout: 90
# No app runs in this case's AMBIENT_HOME. For "running but not answering", a stand-in socket accepts and never replies.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"
closed="Ambient isn't running. Open Ambient.app, then try again."

for args in "" "set k x" "get k"; do
  start=$EPOCHREALTIME
  err=$(ambient memory ${=args} 2>&1); code=$?
  ms=$(( int((EPOCHREALTIME - start) * 1000) ))
  assert_eq "$code" 1 "step 2 [ambient memory $args] exit code"
  assert_contains "$err" "$closed" "step 2 [ambient memory $args]"
  (( ms < 1500 )) || fail "step 2 [ambient memory $args] took $ms ms"
done

out=$(agent_run claude mem-019 "$(real "$QA_ROOT/qa-mem")" <<EOF
$(call memory_list)
{"rpc":{"jsonrpc":"2.0","id":99,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}}
EOF
)
r=$(sed -n 2p <<< $out)
assert_eq "$(jq -r .isError <<< $r)" true "step 3 memory_list isError"
assert_eq "$(jq -r .text <<< $r)" "$closed" "step 3 memory_list text"
text=$(sed -n 3p <<< $out | jq -r .result.instructions)
assert_contains "$text" "Never share secrets." "step 3 initialize still answers with the instructions"
assert_not_contains "$text" "Shared with this project right now" "step 3 instructions"

err=$(ambient memory set k "$(head -c 40000 /dev/zero | tr '\0' a)" 2>&1)
assert_contains "$err" "text is limited to 32 KB. Share it as a file instead." "step 4 (checked before anything is sent)"
assert_not_contains "$err" "isn't running" "step 4"

# Running, but not answering.
mkdir -p "$AMBIENT_HOME"
/usr/bin/python3 -I - "$AMBIENT_HOME/ambient.sock" <<'PY' &
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1]); s.listen(16)
held = []
while True:
    c, _ = s.accept()
    held.append(c)
PY
QA_BG_PIDS+=($!)
wait_for 3 test -S "$AMBIENT_HOME/ambient.sock"
for args in "set k x" "rm k"; do
  start=$EPOCHREALTIME
  err=$(ambient memory ${=args} 2>&1)
  note "[$args] answered in $(( int((EPOCHREALTIME - start) * 1000) )) ms"
  assert_contains "$err" "Ambient didn't answer in time, so this may still go through. Read it back before trying again." "[ambient memory $args] with no answer"
done
for args in "get k" ""; do
  err=$(ambient memory ${=args} 2>&1)
  assert_contains "$err" "Ambient didn't answer in time. Try again in a moment." "[ambient memory $args] with no answer"
done
