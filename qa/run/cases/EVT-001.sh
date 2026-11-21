#!/bin/zsh
# EVT-001 · A Claude Code turn shows as working, with the tool and its hint.
# needs-app: yes
# checks: part
# Left to a person: the orb breathing in Claude coral (#D97757).
# Replays a recorded Claude Code turn (UserPromptSubmit, Pre/PostToolUse for Bash, Read, WebFetch and an MCP tool).
source "$QA_REPO/qa/run/lib.sh"

# Reads one row of `ambient status`: `  ● <agent, 11> <title, 28> <status>  <clock>`.
status_of() { # agent title
  local want="  ● ${(r:11:)1} ${(r:28:)2} " line rest
  for line in "${(@f)$(ambient status)}"; do
    [[ $line == "$want"* ]] || continue
    rest=${line:${#want}}
    print -r -- "${rest%  *}"
    return 0
  done
  return 1
}
clock_of() { # agent title
  local want="  ● ${(r:11:)1} ${(r:28:)2} " line
  for line in "${(@f)$(ambient status)}"; do
    [[ $line == "$want"* ]] && { print -r -- "${line##*  }"; return 0; }
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

S='{"session_id":"evt1-run","transcript_path":"'$HOME'/.claude/projects/api/evt1-run.jsonl","cwd":"'$QA_ROOT'/api","permission_mode":"default"'

hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"run sleep 15 && echo ok"}'
expect_status claude api "Thinking" 1

sleep 2
hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"sleep 15 && echo ok","description":"Wait, then print ok"}}'
expect_status claude api "Bash · sleep 15 && echo ok"
clock=$(clock_of claude api)
[[ $clock == <2-9>s ]] || fail "the clock should count from the prompt (2 s or more before the tool), got [$clock]"
note "clock $clock"
hook claude "$S"',"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"sleep 15 && echo ok"},"tool_response":{"stdout":"ok\n","stderr":"","interrupted":false}}'
expect_status claude api "Thinking"

hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"'$QA_ROOT'/api/Sources/Session.swift"}}'
expect_status claude api "Read · Session.swift"
hook claude "$S"',"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"'$QA_ROOT'/api/Sources/Session.swift"},"tool_response":{"type":"text"}}'
expect_status claude api "Thinking"

hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"WebFetch","tool_input":{"url":"https://example.com/docs","prompt":"Summarize"}}'
expect_status claude api "WebFetch · example.com"
hook claude "$S"',"hook_event_name":"PostToolUse","tool_name":"WebFetch","tool_input":{"url":"https://example.com/docs","prompt":"Summarize"},"tool_response":{"code":200}}'
expect_status claude api "Thinking"

hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"mcp__github__create_pr","tool_input":{"title":"Add caching","body":"x"}}'
expect_status claude api "github · create_pr"
hook claude "$S"',"hook_event_name":"PostToolUse","tool_name":"mcp__github__create_pr","tool_input":{"title":"Add caching"},"tool_response":{"url":"x"}}'
expect_status claude api "Thinking"
