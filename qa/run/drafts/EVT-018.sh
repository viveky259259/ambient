#!/bin/zsh
# EVT-018 · OpenCode's permission requests and questions say what they need, and an answer resumes work.
# needs-app: yes
# Replays what Ambient's OpenCode plugin sends (Claude's format plus Permission, Question and Answered, stamped with
# `ts`), with the payload shapes in OpenCodeAdapterTests.
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
ts() { print -r -- $(( ${EPOCHREALTIME/./} / 1000 )); }   # OpenCode's clock, in milliseconds
oc() { hook opencode '{"session_id":"ses_evt18","cwd":"'$QA_ROOT'/app","ts":'$(ts)','"$1"'}'; }

oc '"hook_event_name":"UserPromptSubmit"'
expect_status opencode app "Thinking"

oc '"hook_event_name":"PreToolUse","tool_name":"bash","tool_input":{"command":"bun test","description":"Run tests"}'
expect_status opencode app "Shell · bun test"
oc '"hook_event_name":"Permission","permission":"bash","patterns":["bun test *"],"metadata":{"command":"bun test"}'
expect_status opencode app "Approve a command · bun test"
oc '"hook_event_name":"Answered"'
expect_status opencode app "Shell · bun test" 1
oc '"hook_event_name":"PostToolUse","tool_name":"bash","tool_input":{"command":"bun test"}'

oc '"hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{"patchText":"*** Update File: src/a.ts\n*** Update File: src/b.ts"}'
expect_status opencode app "Patch · a.ts +1 more"
oc '"hook_event_name":"Permission","permission":"edit","patterns":["src/a.ts","src/b.ts"],"metadata":{"filepath":"src/a.ts, src/b.ts"}'
expect_status opencode app "Review a change · a.ts +1 more"
oc '"hook_event_name":"Answered"'
expect_status opencode app "Patch · a.ts +1 more" 1
oc '"hook_event_name":"PostToolUse","tool_name":"apply_patch","tool_input":{}'

oc '"hook_event_name":"PreToolUse","tool_name":"read","tool_input":{"filePath":"'$HOME'/elsewhere/notes.md"}'
expect_status opencode app "Read · notes.md"
oc '"hook_event_name":"Permission","permission":"external_directory","patterns":["'$HOME'/elsewhere/*"],"metadata":{"filepath":"'$HOME'/elsewhere/notes.md","parentDir":"'$HOME'/elsewhere"}'
expect_status opencode app "Allow access outside the project · ~/elsewhere"
oc '"hook_event_name":"Answered"'
expect_status opencode app "Read · notes.md" 1
oc '"hook_event_name":"PostToolUse","tool_name":"read","tool_input":{}'
expect_status opencode app "Thinking"

oc '"hook_event_name":"Question","questions":[{"question":"Which database?","header":"DB","options":[{"label":"Postgres"},{"label":"SQLite"}]}]'
expect_status opencode app "Answer a question · Which database?"
oc '"hook_event_name":"Answered"'
expect_status opencode app "Thinking" 1
