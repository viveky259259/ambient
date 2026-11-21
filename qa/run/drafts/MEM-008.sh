#!/bin/zsh
# MEM-008 · Entries expire after 7 days by default, or after `ttl` minutes.
# needs-app: yes
# timeout: 150
# A second QA app in its own AMBIENT_HOME stands in for "Ambient was quit" while an entry expired.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"
main=$AMBIENT_HOME

# An entry that expires while its app isn't running.
own_app "$QA_ROOT/b"
ambient memory set gone x --ttl 1 >/dev/null || fail "set gone"
wait_for 5 grep -q '"gone"' "$AMBIENT_HOME/memory.json"
own_app_stop
export AMBIENT_HOME=$main

start=$EPOCHSECONDS
ambient memory set short x --ttl 1 >/dev/null || fail "step 1 set short"
ambient memory set long x >/dev/null || fail "step 1 set long"
exp=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$(ambient memory get long --json | jq -r .expires)" +%s)
(( exp - start >= 10080*60 - 5 && exp - start <= 10080*60 + 5 )) || fail "step 2 expires $(( (exp - start) / 60 )) min after the write, not 10080"

err=$(ambient memory set k x --ttl 0 2>&1); code=$?
assert_eq "$code" 1 "step 4 --ttl 0 exit code"
assert_contains "$err" "ttl_minutes must be between 1 and 43200 (30 days)." "step 4 --ttl 0"
err=$(ambient memory set k x --ttl 43201 2>&1); code=$?
assert_eq "$code" 1 "step 4 --ttl 43201 exit code"
assert_contains "$err" "ttl_minutes must be between 1 and 43200 (30 days)." "step 4 --ttl 43201"

r=$(agent_run claude mem-008 "$(real "$QA_ROOT/qa-mem")" <<EOF | sed -n 2p
$(call memory_write '{"key":"month","value":"x","ttl_minutes":43200}')
EOF
)
assert_eq "$(jq -r .isError <<< $r)" false "step 5 memory_write ttl_minutes 43200: $r"
exp=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$(jq -r .text <<< $r | jq -r .expires)" +%s)
(( exp - EPOCHSECONDS > 30*86400 - 120 && exp - EPOCHSECONDS <= 30*86400 + 5 )) || fail "step 5 expires is not 30 days out"

wait_for 5 grep -q '"short"' "$AMBIENT_HOME/memory.json"
sleep_until $(( start + 70 ))
assert_not_contains "$(ambient memory)" "short" "step 3 list"
err=$(ambient memory get short 2>&1); code=$?
assert_eq "$code" 1 "step 3 get short exit code"
assert_contains "$err" "Nothing is shared as short" "step 3 get short"
assert_eq "$(grep -c '"short"' "$AMBIENT_HOME/memory.json")" 0 "step 3 memory.json still holds the expired entry 10 s after it expired"
assert_contains "$(cat "$AMBIENT_HOME/memory.json")" '"long"' "memory.json keeps the live entry"

own_app "$QA_ROOT/b"
err=$(ambient memory get gone 2>&1)
assert_contains "$err" "Nothing is shared as gone" "an entry that expired while the app was quit"
no_gone() { ! grep -q '"gone"' "$AMBIENT_HOME/memory.json"; }
wait_for 5 no_gone
