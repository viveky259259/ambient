#!/bin/zsh
# MEM-002 · `ambient memory` shares, lists, prints and removes an entry.
# needs-app: yes
# Run from a plain shell, as the case does: no agent session, so no author.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"

out=$(ambient memory set failing-tests "TaskStoreTests.persistRoundTrip" --description "Still red after the fix" 2>&1)
assert_eq $? 0 "set exit code"
note "$out"
assert_contains "$out" "✓ Shared failing-tests (qa-mem)" "step 1 success line"
assert_contains "$out" "Expires $(date -v+7d '+%b %-d, %Y')" "step 1 expiry 7 days from now"

out=$(ambient memory 2>&1)
assert_eq "$(sed -n 1p <<< $out)" "Memory · qa-mem · 1 entry" "step 2 header"
assert_eq "$(sed -n 2p <<< $out)" "  $(printf '%-28s' failing-tests) project  Still red after the fix  —, just now" "step 2 row"

assert_eq "$(ambient memory get failing-tests)" "TaskStoreTests.persistRoundTrip" "step 3 raw value"
assert_eq "$(ambient memory get failing-tests | wc -c | tr -d ' ')" 32 "step 3 bytes (value and one newline)"
json=$(ambient memory get failing-tests --json)
assert_eq "$(jq -r .value <<< $json)" "TaskStoreTests.persistRoundTrip" "step 3 --json value"
assert_eq "$(jq -c keys_unsorted <<< $json)" "$(jq -c keys <<< $json)" "step 3 --json fields sorted"

out=$(ambient memory rm failing-tests 2>&1)
assert_contains "$out" "Forgot failing-tests (qa-mem)" "step 4 forget line"
err=$(ambient memory get failing-tests 2>&1); code=$?
assert_eq "$code" 1 "step 4 get after rm exit code"
assert_contains "$err" "Nothing is shared as failing-tests in qa-mem or globally." "step 4 message"

err=$(ambient memory frobnicate 2>&1); code=$?
assert_eq "$code" 64 "step 5 frobnicate exit code"
assert_contains "$err" "Usage: ambient memory" "step 5 usage line"
err=$(ambient memory set k --ttl soon 2>&1); code=$?
assert_eq "$code" 64 "step 5 --ttl soon exit code"
assert_contains "$err" "--ttl takes minutes, e.g. --ttl 60." "step 5 --ttl message"

# Known gap: the README's command reference leaves out flags the CLI accepts.
ref=$(grep -E '^ambient memory \[' "$QA_REPO/README.md")
for flag in --project --description --ttl --json; do
  assert_contains "$ref" "$flag" "README's ambient memory reference"
done
