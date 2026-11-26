#!/bin/zsh
# PRM-015 · A prompt answered in the agent's own window withdraws the card.
# needs-app: yes
# checks: part
# Left to a person: the card disappearing on screen, with the Claude desktop app's dialog racing it.
# Answering on, wait 20 s. While a recorded prompt waits in the --answer hook, the agent's later events arrive as if
# it was answered in the agent's own window.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

setup() { prm_settings true 20; }
own_app b setup
S='"session_id":"prm-015","cwd":"'$QA_ROOT'/api"'
P='{'$S',"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'

typeset -A next=(
  tool '{'$S',"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf build"},"tool_response":{"stdout":"","stderr":"","interrupted":false}}'
  stop '{'$S',"hook_event_name":"Stop","last_assistant_message":"done"}'
  prompt '{'$S',"hook_event_name":"UserPromptSubmit","prompt":"next"}'
)
for what in tool stop prompt; do
  ask_detached "$QA_ROOT/ask-$what" "$P" hook claude --answer
  sleep 1.5
  ask_running "$QA_ROOT/ask-$what" || fail "$what: the prompt was handed back before anything happened"
  if [[ $what == tool ]]; then
    # A different tool finishing in the same session leaves the card in place.
    hook claude '{'$S',"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"tool_response":{}}'
    sleep 1.5
    ask_running "$QA_ROOT/ask-$what" || fail "an unrelated tool (Read) finishing withdrew the Bash prompt"
  fi
  start=$EPOCHREALTIME
  hook claude "$next[$what]"
  until [[ -s $QA_ROOT/ask-$what.rc ]]; do
    (( $(ms_since $start) > 5000 )) && fail "$what: the card stayed 5 s after the agent moved on"
    sleep 0.05
  done
  ms=$(ms_since $start)
  assert_eq "$(<"$QA_ROOT/ask-$what")" "" "$what: hook output (the island must answer nothing)"
  (( ms < 1500 )) || fail "$what: withdrawn $ms ms after the agent moved on (want at once)"
  note "$what: withdrawn $ms ms after the event"
done
