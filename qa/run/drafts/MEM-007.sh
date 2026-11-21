#!/bin/zsh
# MEM-007 · Writing a key again replaces the entry and restarts its lifetime.
# needs-app: yes
# "A few minutes later" is a few seconds here: what's checked is that the rewrite's expiry is 7 days, not the first ttl.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"

ambient memory set tests "3 failing" --ttl 60 >/dev/null || fail "step 1 set"
first=$(ambient memory get tests --json | jq -r .expires)
sleep 2
ambient memory set tests "1 failing" >/dev/null || fail "step 2 set"
json=$(ambient memory get tests --json)
assert_eq "$(jq -r .value <<< $json)" "1 failing" "step 2 value"
assert_eq "$(jq -r .updated <<< $json)" "just now" "step 2 updated"
exp=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$(jq -r .expires <<< $json)" +%s)
(( exp - EPOCHSECONDS > 7*86400 - 120 )) || fail "step 2 expires $(jq -r .expires <<< $json), not 7 days out (first write's was $first)"
assert_eq "$(ambient memory | grep -c '^  tests ')" 1 "rows for tests after the rewrite"

print 'build ok' > build.log
ambient memory set tests --file ./build.log >/dev/null || fail "step 3 set --file"
path=$(ambient memory get tests)
assert_contains "$path" "$AMBIENT_HOME/memory/" "step 3 get prints the copy's path"
assert_eq "$(cat "$path")" "build ok" "step 3 copy's content"
assert_contains "$(ambient memory | grep '^  tests ')" "file build.log" "step 3 list row"
assert_eq "$(ambient memory | grep -c '^  tests ')" 1 "rows for tests after sharing a file under it"

ambient memory set tests g --global >/dev/null || fail "set --global"
assert_eq "$(ambient memory | grep -c '^  tests ')" 2 "a global write makes a second, separate entry"
assert_eq "$(ambient memory get tests --global)" g "global entry"
assert_eq "$(ambient memory get tests --project)" "$path" "project entry still the file"
