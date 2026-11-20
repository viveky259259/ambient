#!/bin/zsh
# EVT-003 · Each kind of Claude Code prompt says what it needs.
# needs-app: yes
# Replays Claude Code's PreToolUse → PermissionRequest → PostToolUse for each kind of prompt, in place of a real session.
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

S='{"session_id":"evt3-run","transcript_path":"'$HOME'/.claude/projects/api/evt3-run.jsonl","cwd":"'$QA_ROOT'/api","permission_mode":"default"'
hook claude "$S"',"hook_event_name":"UserPromptSubmit","prompt":"go"}'

ask() { # tool tool_input expected
  hook claude "$S"',"hook_event_name":"PreToolUse","tool_name":"'$1'","tool_input":'$2'}'
  hook claude "$S"',"hook_event_name":"PermissionRequest","tool_name":"'$1'","tool_input":'$2'}'
  expect_status claude api "$3"
  hook claude "$S"',"hook_event_name":"PostToolUse","tool_name":"'$1'","tool_input":'$2',"tool_response":{}}'
  expect_status claude api "Thinking"
}

ask Edit '{"file_path":"'$QA_ROOT'/api/Sources/Session.swift","old_string":"a","new_string":"b"}' "Review a change · Session.swift"
ask WebFetch '{"url":"https://example.com/x","prompt":"summarize"}' "Allow web access · example.com"
ask Read '{"file_path":"'$QA_ROOT'/elsewhere/notes.md"}' "Approve a tool · Read: notes.md"
ask ExitPlanMode '{"plan":"# Add caching\n\n1. Cache the parsed config\n2. Invalidate on save"}' "Review a plan · Add caching"
ask mcp__github__create_pr '{"title":"Add caching","body":"x"}' "Approve a tool · github · create_pr"
ask AskUserQuestion '{"questions":[{"question":"Which cache store?","header":"Store","options":[{"label":"Memory","description":"Fast"},{"label":"Disk","description":"Survives"}],"multiSelect":false},{"question":"Expire after how long?","header":"TTL","options":[],"multiSelect":false}]}' "Answer a question · Which cache store? (+1 more)"
