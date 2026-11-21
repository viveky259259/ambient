#!/bin/zsh
# WAL-025 · Today's story survives restarts and starts fresh at midnight.
# needs-app: yes
# timeout: 120
# checks: part
# Left to a person: step 3 as written, the clock passing midnight while Ambient keeps running (here a day.json from
# yesterday is loaded at launch instead), and a turn running across midnight counting only its time after it; the
# scene's own text.
# Replays recorded Claude Code hooks in place of a real agent. Quits the case's own QA app by its pid and starts it
# again, with this case's HOME and AMBIENT_HOME, to stand in for quitting and relaunching.
source "$QA_REPO/qa/run/lib.sh"
day=$AMBIENT_HOME/day.json
mkdir -p "$QA_ROOT"/{api,web}

app=$QA_APP_PID
trap '[[ $app != $QA_APP_PID ]] && kill $app 2>/dev/null' EXIT

relaunch() { # [command to run while Ambient is closed]
  kill -TERM $app 2>/dev/null
  local end=$((SECONDS + 10))
  # The runner started the first app and can't reap it while the script runs, so a quit one stays a zombie (Z).
  while [[ -n $(ps -o stat= -p $app 2>/dev/null | grep -v Z) ]]; do
    (( SECONDS >= end )) && fail "the QA app (pid $app) did not quit within 10 s"
    sleep 0.2
  done
  (( $# )) && "$@"
  "$QA_APP/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
  app=$!
  wait_for 15 ambient status
  kill -0 $app 2>/dev/null || fail "the QA app exited after relaunch"
}
ev() { hook claude '{"session_id":"wal025-'$1'","cwd":"'$QA_ROOT/$1'","hook_event_name":"'$2'"'${3:-}'}'; }
field() { jq -c ".log.$1" "$day"; }
tools_are() { [[ $(jq -r '.log.tools' "$day" 2>/dev/null) == "$1" ]]; }

# Some activity: two finished turns, one failed, a call for you.
ev api UserPromptSubmit
ev api PreToolUse ',"tool_name":"Read","tool_input":{"file_path":"a.txt"}'
ev api Notification ',"notification_type":"agent_needs_input","message":"Which one?"'
ev api Stop
ev web UserPromptSubmit
ev web PreToolUse ',"tool_name":"Bash","tool_input":{"command":"make"}'
ev web StopFailure ',"error_message":"Quota exceeded"'
wait_for 10 tools_are 2
sleep 1.5
before=$(jq -cS '.log' "$day")
note "before relaunch: $(jq -c '.log | {tools, turnsDone, turnsFailed, neededYou, projects, moments: (.moments|length)}' "$day")"

# Step 2: readable and writable by the user only.
assert_mode "$day" 600

# Step 1: after a relaunch the story carries on from where it was.
relaunch
ev api PreToolUse ',"tool_name":"Read","tool_input":{"file_path":"b.txt"}'
wait_for 10 tools_are 3
sleep 1.5
assert_eq "$(jq -cS '.log | .tools -= 1' "$day")" "$before" "today's story after relaunch and one more tool"
assert_mode "$day" 600

# Step 3: a story saved yesterday starts a fresh day.
today=$(field day)
relaunch zsh -c 'jq ".log.day -= 86400" "$1" > "$1.tmp" && mv "$1.tmp" "$1"' _ "$day"
fresh() { [[ $(jq -r '.log.day' "$day") == "$today" ]]; }
wait_for 10 fresh
assert_eq "$(jq -c '.log | [.tools, .turnsDone, .turnsFailed, .neededYou, .finishedSeconds, .longestRun]' "$day")" \
  '[0,0,0,0,0,0]' "counts of a fresh day"
assert_eq "$(jq -c '.log | [.projects, .marks, .moments]' "$day")" '[[],[],[]]' "projects, marks and moments of a fresh day"

# Step 4: a damaged file doesn't stop Ambient, which starts a fresh day.
relaunch zsh -c 'print garbage > "$1"' _ "$day"
ev web PreToolUse ',"tool_name":"Bash","tool_input":{"command":"make"}'
wait_for 10 tools_are 1
assert_eq "$(jq -c '.log | [.tools, .turnsDone, .turnsFailed, .neededYou, (.moments|length)]' "$day")" \
  '[1,0,0,0,0]' "story after launching over a damaged day.json and one tool"
assert_eq "$(field day)" "$today" "the day a damaged file is replaced with"
