#!/bin/zsh
# EVT-017 · Copilot CLI reports prompts, tools, needs-you and errors.
# needs-app: yes
# checks: part
# Left to a person: the rows in pink (#DB61A2).
# Replays Copilot CLI's hooks (`ambient hook copilot <event>`, camelCase payloads as in CopilotAdapterTests).
source "$QA_REPO/qa/run/lib.sh"

status_of() { # agent title: the status text of that row of `ambient status`
  local want="  ● ${(r:11:)1} ${(r:28:)2} " line rest
  for line in "${(@f)$(ambient status)}"; do
    [[ $line == "$want"* ]] || continue
    rest=${line:${#want}}
    print -r -- "${rest%  *}"
    return 0
  done
  return 1
}
expect_status() { # agent title expected [seconds]
  local got end=$(( EPOCHREALTIME + ${4:-3} ))
  while :; do
    got=$(status_of "$1" "$2")
    [[ $got == "$3" ]] && { note "$2 · $got"; return 0; }
    (( EPOCHREALTIME > end )) && fail "$1 $2: expected [$3], got [${got:-no row}]"
    sleep 0.1
  done
}
cop() { print -r -- "$2" | ambient hook copilot "$1"; }   # event json
stays() { sleep 0.5; expect_status copilot cli "$1" 0; }

P='{"sessionId":"cp1","timestamp":1763694000000,"cwd":"'$QA_ROOT'/cli"'
cop sessionStart "$P"',"source":"new","initialPrompt":""}'
cop userPromptSubmitted "$P"',"prompt":"what changed?"}'
expect_status copilot cli "Thinking"
cop preToolUse "$P"',"toolName":"bash","toolArgs":"{\"command\":\"git status\",\"description\":\"Status\"}"}'
expect_status copilot cli "Shell · git status"
cop postToolUse "$P"',"toolName":"bash","toolArgs":"{\"command\":\"git status\"}","toolResult":{"resultType":"success","textResultForLlm":"clean"}}'
expect_status copilot cli "Thinking"

cop preToolUse "$P"',"toolName":"bash","toolArgs":"{\"command\":\"git push --force\"}"}'
cop notification "$P"',"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Copilot needs your permission to use bash"}'
expect_status copilot cli "Approve a command"
cop postToolUse "$P"',"toolName":"bash","toolArgs":"{\"command\":\"git push --force\"}","toolResult":{"resultType":"success"}}'
cop notification "$P"',"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow the github MCP server to create a pull request?"}'
expect_status copilot cli "Approve a tool · Allow the github MCP server to create a pull request?"
cop notification "$P"',"hook_event_name":"Notification","notification_type":"agent_idle","message":"Copilot is idle"}'
stays "Approve a tool · Allow the github MCP server to create a pull request?"
cop notification "$P"',"hook_event_name":"Notification","notification_type":"shell_completed","message":"Shell command finished"}'
stays "Approve a tool · Allow the github MCP server to create a pull request?"

cop postToolUse "$P"',"toolName":"github-create_pr","toolArgs":"{}","toolResult":{"resultType":"success"}}'
expect_status copilot cli "Thinking"
print -r -- '{"sessionId":"cp1","error":{"message":"Rate limited, retrying"},"recoverable":true}' | ambient hook copilot errorOccurred
stays "Thinking"
print -r -- '{"sessionId":"cp1","error":{"message":"Rate limited, retrying"},"recoverable":false}' | ambient hook copilot errorOccurred
expect_status copilot cli "Failed · Rate limited, retrying"

cop userPromptSubmitted "$P"',"prompt":"try again"}'
cop agentStop "$P"',"stopReason":"end_turn"}'
expect_status copilot cli "Done"
