#!/bin/zsh
# PRM-031 · ambient doctor says when the island answers.
# needs-app: no
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

line='• Permission prompts: the island answers for Claude Code and Codex, waiting 30s before the agent asks'
prm_settings true 30
out=$(ambient doctor 2>&1)
assert_contains "$out" "$line" "doctor with answering on, wait 30"

prm_settings false 30
out=$(ambient doctor 2>&1)
assert_not_contains "$out" "Permission prompts" "doctor with answering off"
