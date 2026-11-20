# Helpers for the working-memory (MEM-) and remote (RMT-) case scripts. Source after lib.sh.
#
# Ambient tells which agent session is asking by its process: the first ancestor of a hook, or of
# `ambient mcp`, that isn't a shell. So a stand-in agent here is one Python process that sends its
# agent's hooks and runs `ambient mcp` as its own children, the way Claude Code or Codex would.

zmodload zsh/datetime zsh/mathfunc

QA_AGENT_PY=$QA_ROOT/agent.py
cat > "$QA_AGENT_PY" <<'PY'
# A stand-in agent process. argv: AGENT SESSION CWD. Commands on stdin, one JSON object per line:
#   {"hook": {...}}                 sends this hook event (session_id and cwd added) through `ambient hook AGENT`
#   {"call": NAME, "args": {...}}   calls an `ambient mcp` tool; prints {"ms", "isError", "text"}
#   {"rpc": {...}}                  sends one JSON-RPC message to `ambient mcp`; prints the reply line
#   {"mcp_cwd": DIR}                (re)starts `ambient mcp` in DIR (default CWD)
#   {"sleep": SECONDS}
# Prints {"pid": N} first. Every reply is one JSON line on stdout.
import json, os, subprocess, sys, time

ambient = os.path.join(os.environ["QA_APP"], "Contents/Helpers/ambient")
agent, session, cwd = sys.argv[1:4]
mcp = None
next_id = 0

def out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

def start(folder):
    global mcp
    if mcp:
        mcp.stdin.close(); mcp.wait()
    mcp = subprocess.Popen([ambient, "mcp"], cwd=folder, stdin=subprocess.PIPE, stdout=subprocess.PIPE)

def rpc(message):
    if mcp is None:
        start(cwd)
    mcp.stdin.write((json.dumps(message) + "\n").encode()); mcp.stdin.flush()
    if "id" not in message:
        return None
    return mcp.stdout.readline().decode()

out({"pid": os.getpid()})
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    cmd = json.loads(line)
    if "hook" in cmd:
        event = {"session_id": session, "cwd": cwd}
        event.update(cmd["hook"])
        subprocess.run([ambient, "hook", agent], input=json.dumps(event).encode(), cwd=cwd,
                       stdout=subprocess.DEVNULL)
    elif "call" in cmd:
        next_id += 1
        started = time.time()
        reply = json.loads(rpc({"jsonrpc": "2.0", "id": next_id, "method": "tools/call",
                                "params": {"name": cmd["call"], "arguments": cmd.get("args", {})}}))
        result = reply.get("result", {})
        out({"ms": int((time.time() - started) * 1000), "isError": result.get("isError"),
             "text": (result.get("content") or [{}])[0].get("text")})
    elif "rpc" in cmd:
        reply = rpc(cmd["rpc"])
        if reply is not None:
            sys.stdout.write(reply); sys.stdout.flush()
    elif "mcp_cwd" in cmd:
        start(cmd["mcp_cwd"])
    elif "sleep" in cmd:
        time.sleep(cmd["sleep"])
if mcp:
    mcp.stdin.close(); mcp.wait()
PY

# Runs a stand-in agent to the end of its commands (stdin) and prints its replies, the pid line first.
# agent_run AGENT SESSION CWD < commands
agent_run() { /usr/bin/python3 -I "$QA_AGENT_PY" "$@"; }

# Runs a stand-in agent in the background; its replies go to OUT. Sets AGENT_PID once it has started.
# agent_start OUT AGENT SESSION CWD < commands
agent_start() {
  local out=$1; shift
  cat > "$out.in"
  /usr/bin/python3 -I "$QA_AGENT_PY" "$@" < "$out.in" > "$out" &
  QA_BG_PIDS+=($!)
  wait_for 5 test -s "$out"
  AGENT_PID=$(head -1 "$out" | jq -r .pid)
}

# The Nth reply (1 = the first after the pid line) of a stand-in agent's output, as JSON.
reply() { sed -n "$(( $2 + 1 ))p" "$1"; }
# Waits until a background stand-in agent has printed N replies. wait_reply OUT N [SECONDS]
has_replies() { (( $(wc -l < "$1") > $2 )); }
wait_reply() { wait_for ${3:-10} has_replies "$1" "$2"; }

# A JSON tool call line for agent_run: call NAME ARGS-JSON
call() { local args=${2:-'{}'}; print -r -- "{\"call\":\"$1\",\"args\":$args}"; }

# A git repository with one commit. git_repo DIR
git_repo() {
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" -c user.name=qa -c user.email=qa@example.invalid commit -q --allow-empty -m init
}

# The path as Ambient keys a project: symlinks resolved, then /private dropped, as Foundation does.
real() { (cd "$1" && pwd -P | sed "s,^/private/,/,"); }

QA_BG_PIDS=()
QA_OWN_APP_PID=
qa_cleanup() {
  local pid
  for pid in $QA_BG_PIDS; do kill $pid 2>/dev/null; done
  [[ -n $QA_OWN_APP_PID ]] && own_app_stop
  return 0
}
trap qa_cleanup EXIT

# Starts another AmbientQA in AMBIENT_HOME=DIR (exported, so `ambient` talks to it) with this case's HOME.
# For "quit Ambient and open it again": the runner's app can't be restarted. own_app DIR
own_app() {
  export AMBIENT_HOME=$1
  mkdir -p "$AMBIENT_HOME"
  "$QA_APP/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
  QA_OWN_APP_PID=$!
  local end=$((SECONDS + 15))
  until /usr/bin/python3 -I -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])' "$AMBIENT_HOME/ambient.sock" 2>/dev/null; do
    kill -0 $QA_OWN_APP_PID 2>/dev/null || { echo "own_app: the QA app exited" >&2; exit 2; }
    (( SECONDS >= end )) && { echo "own_app: no socket within 15 s" >&2; exit 2; }
    sleep 0.2
  done
}

# Stops it by pid (SIGTERM: the app doesn't save on the way out, as quitting from its menu would).
own_app_stop() {
  [[ -n $QA_OWN_APP_PID ]] || return 0
  kill $QA_OWN_APP_PID 2>/dev/null
  for i in {1..25}; do kill -0 $QA_OWN_APP_PID 2>/dev/null || break; sleep 0.2; done
  kill -9 $QA_OWN_APP_PID 2>/dev/null
  QA_OWN_APP_PID=
  return 0
}

# Sleeps until EPOCHSECONDS reaches T. sleep_until T
sleep_until() { local d=$(( $1 - EPOCHSECONDS )); (( d > 0 )) && sleep $d; return 0; }
