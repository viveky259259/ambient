#!/bin/zsh
# EVT-011 · Gemini CLI reports its turn and says what its confirmation needs.
# needs-app: yes
# checks: part
# Left to a person: the rows in Gemini blue (#4F8DF7).
# Replays Gemini CLI's hooks (BeforeAgent, BeforeTool, ToolPermission Notification, AfterTool, AfterAgent) with the
# payload shapes in GeminiAdapterTests and WaitingReasonTests.geminiDescribesItsConfirmation.
# Known gap check, last: Gemini CLI has no failure hook, so a turn whose tool failed ends as Done, never Failed.
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
gem() { hook gemini "$1" >/dev/null; }   # Gemini's hook always prints {} back (EVT-012)

S='{"session_id":"evt11-gem","transcript_path":"'$HOME'/.gemini/tmp/x/chats/session.json","cwd":"'$QA_ROOT'/site","timestamp":"2026-11-21T03:00:00.000Z"'
tool() { # name input expected-working [details expected-confirmation]
  gem "$S"',"hook_event_name":"BeforeTool","tool_name":"'$1'","tool_input":'$2'}'
  expect_status gemini site "$3"
  if [[ -n ${4:-} ]]; then
    gem "$S"',"hook_event_name":"Notification","notification_type":"ToolPermission","message":"Tool requires confirmation","details":'$4'}'
    expect_status gemini site "$5"
  fi
  gem "$S"',"hook_event_name":"AfterTool","tool_name":"'$1'","tool_input":'$2',"tool_response":{"llmContent":"x","error":null}}'
  expect_status gemini site "Thinking"
}

gem "$S"',"hook_event_name":"SessionStart","source":"startup"}'
gem "$S"',"hook_event_name":"BeforeAgent","prompt":"tidy the site"}'
expect_status gemini site "Thinking"
tool run_shell_command '{"command":"ls -la","description":"List"}' "Shell · ls -la" \
  '{"type":"exec","title":"Shell","command":"ls -la","rootCommand":"ls"}' "Approve a command · ls -la"
tool read_file '{"absolute_path":"'$QA_ROOT'/site/README.md"}' "Read · README.md"
tool replace '{"file_path":"'$QA_ROOT'/site/README.md","old_string":"a","new_string":"b"}' "Edit · README.md" \
  '{"type":"edit","title":"Edit","fileName":"README.md","filePath":"'$QA_ROOT'/site/README.md","fileDiff":"..."}' "Review a change · README.md"
tool google_web_search '{"query":"static site hosting"}' "Search · static site hosting"
tool web_fetch '{"prompt":"Summarize https://example.com"}' "Fetch · Summarize https://example.com" \
  '{"type":"info","title":"Web Fetch","prompt":"Summarize https://example.com","urls":["https://example.com"]}' "Allow web access · example.com"
tool mcp__github__create_pr '{"title":"Tidy"}' "github · create_pr" \
  '{"type":"mcp","title":"MCP","serverName":"github","toolName":"create_pr"}' "Approve a tool · github · create_pr"

response="Tidied the site: README.md rewritten, two dead links removed, and the build passes. Nothing else changed in the repository. Tell me if you want the old README kept as a backup somewhere."
gem "$S"',"hook_event_name":"AfterAgent","prompt":"tidy the site","prompt_response":"'$response'","stop_hook_active":false}'
expect_status gemini site "Done · ${response[1,159]}…"

# Known gap: a turn that fails never shows Failed. Here the only tool fails and the turn ends.
F='{"session_id":"evt11-fail","cwd":"'$QA_ROOT'/broken"'
gem "$F"',"hook_event_name":"BeforeAgent","prompt":"deploy"}'
gem "$F"',"hook_event_name":"BeforeTool","tool_name":"run_shell_command","tool_input":{"command":"make deploy"}}'
gem "$F"',"hook_event_name":"AfterTool","tool_name":"run_shell_command","tool_input":{"command":"make deploy"},"tool_response":{"llmContent":"","error":"exit status 2"}}'
gem "$F"',"hook_event_name":"AfterAgent","prompt":"deploy","prompt_response":"","stop_hook_active":false}'
sleep 0.5
got=$(status_of gemini broken)
[[ $got == Failed* ]] || fail "known gap: a Gemini turn whose tool failed reads [$got], never Failed (the Gemini adapter maps no failure event)"
