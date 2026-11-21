#!/bin/zsh
# MEM-003 · `ambient memory set` takes its value from standard input.
# needs-app: yes
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"

printf 'line one\nline two\n' | ambient memory set notes >/dev/null
assert_eq $? 0 "step 1 exit code"
echo hello | ambient memory set notes2 - >/dev/null
assert_eq $? 0 "step 2 exit code"
assert_eq "$(ambient memory get notes2)" hello "step 2 value"

err=$(ambient memory set notes3 one two 2>&1); code=$?
assert_eq "$code" 64 "step 3 exit code"
assert_contains "$err" "Give the value as one argument, in quotes, or a file, not both." "step 3 message"

ambient memory get notes > "$QA_ROOT/got"
printf 'line one\nline two\n' > "$QA_ROOT/want"
cmp -s "$QA_ROOT/got" "$QA_ROOT/want" || fail "step 4 printed [$(od -c "$QA_ROOT/got" | head -3)]"
