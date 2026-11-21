#!/bin/zsh
# MEM-006 · A `ambient mcp` started in `/` or the home folder uses the session's project.
# needs-app: yes
# Stand-in agent processes start `ambient mcp` in / and in the home folder, as some agent apps do.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
root=$(real "$QA_ROOT/qa-mem")

for start in / "$HOME"; do
  out=$(agent_run claude "mem-006-${#start}" "$root" <<EOF
{"hook":{"hook_event_name":"SessionStart","source":"startup"}}
{"hook":{"hook_event_name":"UserPromptSubmit","prompt":"remember where"}}
{"sleep":1}
{"mcp_cwd":"$start"}
$(call memory_write '{"key":"where","value":"here"}')
EOF
)
  r=$(sed -n 2p <<< $out)
  note "started in $start: $r"
  assert_eq "$(jq -r .isError <<< $r)" false "memory_write from an mcp started in $start"
  assert_eq "$(jq -r .text <<< $r | jq -r .project)" "$root" "project of a write from an mcp started in $start"
done
cd "$QA_ROOT/qa-mem"
assert_eq "$(ambient memory get where)" here "step 3 get in qa-mem"

# With no session Ambient knows (no hooks), the project is the folder itself.
r=$(agent_run claude mem-006-unknown "$root" <<EOF | sed -n 2p
{"mcp_cwd":"/"}
$(call memory_write '{"key":"where-unknown","value":"x"}')
EOF
)
assert_eq "$(jq -r .text <<< $r | jq -r .project)" / "project with no known session"
