#!/bin/zsh
# BRD-031 · Reading agent chats is a separate opt-in.
# needs-app: no
# timeout: 240
# checks: part
# Left to a person: the toggle's subtitle; whether Ambient opens a transcript at all with the toggle off (fs_usage).
# Starts the QA app itself with summaries on and a fake local-agent gateway that logs each prompt (see
# qa/run/board-lib.sh); each Claude Code session has a transcript in the case home holding a canary.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

gw_config "[$(gw_model hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit chat)]"
fake_gateway
transcript() { # session-id
  local dir=$HOME/.claude/projects/-qa-board
  mkdir -p $dir
  local i
  for i in 1 2 3 4 5 6 7 8; do
    jq -nc --arg t "user turn $i transcript-canary-$i $(printf 'x%.0s' {1..300})" '{type: "user", message: {role: "user", content: $t}}'
    jq -nc --arg t "assistant turn $i transcript-canary-$i" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $t}]}}'
  done > $dir/$1.jsonl
}
facts() { # the prompt's session facts for a session
  jq -r --arg s "$1" 'select(.tool == "submit_inference") | .arguments.prompt | select(contains("session_id: " + $s))' $QA_ROOT/gw.log \
    | sed -n '/^Session facts:/,$p' | tail -n +2
}
run() { # session-id
  transcript $1
  local S='{"session_id":"'$1'","cwd":"'$QA_ROOT'/'$1'","transcript_path":"'$HOME'/.claude/projects/-qa-board/'$1'.jsonl"'
  hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"go"}'
  hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
  wait_for 30 test -n "$(facts $1)"
}

# Off (the default with summaries on).
board_app taskLLMEnabled=YES taskLLMReadTranscripts=NO
run brd031-off
f=$(facts brd031-off)
print -r -- "$f" | sed 's/^/    /'
assert_not_contains "$f" transcript_excerpt "the prompt with the toggle off"
assert_not_contains "$f" transcript-canary "the prompt with the toggle off"
keys=$(print -r -- "$f" | sed 's/:.*//' | sort -u | tr '\n' ' ')
for k in ${=keys}; do
  [[ " agent session_id project cwd title mood activity " == *" $k "* ]] || fail "the prompt carries [$k], beyond agent, session id, project, folder, title, mood and activity"
done

# On.
board_stop
board_app taskLLMEnabled=YES taskLLMReadTranscripts=YES
run brd031-on
f=$(facts brd031-on)
assert_contains "$f" "transcript_excerpt:" "the prompt with the toggle on"
assert_contains "$f" "transcript-canary-8" "the prompt with the toggle on"
excerpt=$(print -r -- "$f" | sed -n '/^transcript_excerpt:/,$p' | tail -n +2)
(( ${#excerpt} <= 2500 )) || fail "the excerpt is ${#excerpt} characters (at most 2,500)"
note "excerpt: ${#excerpt} characters"
# Sent only to the loopback gateway this case started.
assert_eq "$(jq -r .tool $QA_ROOT/gw.log | sort -u | tr '\n' ' ')" "get_job list_models model_storage_status submit_inference " "gateway calls"
