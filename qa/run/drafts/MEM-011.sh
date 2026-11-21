#!/bin/zsh
# MEM-011 · Copies of files no entry refers to are deleted after a grace period.
# needs-app: yes
# timeout: 180
# checks: part
# Left to a person: the real-time grace and timing (a copy stays 5 minutes, then goes within about 10).
# Instead of waiting 12 minutes: copies are aged by setting their modification time back 6 minutes (collection
# judges age by it), and a fresh QA app in its own AMBIENT_HOME collects within its first sweep (collection then
# runs every 5 minutes).
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"
print 'log a' > a.log; print 'log b' > b.log; print 'log c' > c.log

own_app "$QA_ROOT/b"
copy_a=$(ambient memory set log-a --file a.log >/dev/null && ambient memory get log-a) || fail "share a.log"
ambient memory rm log-a >/dev/null || fail "rm log-a"
copy_b=$(ambient memory set log-b --file b.log >/dev/null && ambient memory get log-b) || fail "share b.log"
ambient memory set log-b2 --file b.log >/dev/null || fail "share b.log again"
ambient memory rm log-b >/dev/null || fail "rm log-b"
copy_c=$(ambient memory set log-c --file c.log --ttl 1 >/dev/null && ambient memory get log-c) || fail "share c.log"
c_made=$EPOCHSECONDS
note "copies: $copy_a $copy_b $copy_c"

# Fresh copies stay through a collection.
sleep 2; own_app_stop; own_app "$QA_ROOT/b"; sleep 8
assert_file "$copy_a"

age() { touch -h -t "$(date -v-6M +%Y%m%d%H%M.%S)" "$@"; }
age "$copy_a" "${copy_a:h}" "$copy_b" "${copy_b:h}"
own_app_stop; own_app "$QA_ROOT/b"
gone_a() { [[ ! -e $copy_a ]]; }
wait_for 15 gone_a
assert_file "$copy_b"
# Removing the copy touched its folder, so the empty folder waits for a later collection.
[[ -e ${copy_a:h} ]] && note "the emptied folder outlived the collection that deleted its copy"
age "${copy_a:h}"
own_app_stop; own_app "$QA_ROOT/b"
folder_gone() { [[ ! -e ${copy_a:h} ]]; }
wait_for 15 folder_gone

# An entry that expires loses its copy the same way.
sleep_until $(( c_made + 62 ))
err=$(ambient memory get log-c 2>&1)
assert_contains "$err" "Nothing is shared as log-c" "log-c after its ttl"
sleep 2; age "$copy_c" "${copy_c:h}"
own_app_stop; own_app "$QA_ROOT/b"
gone_c() { [[ ! -e $copy_c ]]; }
wait_for 15 gone_c
assert_file "$copy_b"
