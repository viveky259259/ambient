#!/bin/zsh
# MEM-005 · Git worktrees of one repository share its memory; submodules and loose folders don't.
# needs-app: yes
# A stand-in Codex process reads from the worktree, as the real agent would through `ambient mcp`.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
root=$(real "$QA_ROOT/qa-mem")
git -C "$QA_ROOT/qa-mem" worktree add -q ../qa-mem-wt -b feature || fail "git worktree add"
mkdir -p "$QA_ROOT/qa-mem/src/deep"

cd "$QA_ROOT/qa-mem/src/deep"
ambient memory set handoff "from main" >/dev/null || fail "step 2 set"

cd "$QA_ROOT/qa-mem-wt"
r=$(agent_run codex mem-005 "$(real "$QA_ROOT/qa-mem-wt")" <<EOF | sed -n 2p
{"hook":{"hook_event_name":"SessionStart","source":"startup"}}
$(call memory_read '{"key":"handoff"}')
EOF
)
note "worktree read: $r"
assert_eq "$(jq -r .isError <<< $r)" false "step 3 memory_read isError"
t=$(jq -r .text <<< $r)
assert_eq "$(jq -r .value <<< $t)" "from main" "step 3 value"
assert_eq "$(jq -r .project <<< $t)" "$root" "step 3 project is qa-mem's root, not the worktree's"
assert_contains "$(ambient memory | sed -n 1p)" "Memory · qa-mem · " "step 3 CLI header in the worktree"

mkdir -p "$QA_ROOT/qa-loose"
cd "$QA_ROOT/qa-loose"
assert_eq "$(ambient memory | sed -n 1p)" "Memory · qa-loose · 0 entries" "step 4 header outside a repository"

git_repo "$QA_ROOT/lib-src"
git -C "$QA_ROOT/qa-mem" -c protocol.file.allow=always submodule add -q "$QA_ROOT/lib-src" vendor/lib || fail "git submodule add"
cd "$QA_ROOT/qa-mem/vendor/lib"
err=$(ambient memory get handoff 2>&1); code=$?
assert_eq "$code" 1 "step 5 exit code"
assert_contains "$err" "Nothing is shared as handoff in lib or globally." "step 5 message (a submodule is its own project)"
