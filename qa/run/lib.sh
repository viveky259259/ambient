# Helpers for QA case scripts. Sourced by qa/run/cases/<ID>.sh; the runner sets the environment:
#
#   HOME          a throwaway home for this case: agent configs live here, never in the real one
#   AMBIENT_HOME  $QA_ROOT/a: the app's socket, state, logs and CLI link
#   QA_ROOT       the case's own folder, removed afterwards when the case passes
#   QA_APP        build/AmbientQA.app
#   QA_APP_PID    the running QA app, when the script declares `# needs-app: yes`
#
# A script passes by exiting 0. Use the assert helpers so a failure says what differed.

set -u
zmodload zsh/datetime   # $EPOCHREALTIME for timings

[[ -n ${QA_ROOT:-} && $HOME == "$QA_ROOT"/* ]] || { echo "lib.sh: run cases through scripts/qa-run.ts, never in a real home" >&2; exit 2; }

ambient() { "$QA_APP/Contents/Helpers/ambient" "$@"; }

fail() { echo "FAIL: $*" >&2; exit 1; }
note() { echo "  · $*"; }

assert_eq() { # actual expected [message]
  [[ "$1" == "$2" ]] || fail "${3:-values differ}: expected [$2], got [$1]"
}
assert_ne() { [[ "$1" != "$2" ]] || fail "${3:-values are equal}: both [$1]"; }
assert_contains() { # haystack needle [message]
  [[ "$1" == *"$2"* ]] || fail "${3:-text is missing}: [$2] not in [${1:0:400}]"
}
assert_not_contains() { [[ "$1" != *"$2"* ]] || fail "${3:-text must not appear}: [$2] found"; }
assert_file() { [[ -e "$1" ]] || fail "missing file $1"; }
assert_no_file() { [[ ! -e "$1" ]] || fail "file should not exist: $1"; }
assert_mode() { # path octal-mode, e.g. 600
  local m; m=$(stat -f %Lp "$1") || fail "cannot stat $1"
  [[ $m == "$2" ]] || fail "mode of $1: expected $2, got $m"
}
assert_exit() { # expected-code command...
  local want=$1; shift
  "$@"; local got=$?
  [[ $got == "$want" ]] || fail "exit code of [$*]: expected $want, got $got"
}
assert_json() { # file jq-expression expected
  local got; got=$(jq -r "$2" "$1" 2>/dev/null) || fail "cannot read $2 from $1"
  [[ $got == "$3" ]] || fail "$1 $2: expected [$3], got [$got]"
}

# Polls a command until it succeeds. wait_for SECONDS command...
wait_for() {
  local limit=$1; shift
  local end=$((SECONDS + limit))
  until "$@" >/dev/null 2>&1; do
    (( SECONDS >= end )) && fail "timed out after ${limit}s waiting for: $*"
    sleep 0.2
  done
}

state() { cat "$AMBIENT_HOME/state.json" 2>/dev/null; }
# Waits for the app to save state, then prints a jq expression over it.
state_get() { # jq-expression
  wait_for 5 test -f "$AMBIENT_HOME/state.json"
  jq -r "$1" "$AMBIENT_HOME/state.json"
}

# Sends one agent hook event the way the agent would: JSON on stdin to `ambient hook <agent>`.
hook() { # agent json
  print -r -- "$2" | ambient hook "$1"
}

# Makes the throwaway home look like a Mac with this agent installed (its config folder).
fake_agent() {
  case $1 in
    claude) mkdir -p "$HOME/.claude" ;;
    codex) mkdir -p "$HOME/.codex" ;;
    gemini) mkdir -p "$HOME/.gemini" ;;
    antigravity) mkdir -p "$HOME/.gemini/config" ;;
    cursor) mkdir -p "$HOME/.cursor" ;;
    copilot) mkdir -p "$HOME/.copilot" ;;
    opencode) mkdir -p "$HOME/.config/opencode" ;;
    *) fail "fake_agent: unknown agent $1" ;;
  esac
}

# A stand-in for the app's socket that records what a hook sends, one line per message.
# Use it for cases about the wire itself, with `# needs-app: no`.
listen_socket() { # output-file
  /usr/bin/python3 -I - "$AMBIENT_HOME/ambient.sock" "$1" <<'PY' &
import os, socket, sys
path, out = sys.argv[1], sys.argv[2]
os.makedirs(os.path.dirname(path), exist_ok=True)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path); s.listen(16)
with open(out, "ab", buffering=0) as f:
    while True:
        c, _ = s.accept()
        data = b""
        c.settimeout(2)
        try:
            while chunk := c.recv(65536):
                data += chunk
        except OSError:
            pass
        c.close()
        f.write(data.rstrip(b"\n") + b"\n")
PY
  QA_LISTENER_PID=$!
  wait_for 3 test -S "$AMBIENT_HOME/ambient.sock"
  trap 'kill $QA_LISTENER_PID 2>/dev/null' EXIT
}
