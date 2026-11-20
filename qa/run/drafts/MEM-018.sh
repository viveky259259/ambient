#!/bin/zsh
# MEM-018 · A `memory.json` this version can't read is left untouched.
# needs-app: yes
# timeout: 90
# A second QA app in its own AMBIENT_HOME, so memory.json is in place before it starts. Instead of waiting 15
# minutes, a copy no entry refers to is aged 6 minutes: a collection in the app's first sweeps would delete it.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"
b=$QA_ROOT/b
sha=${(l:64::e:)}
mkdir -p "$b/memory/$sha"
print 'old copy' > "$b/memory/$sha/old.log"
chmod 400 "$b/memory/$sha/old.log"; chmod 700 "$b/memory/$sha"
touch -h -t "$(date -v-6M +%Y%m%d%H%M.%S)" "$b/memory/$sha/old.log" "$b/memory/$sha"
print -rn -- '{"version":2,"entries":[]}' > "$b/memory.json"
cp "$b/memory.json" "$QA_ROOT/memory.json.written"

own_app "$b"
ambient memory set temp x >/dev/null || fail "step 2 set"
assert_eq "$(ambient memory get temp)" x "step 2 get"
sleep 15
cmp -s "$b/memory.json" "$QA_ROOT/memory.json.written" || fail "step 3 memory.json changed: $(cat "$b/memory.json")"
assert_file "$b/memory/$sha/old.log"

own_app_stop
own_app "$b"
err=$(ambient memory get temp 2>&1)
assert_contains "$err" "Nothing is shared as temp" "after a restart, temp"
cmp -s "$b/memory.json" "$QA_ROOT/memory.json.written" || fail "memory.json changed after the restart"
