#!/bin/zsh
# MEM-014 · Text that looks like a token or private key is refused, in the value, key or description.
# needs-app: yes
# Made-up tokens of the right shape only. The known gap's shapes (Stripe, JWT, Bearer, password=) are checked last.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"
refusal() { print -r -- "That looks like it contains $1. Every agent on this Mac can read shared memory, so Ambient doesn't share secrets. Leave it out, or say where the agent can find it instead."; }

ghp="ghp_${(l:36::a:)}"
ant="sk-ant-${(l:24::x:)}"
pem="-----BEGIN RSA PRIVATE KEY-----"
aws="AKIA${(l:16::Q:)}"
slack="xoxb-1234567890-abcdefghij"
openai="sk-proj-${(l:40::b:)}"
secrets=($ghp $ant $pem $aws $slack $openai)

expect_refused() { # what command...
  local what=$1; shift
  local err code
  err=$("$@" 2>&1); code=$?
  assert_eq "$code" 1 "exit code of [$*]"
  assert_contains "$err" "$(refusal "$what")" "[$*]"
}
expect_refused "a GitHub token" ambient memory set token "$ghp"
expect_refused "a GitHub token" ambient memory set "$ghp" x
expect_refused "an Anthropic API key" ambient memory set k x --description "use $ant"
expect_refused "a private key" ambient memory set k "$pem"
expect_refused "an AWS access key" ambient memory set k "key $aws here"
expect_refused "a Slack token" ambient memory set k "$slack"

r=$(agent_run claude mem-014 "$(real "$QA_ROOT/qa-mem")" <<EOF | sed -n 2p
$(call memory_write "{\"key\":\"k\",\"value\":\"OPENAI_API_KEY=$openai\"}")
EOF
)
assert_eq "$(jq -r .isError <<< $r)" true "step 4 MCP isError"
assert_eq "$(jq -r .text <<< $r)" "$(refusal "an OpenAI API key")" "step 4 MCP text"

list=$(ambient memory)
assert_eq "$(sed -n 1p <<< $list)" "Memory · qa-mem · 0 entries" "step 5 list"
sleep 2
for s in $secrets; do
  [[ -f $AMBIENT_HOME/memory.json ]] && assert_not_contains "$(cat "$AMBIENT_HOME/memory.json")" "$s" "memory.json"
done

# Known gap: other token shapes are shared.
for value in "sk_live_${(l:24::c:)}" \
             "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJxYSJ9.${(l:43::d:)}" \
             "Authorization: Bearer ${(l:32::e:)}" \
             "password=hunter2-qa"; do
  err=$(ambient memory set gap "$value" 2>&1); code=$?
  ambient memory rm gap >/dev/null 2>&1
  [[ $code == 1 && $err == *"That looks like it contains"* ]] || fail "shared as text, not refused: [${value:0:24}…]"
done
