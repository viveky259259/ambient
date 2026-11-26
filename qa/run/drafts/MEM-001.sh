#!/bin/zsh
# MEM-001 · One agent's text is read back by another agent in the same project.
# needs-app: yes
# Stand-in Claude Code and Codex processes send their hooks and call `ambient mcp`, as the real agents would.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
root=$(real "$QA_ROOT/qa-mem")
value='{"GET /users": "200 [User]"}'

# Claude Code writes, and stays running while Codex reads.
agent_start "$QA_ROOT/claude.out" claude mem-claude-1 "$root" <<EOF
{"hook":{"hook_event_name":"SessionStart","source":"startup"}}
{"hook":{"hook_event_name":"UserPromptSubmit","prompt":"share the schema"}}
{"sleep":1}
$(call memory_write "$(jq -nc --arg v "$value" '{key:"api-schema",value:$v,description:"Users endpoint contract"}')")
{"sleep":10}
EOF
wait_reply "$QA_ROOT/claude.out" 1
w=$(reply "$QA_ROOT/claude.out" 1)
note "write: $w"
assert_eq "$(jq -r .isError <<< $w)" false "memory_write isError"
t=$(jq -r .text <<< $w)
assert_eq "$(jq -r 'has("value")' <<< $t)" false "write result has a value field"
assert_eq "$(jq -r .key <<< $t)" api-schema "key"
assert_eq "$(jq -r .scope <<< $t)" project "scope"
assert_eq "$(jq -r .project <<< $t)" "$root" "project"
assert_eq "$(jq -r .size <<< $t)" 28 "size"
assert_eq "$(jq -r .updated <<< $t)" "just now" "updated"
assert_eq "$(jq -r .shared_by <<< $t)" "Claude Code (claude:mem-claude-1)" "shared_by"
exp=$(jq -r .expires <<< $t)
exp_s=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$exp" +%s) || fail "expires is not ISO 8601: $exp"
(( exp_s - EPOCHSECONDS > 7*86400 - 120 && exp_s - EPOCHSECONDS <= 7*86400 + 5 )) || fail "expires $exp is not 7 days from now"
(( $(jq -r .ms <<< $w) < 1000 )) || fail "memory_write took $(jq -r .ms <<< $w) ms"

out=$(agent_run codex mem-codex-1 "$root" <<EOF
{"hook":{"hook_event_name":"SessionStart","source":"startup"}}
{"hook":{"hook_event_name":"UserPromptSubmit","prompt":"read it"}}
$(call memory_read '{"key":"api-schema"}')
$(call memory_list)
EOF
)
r=$(sed -n 2p <<< $out); l=$(sed -n 3p <<< $out)
note "read: $r"
assert_eq "$(jq -r .isError <<< $r)" false "memory_read isError"
rt=$(jq -r .text <<< $r)
assert_eq "$(jq -r .value <<< $rt)" "$value" "value read back"
assert_eq "$(jq -r .shared_by <<< $rt)" "Claude Code (claude:mem-claude-1)" "shared_by on read (the writer)"
assert_eq "$(jq -r .description <<< $rt)" "Users endpoint contract" "description on read"
(( $(jq -r .ms <<< $r) < 1000 )) || fail "memory_read took $(jq -r .ms <<< $r) ms"

note "list: $l"
lt=$(jq -r .text <<< $l)
assert_eq "$(jq -r '.entries[0].key' <<< $lt)" api-schema "newest listed entry"
assert_eq "$(jq -r '.entries[0].description' <<< $lt)" "Users endpoint contract" "listed description"
assert_eq "$(jq -r '.entries[0].size' <<< $lt)" 28 "listed size"
assert_eq "$(jq -r '[.entries[] | has("value")] | any' <<< $lt)" false "a listed entry has a value"
(( $(jq -r .ms <<< $l) < 1000 )) || fail "memory_list took $(jq -r .ms <<< $l) ms"
