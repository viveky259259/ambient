#!/bin/zsh
# MEM-017 · Shared memory is saved for your user only and survives a restart.
# needs-app: yes
# checks: part
# Left to a person: quitting from the menu saves at once (a write just before quitting isn't lost); here the app is
# stopped by pid, which doesn't run the app's quit.
# A second QA app in its own AMBIENT_HOME is stopped and started again for the restart.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"
own_app "$QA_ROOT/b"

start=$EPOCHREALTIME
ambient memory set keep "still here" >/dev/null || fail "step 1 set"
saved() { grep -q '"still here"' "$AMBIENT_HOME/memory.json" 2>/dev/null; }
wait_for 3 saved
note "memory.json saved $(( int((EPOCHREALTIME - start) * 1000) )) ms after the write"
(( EPOCHREALTIME - start < 2 )) || fail "memory.json saved more than 2 s after the write"
assert_mode "$AMBIENT_HOME/memory.json" 600
assert_json "$AMBIENT_HOME/memory.json" .version 1
assert_json "$AMBIENT_HOME/memory.json" '.entries[] | select(.key == "keep") | .value' "still here"

print 'a shared file' > shared.txt
ambient memory set file --file shared.txt >/dev/null || fail "step 2 share"
for d in "$AMBIENT_HOME"/memory/*(/); do assert_mode "$d" 700; done
for f in "$AMBIENT_HOME"/memory/*/*(.); do assert_mode "$f" 400; done

sleep 2
own_app_stop
own_app "$QA_ROOT/b"
assert_eq "$(ambient memory get keep)" "still here" "step 3 after a restart"
