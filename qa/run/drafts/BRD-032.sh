#!/bin/zsh
# BRD-032 · Cloud-tagged models are refused.
# needs-app: no
# timeout: 180
# checks: part
# Left to a person: the subtitle's amber colour.
# Starts the QA app itself with summaries on and each cloud-tagged model id (the setting is in Settings › Board), with a
# fake local-agent gateway that lists both ids as chat models, so only Ambient's own refusal keeps them from running.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

gw_config "[$(gw_model gpt-oss:120b-cloud chat), $(gw_model ollama:cloud/llama3 chat)]"
fake_gateway
n=0
for id in gpt-oss:120b-cloud ollama:cloud/llama3; do
  board_app taskLLMEnabled=YES taskLLMModelID=$id
  assert_eq "$(ambient task model --json | jq -r .status)" "Model $id looks cloud-hosted. Choose a local hf:/ollama: model." "status for $id"
  n=$((n + 1))
  S='{"session_id":"brd032-'$n'","cwd":"'$QA_ROOT'/cloud-'$n'"'
  hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"go"}'
  hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
  sleep 5
  assert_eq "$(gw_calls submit_inference)" 0 "submit_inference calls with $id"
  assert_eq "$(ambient tasks --json | jq -r 'map(.summary // "") | join("")')" "" "summaries with $id"
  board_stop
done
