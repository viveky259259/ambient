#!/bin/zsh
# EVT-012 · Gemini CLI always gets valid JSON back from the hook.
# needs-app: yes
# Sends Gemini CLI's hook input as the case does, with Ambient running, then with no Ambient (a home whose socket nobody serves).
source "$QA_REPO/qa/run/lib.sh"

# Prints exactly what the hook wrote, with a trailing '|' so a final newline survives, then the exit code.
run() { # input-mode
  local out code
  case $1 in
    payload) out=$(print -r -- '{"session_id":"g1","hook_event_name":"BeforeTool","tool_name":"run_shell_command"}' | ambient hook gemini; code=$?; print -rn -- "|$code") ;;
    garbage) out=$(print -r -- 'not json' | ambient hook gemini; code=$?; print -rn -- "|$code") ;;
    empty)   out=$(ambient hook gemini </dev/null; code=$?; print -rn -- "|$code") ;;
  esac
  print -r -- "$out"
}

for where in running quit; do
  for input in payload garbage empty; do
    if [[ $where == quit ]]; then
      got=$(AMBIENT_HOME=$QA_ROOT/no-app run $input)
    else
      got=$(run $input)
    fi
    assert_eq "$got" $'{}\n|0' "Gemini hook stdout and exit code ($input, Ambient $where)"
  done
  note "Ambient $where: {} and a newline, exit 0, for a payload, garbage and empty input"
done
