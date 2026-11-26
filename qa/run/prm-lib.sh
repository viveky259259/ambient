# Helpers for the permission (PRM-) and alert (ALR-) case scripts. Source after lib.sh.
#
# The app reads ~/.ambient/permissions.json and its defaults only when it starts, and the runner starts
# its app before the script runs. Cases that need the app started with given settings declare
# `# needs-app: yes` (for the lock and the cleared settings domain) and start their own instance with
# `own_app`, in its own AMBIENT_HOME under the case folder, and stop it by pid.

zmodload zsh/datetime zsh/mathfunc

# Writes permissions.json in the current AMBIENT_HOME. prm_settings ENABLED WAIT
prm_settings() {
  mkdir -p "$AMBIENT_HOME"
  print -r -- "{\"enabled\": $1, \"wait\": $2}" > "$AMBIENT_HOME/permissions.json"
}

QA_OWN_APPS=()
own_app_cleanup() {
  local pid
  for pid in $QA_OWN_APPS; do kill $pid 2>/dev/null; done
  for pid in $QA_OWN_APPS; do
    for i in {1..25}; do kill -0 $pid 2>/dev/null || break; sleep 0.2; done
    kill -9 $pid 2>/dev/null
  done
  [[ -n ${QA_ISLAND_PID:-} ]] && kill $QA_ISLAND_PID 2>/dev/null
  return 0
}
trap own_app_cleanup EXIT

# Starts another AmbientQA instance with a fresh AMBIENT_HOME ($QA_ROOT/<name>) and HOME, after `setup`
# (a function name or :) has seeded them. Exports AMBIENT_HOME so `ambient` talks to this instance.
# own_app NAME [setup-function]
own_app() {
  local name=$1 setup=${2:-:}
  export AMBIENT_HOME=$QA_ROOT/$name
  mkdir -p "$AMBIENT_HOME" "$QA_ROOT/home-$name"
  $setup
  HOME=$QA_ROOT/home-$name AMBIENT_HOME=$AMBIENT_HOME "$QA_APP/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
  QA_OWN_APP_PID=$!
  QA_OWN_APPS+=($QA_OWN_APP_PID)
  local end=$((SECONDS + 15))
  until /usr/bin/python3 -I -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])' "$AMBIENT_HOME/ambient.sock" 2>/dev/null; do
    kill -0 $QA_OWN_APP_PID 2>/dev/null || { echo "own_app: the QA app exited" >&2; exit 2; }
    (( SECONDS >= end )) && { echo "own_app: no socket within 15 s" >&2; exit 2; }
    sleep 0.2
  done
}

own_app_stop() {
  kill $QA_OWN_APP_PID 2>/dev/null
  for i in {1..25}; do kill -0 $QA_OWN_APP_PID 2>/dev/null || return 0; sleep 0.2; done
  kill -9 $QA_OWN_APP_PID 2>/dev/null
  return 0
}

# Runs `ambient ARGS...` with JSON on stdin from a stand-in agent process detached from this script
# (its parent is launchd), so the hook's process chain holds no app that might be in front: the case's
# "switch to Finder". Files: OUT (stdout), OUT.pid (the hook), OUT.agent (the stand-in agent),
# OUT.rc ("exit-code milliseconds") once the hook ends. Extra environment: QA_ASK_ENV="K=V ...".
# ask_detached OUT JSON ARGS...
ask_detached() {
  local out=$1 json=$2; shift 2
  rm -f "$out" "$out".pid "$out".agent "$out".rc
  /usr/bin/python3 -I - "$out" "$json" "${QA_ASK_ENV:-}" "$QA_APP/Contents/Helpers/ambient" "$@" <<'PY'
import os, subprocess, sys, time
out, payload, extra = sys.argv[1], sys.argv[2], sys.argv[3]
cmd = sys.argv[4:]
if os.fork() > 0:
    os._exit(0)
os.setsid()
if os.fork() > 0:
    os._exit(0)
devnull = os.open(os.devnull, os.O_RDWR)
for fd in (0, 1, 2):
    os.dup2(devnull, fd)
while os.getppid() != 1:
    time.sleep(0.02)
env = dict(os.environ)
for pair in extra.split():
    k, _, v = pair.partition("=")
    env[k] = v
with open(out + ".agent", "w") as f:
    f.write(str(os.getpid()))
start = time.time()
with open(out, "wb") as f:
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=f, stderr=subprocess.DEVNULL, env=env)
with open(out + ".pid", "w") as f:
    f.write(str(p.pid))
p.stdin.write(payload.encode())
p.stdin.close()
rc = p.wait()
with open(out + ".tmp", "w") as f:
    f.write("%d %d" % (rc, int((time.time() - start) * 1000)))
os.rename(out + ".tmp", out + ".rc")
PY
  wait_for 5 test -s "$out.pid"
}

# Waits for a detached hook to end and sets ASK_RC and ASK_MS. ask_wait OUT SECONDS
ask_wait() {
  wait_for $2 test -s "$1.rc"
  local r; r=$(<"$1.rc")
  ASK_RC=${r%% *}
  ASK_MS=${r##* }
}

# Whether a detached hook is still running.
ask_running() { [[ ! -s "$1.rc" ]] && kill -0 $(<"$1.pid") 2>/dev/null; }

# A stand-in for the app's socket that records every message, one per line, and answers a permission
# request with ANSWER (allow, deny or ask). fake_island ANSWER LOG
fake_island() {
  mkdir -p "$AMBIENT_HOME"
  /usr/bin/python3 -I - "$AMBIENT_HOME/ambient.sock" "$2" "$1" <<'PY' &
import json, socket, sys
path, out, answer = sys.argv[1], sys.argv[2], sys.argv[3]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path); s.listen(16)
with open(out, "ab", buffering=0) as f:
    while True:
        c, _ = s.accept()
        c.settimeout(5)
        data = b""
        try:
            while chunk := c.recv(65536):
                data += chunk
        except OSError:
            pass
        f.write(data.rstrip(b"\n") + b"\n")
        try:
            if "permissionRequest" in json.loads(data):
                c.sendall(json.dumps({"permissionAnswer": {"_0": answer}}).encode() + b"\n")
        except (ValueError, OSError):
            pass
        c.close()
PY
  QA_ISLAND_PID=$!
  wait_for 3 test -S "$AMBIENT_HOME/ambient.sock"
}

# The bundle id of the app in front right now, as the app itself asks NSWorkspace (read only, no
# Automation prompt), for "the agent's app is in front".
front_bundle() {
  osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier.js' 2>/dev/null
}

# Milliseconds since an $EPOCHREALTIME stamp.
ms_since() { local ms=$(( int((EPOCHREALTIME - $1) * 1000) )) || exit 2; print $ms; }

# A field of one session in state.json. sess SESSION_ID JQ-EXPRESSION
sess() { jq -r --arg id "$1" ".sessions[]? | select(.sessionId==\$id) | $2" "$AMBIENT_HOME/state.json" 2>/dev/null; }
# True when that field equals the value: for wait_for. sess_is SESSION_ID JQ-EXPRESSION VALUE
sess_is() { [[ "$(sess "$1" "$2")" == "$3" ]]; }
