#!/bin/zsh
# MEM-020 · Forgetting removes the project's entry first, then the global one.
# needs-app: yes
# A stand-in agent process calls memory_forget through `ambient mcp`.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"
ambient memory set k g --global >/dev/null || fail "set global"
ambient memory set k p >/dev/null || fail "set project"

out=$(agent_run claude mem-020 "$(real "$QA_ROOT/qa-mem")" <<EOF
$(call memory_forget '{"key":"k"}')
$(call memory_forget '{"key":"k"}')
$(call memory_forget '{"key":"k"}')
EOF
)
for n s in 2 project 3 global; do
  r=$(sed -n ${n}p <<< $out)
  assert_eq "$(jq -r .isError <<< $r)" false "forget $((n - 1)) isError"
  assert_eq "$(jq -r .text <<< $r | jq -r .forgotten.scope)" "$s" "forget $((n - 1)) scope"
done
r=$(sed -n 4p <<< $out)
assert_eq "$(jq -r .isError <<< $r)" true "third forget isError"
assert_eq "$(jq -r .text <<< $r)" "Nothing is shared as k in qa-mem or globally." "third forget"

ambient memory set k g --global >/dev/null; ambient memory set k p >/dev/null
r=$(agent_run claude mem-020b "$(real "$QA_ROOT/qa-mem")" <<EOF | sed -n 2p
$(call memory_forget '{"key":"k","scope":"global"}')
EOF
)
assert_eq "$(jq -r .text <<< $r | jq -r .forgotten.scope)" global "scope global forgets the global entry"
assert_eq "$(ambient memory get k)" p "the project entry stays"
err=$(ambient memory get k --global 2>&1)
assert_contains "$err" "Nothing is shared as k globally." "the global entry is gone"
