#!/bin/zsh
# MEM-013 · Keys are short and plain.
# needs-app: yes
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"
plain="Keys use letters, digits and . _ : / @ - (no spaces), and start with a letter or digit, e.g. api-schema."

for key in "has space" -leading; do
  err=$(ambient memory set "$key" x 2>&1); code=$?
  assert_eq "$code" 1 "step 1 [$key] exit code ($err)"
  assert_contains "$err" "$plain" "step 1 [$key]"
done
err=$(ambient memory set "${(l:81::k:)}" x 2>&1); code=$?
assert_eq "$code" 1 "step 1 81-character key exit code"
assert_contains "$err" "Keys are limited to 80 characters." "step 1 81-character key"
ambient memory set "${(l:80::k:)}" x >/dev/null || fail "an 80-character key was refused"

for key in api/schema.v2 tests:unit@main "  padded  "; do
  ambient memory set "$key" ok >/dev/null || fail "step 2 [$key] refused"
done
assert_eq "$(ambient memory get api/schema.v2)" ok "step 2 api/schema.v2"
assert_eq "$(ambient memory get tests:unit@main)" ok "step 2 tests:unit@main"
assert_eq "$(ambient memory get padded)" ok "step 2 padded key read back as padded"
assert_eq "$(ambient memory get padded --json | jq -r .key)" padded "step 2 stored key"
