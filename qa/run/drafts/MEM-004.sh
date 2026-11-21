#!/bin/zsh
# MEM-004 · Project entries stay in their project; global ones reach every project.
# needs-app: yes
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
git_repo "$QA_ROOT/qa-mem-other"
git_repo "$QA_ROOT/other-parent/qa-mem"

cd "$QA_ROOT/qa-mem"
ambient memory set plan "project plan" >/dev/null || fail "set project plan"
ambient memory set plan "global plan" --global >/dev/null || fail "set global plan"
assert_eq "$(ambient memory get plan)" "project plan" "step 2 get (project first)"
assert_eq "$(ambient memory get plan --global)" "global plan" "step 2 get --global"

cd "$QA_ROOT/qa-mem-other"
assert_eq "$(ambient memory get plan)" "global plan" "step 3 get in another project"
out=$(ambient memory)
assert_eq "$(sed -n 1p <<< $out)" "Memory · qa-mem-other · 1 entry" "step 3 header"
assert_contains "$(sed -n 2p <<< $out)" " global " "step 3 only row is the global one"

cd "$QA_ROOT/other-parent/qa-mem"
err=$(ambient memory get plan --project 2>&1); code=$?
assert_eq "$code" 1 "step 4 exit code"
assert_contains "$err" "Nothing is shared as plan in qa-mem." "step 4 message (a same-named repository doesn't share)"

cd "$QA_ROOT/qa-mem"
ambient memory set plan x --in ../qa-mem-other >/dev/null || fail "set --in ../qa-mem-other"
assert_eq "$(ambient memory get plan --project --in ../qa-mem-other)" x "--in writes to the other project"
assert_eq "$(ambient memory get plan)" "project plan" "qa-mem's own entry is unchanged"

other=$(real "$QA_ROOT/qa-mem-other")
r=$(agent_run claude mem-004 "$(real "$QA_ROOT/qa-mem")" <<EOF | sed -n 2p
$(call memory_write "{\"key\":\"plan2\",\"value\":\"y\",\"project\":\"$other\"}")
EOF
)
assert_eq "$(jq -r .isError <<< $r)" false "memory_write with project: $r"
assert_eq "$(jq -r .text <<< $r | jq -r .project)" "$other" "memory_write with project lands in that project"
assert_eq "$(ambient memory get plan2 --project --in ../qa-mem-other)" y "read back in the other project"
