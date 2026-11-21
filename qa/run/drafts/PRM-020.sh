#!/bin/zsh
# PRM-020 · MCP tools show no details and the card says so.
# needs-app: no
# checks: part
# Left to a person: the card reading wants to use <tool> with Its details aren't shown here. and See it all in <app>, both in amber.
# Checks what the permission hook hands the island for an MCP tool: its name and no hint.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

prm_settings true 20
fake_island ask "$QA_ROOT/island.log"
P='{"session_id":"prm-020","hook_event_name":"PermissionRequest","cwd":"'$QA_ROOT'","tool_name":"mcp__github__delete_repo","tool_input":{"repo":"work/everything","command":"rm -rf /"}}'
out=$(print -r -- "$P" | ambient hook claude --answer)
assert_eq "$out" "" "hook output when the island hands the prompt back"
assert_eq "$(jq -r '.permissionRequest._0.toolName' "$QA_ROOT/island.log")" "mcp__github__delete_repo" "tool name sent to the island"
assert_eq "$(jq -r '.permissionRequest._0 | has("hint") and .hint != null' "$QA_ROOT/island.log")" false "an MCP tool must carry no hint"
