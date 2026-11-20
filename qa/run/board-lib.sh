# Helpers for the task board cases (BRD-), sourced after lib.sh.
#
# The board's model settings live in the QA app's defaults and are read once at launch, and the defaults point at
# 127.0.0.1:5051, where this Mac's real local-agent gateway listens. So a board case that asks how the model runs
# (`ambient task model`, `ambient mcp`), turns summaries on, or needs tasks.json seeded before launch starts the QA app
# itself, with `# needs-app: no`: it takes the runner's lock like the runner does, and gives the app its model settings
# as launch arguments (the argument domain, which writes nothing to any defaults), always with the gateway URL of a
# fake gateway in the case folder, or a closed loopback port. Runtimes (Python, llama.cpp) and models are fakes in the
# case folder too: nothing here loads real weights or talks to the real gateway.

BOARD_BIN=$QA_ROOT/bin
BOARD_MODELS=$QA_ROOT/models
BOARD_TMP=$QA_ROOT/tmp
BOARD_LOCK=/tmp/ambient-qa.lock
mkdir -p "$BOARD_BIN" "$BOARD_MODELS" "$BOARD_TMP"
typeset -g BOARD_APP_PID="" BOARD_LOCKED="" BOARD_GW_PID="" BOARD_GW_PORT=""
# Discard port on loopback: nothing listens, so a probe fails at once instead of reaching anything real.
typeset -g BOARD_CLOSED_URL="http://127.0.0.1:9/mcp"

board_cleanup() {
  board_stop
  [[ -n $BOARD_GW_PID ]] && kill $BOARD_GW_PID 2>/dev/null
  # Fake model runtimes the app started and left (it was stopped without quitting).
  local pid
  for pid in $(cat "$QA_ROOT"/runtime-pids 2>/dev/null); do kill $pid 2>/dev/null; done
  [[ -n $BOARD_LOCKED ]] && [[ $(cat $BOARD_LOCK/pid 2>/dev/null) == $$ ]] && rm -rf $BOARD_LOCK
  BOARD_LOCKED=""
}
trap 'board_cleanup' EXIT
trap 'board_cleanup; exit 2' TERM INT HUP

# The runner's lock: one QA app at a time, across runners.
board_lock() {
  local pid
  until mkdir $BOARD_LOCK 2>/dev/null; do
    pid=$(cat $BOARD_LOCK/pid 2>/dev/null)
    if [[ -n $pid ]] && ! kill -0 $pid 2>/dev/null; then rm -rf $BOARD_LOCK; continue; fi
    sleep 0.5
  done
  print $$ > $BOARD_LOCK/pid
  BOARD_LOCKED=1
}

# Starts the QA app with board settings. board_app [key=value ...] with keys taskLLMEnabled, taskLLMMCPURL,
# taskLLMModelID, taskLLMModelPath, taskLLMPython, taskLLMReadTranscripts, taskLLMModelsVolume. BOARD_APP_PATH, when
# set, is the app's PATH (default: the case's fake runtimes, then this PATH). $BOARD_BIN/python3 is a fake Python with
# mlx-lm and mlx-vlm, so a model folder with no Python chosen never makes the app try a real one.
board_app() {
  [[ -n $BOARD_LOCKED ]] || board_lock
  typeset -A s=(
    taskLLMEnabled NO
    taskLLMMCPURL "${BOARD_GW_PORT:+http://127.0.0.1:$BOARD_GW_PORT/mcp}"
    taskLLMModelID hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit
    taskLLMModelPath ""
    taskLLMPython ""
    taskLLMReadTranscripts NO
    taskLLMModelsVolume /Volumes/Models
  )
  [[ -n ${s[taskLLMMCPURL]} ]] || s[taskLLMMCPURL]=$BOARD_CLOSED_URL
  local kv
  for kv in "$@"; do s[${kv%%=*}]=${kv#*=}; done
  [[ ${s[taskLLMMCPURL]} != (http|https)://(127.0.0.1|localhost|\[::1\]|0.0.0.0):5051* ]] || { echo "board_app: refusing the real gateway's port" >&2; exit 2; }
  local -a args=()
  # A value of "-" leaves the setting to the app's own defaults.
  for kv in ${(k)s}; do [[ ${s[$kv]} == - ]] || args+=(-$kv "${s[$kv]}"); done
  PATH=${BOARD_APP_PATH:-$BOARD_BIN:$PATH} TMPDIR=$BOARD_TMP/ \
    "$QA_APP/Contents/MacOS/AmbientQA" "${args[@]}" >/dev/null 2>&1 &
  BOARD_APP_PID=$!
  local end=$((SECONDS + 15))
  until ambient tasks >/dev/null 2>&1; do
    kill -0 $BOARD_APP_PID 2>/dev/null || { echo "the QA app exited at launch" >&2; exit 2; }
    (( SECONDS < end )) || { echo "the QA app did not answer within 15 s" >&2; exit 2; }
    sleep 0.2
  done
}

# Stops the app this script started, by pid (like the runner: TERM, then KILL). Keeps the lock for a relaunch.
board_stop() {
  [[ -n $BOARD_APP_PID ]] || return 0
  kill $BOARD_APP_PID 2>/dev/null
  local i
  for i in {1..15}; do kill -0 $BOARD_APP_PID 2>/dev/null || break; sleep 0.2; done
  kill -9 $BOARD_APP_PID 2>/dev/null
  wait $BOARD_APP_PID 2>/dev/null
  BOARD_APP_PID=""
}

# Board as JSON, and one task's field: task_get TITLE jq-filter-on-the-task
tasks_json() { ambient tasks --json; }
task_get() { ambient tasks --json | jq -r --arg t "$1" "[.[] | select(.title == \$t)][0] | $2"; }
task_count() { ambient tasks --json | jq length; }

# A fake local-agent gateway (MCP over streamable HTTP) on a free loopback port. It answers from $QA_ROOT/gw.json,
# read on every request (models, storage, reply), and logs every call to $QA_ROOT/gw.log, one JSON line each.
fake_gateway() { # [port]
  [[ -f $QA_ROOT/gw.json ]] || gw_config '[]'
  rm -f "$QA_ROOT/gw.port"
  /usr/bin/python3 -I - "$QA_ROOT" "${1:-0}" <<'PY' &
import json, os, sys, time, uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
root = sys.argv[1]
jobs = {}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        cfg = json.load(open(os.path.join(root, "gw.json")))
        method = body.get("method")
        params = body.get("params") or {}
        with open(os.path.join(root, "gw.log"), "a") as f:
            f.write(json.dumps({"method": method, "tool": params.get("name"), "arguments": params.get("arguments")}) + "\n")
        if "id" not in body:
            self.send_response(202); self.end_headers(); return
        result = {}
        if method == "initialize":
            result = {"protocolVersion": "2025-03-26", "capabilities": {"tools": {}}, "serverInfo": {"name": "fake-local-agent", "version": "0"}}
        elif method == "tools/call":
            name, args = params.get("name"), params.get("arguments") or {}
            if name == "model_storage_status": out = cfg.get("storage", {"external_volume_available": True})
            elif name == "list_models": out = {"models": cfg.get("models", [])}
            elif name == "submit_inference":
                jid = "job-" + uuid.uuid4().hex[:8]; jobs[jid] = time.time(); out = {"id": jid, "status": "queued"}
            elif name == "get_job":
                # A job takes job_seconds (default none) to finish, then replies with the configured text.
                if time.time() - jobs.get(args.get("job_id"), 0) < cfg.get("job_seconds", 0):
                    out = {"id": args.get("job_id"), "status": "running"}
                else:
                    out = {"id": args.get("job_id"), "status": "completed", "result": {"message": {"role": "assistant", "content": cfg.get("reply", "")}}}
            else: out = {}
            result = {"content": [{"type": "text", "text": json.dumps(out)}]}
        data = ("event: message\ndata: " + json.dumps({"jsonrpc": "2.0", "id": body["id"], "result": result}) + "\n\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Mcp-Session-Id", "fake-session")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
HTTPServer.allow_reuse_address = True
s = HTTPServer(("127.0.0.1", int(sys.argv[2])), H)
open(os.path.join(root, "gw.port.tmp"), "w").write(str(s.server_port))
os.rename(os.path.join(root, "gw.port.tmp"), os.path.join(root, "gw.port"))
s.serve_forever()
PY
  BOARD_GW_PID=$!
  wait_for 5 test -s "$QA_ROOT/gw.port"
  BOARD_GW_PORT=$(cat "$QA_ROOT/gw.port")
}

# gw_config MODELS-JSON [STORAGE-JSON] [REPLY-TEXT]
gw_config() {
  local storage='{"external_volume_available":true}'
  local reply='{"title":"QA model title","summary":"QA summary from the fake model","status":"inProgress"}'
  [[ -n ${2:-} ]] && storage=$2
  [[ -n ${3:-} ]] && reply=$3
  jq -n --argjson models "$1" --argjson storage "$storage" --arg reply "$reply" \
    --argjson job "${GW_JOB_SECONDS:-0}" '{models: $models, storage: $storage, reply: $reply, job_seconds: $job}' > "$QA_ROOT/gw.json.tmp" && mv "$QA_ROOT/gw.json.tmp" "$QA_ROOT/gw.json"
}
gw_calls() { local n; n=$(grep -c "\"tool\": \"$1\"" "$QA_ROOT/gw.log" 2>/dev/null); print ${n:-0}; }

# A gateway inventory entry: gw_model ID KIND [PATH]
gw_model() { jq -nc --arg id "$1" --arg kind "$2" --arg path "${3:-}" '{id: $id, kind: $kind} + (if $path == "" then {} else {path: $path, runtime_available: true} end)'; }

# A fake Python for MLX runs: answers the app's import probe (failing for a module while $QA_ROOT/fakepy-no-<module>
# exists), and as a loaded model answers each request line on stdin with a marked reply. Logs to $QA_ROOT/fakepy.log.
fake_python() { # path
  mkdir -p "${1:h}"
  cat > "$1" <<PY
#!/usr/bin/python3 -I
import json, os, sys
root = "$QA_ROOT"
def log(**kv):
    with open(os.path.join(root, "fakepy.log"), "a") as f: f.write(json.dumps(kv) + "\n")
if len(sys.argv) > 2 and "find_spec" in sys.argv[2]:
    module = sys.argv[2].split("find_spec('")[1].split("'")[0]
    ok = not os.path.exists(os.path.join(root, "fakepy-no-" + module))
    log(kind="probe", python=sys.argv[0], module=module, ok=ok)
    sys.exit(0 if ok else 1)
with open(os.path.join(root, "runtime-pids"), "a") as f: f.write(str(os.getpid()) + "\n")
env = {k: os.environ.get(k) for k in ("HF_HUB_OFFLINE", "TRANSFORMERS_OFFLINE", "HF_DATASETS_OFFLINE")}
log(kind="start", python=sys.argv[0], pid=os.getpid(), argv=sys.argv[1:], cwd=os.getcwd(), env=env)
reply = json.load(open(os.path.join(root, "gw.json"))).get("reply", "") if os.path.exists(os.path.join(root, "gw.json")) else ""
while True:
    line = sys.stdin.readline()
    if not line: break
    req = json.loads(line)
    log(kind="request", pid=os.getpid(), path=req["path"], vision=req["vision"], prompt=req["prompt"])
    sys.stdout.write("some runtime noise\n\nAMBIENT_RESULT " + json.dumps({"text": reply}) + "\n"); sys.stdout.flush()
log(kind="exit", pid=os.getpid())
PY
  chmod +x "$1"
}

# A fake llama.cpp completion tool: logs its arguments and the prompt file's mode, then prints the reply.
fake_llama() { # path
  mkdir -p "${1:h}"
  cat > "$1" <<PY
#!/usr/bin/python3 -I
import json, os, stat, sys
root = "$QA_ROOT"
args = sys.argv[1:]
pf = args[args.index("-f") + 1] if "-f" in args else None
info = {"argv": args, "prompt_file": pf, "pid": os.getpid()}
if pf and os.path.exists(pf):
    st = os.stat(pf); info["mode"] = oct(stat.S_IMODE(st.st_mode)); info["prompt"] = open(pf).read()
    info["tmp_listing"] = sorted(n for n in os.listdir(os.path.dirname(pf)) if n.startswith("ambient-prompt-"))
with open(os.path.join(root, "llama.log"), "a") as f: f.write(json.dumps(info) + "\n")
print(json.load(open(os.path.join(root, "gw.json"))).get("reply", "") if os.path.exists(os.path.join(root, "gw.json")) else "")
PY
  chmod +x "$1"
}

# Model folders made of the right file names and an empty weights file: nothing a runtime could load.
mlx_folder() { # path [extra-config-json]
  mkdir -p "$1"
  local extra='{}'
  [[ -n ${2:-} ]] && extra=$2
  jq -n --argjson extra "$extra" '{model_type: "qwen2", hidden_size: 64} + $extra' > "$1/config.json"
  : > "$1/model.safetensors"
}

# The CLI marks errors with "✗ " and successes with "✓ ": the cases quote the text after the mark.
unmark() { print -r -- "${1#[✗✓!] }"; }

fake_python "$BOARD_BIN/python3"

# Seconds since 2001-01-01, the dates tasks.json holds: ref_date SECONDS-FROM-NOW (negative for the past).
ref_date() { print $(( EPOCHREALTIME - 978307200 + $1 )); }
# One agent-made task for a seeded tasks.json: seed_task ID TITLE STATUS UPDATED-REF [project] [manual]
seed_task() {
  jq -nc --arg id "$1" --arg title "$2" --arg status "$3" --argjson at "$4" --arg project "${5:-}" --argjson manual "${6:-false}" \
    '{id: $id, title: $title, status: $status, summarySource: "heuristic", agents: ["claude"], sessionIds: [],
      manual: $manual, createdAt: $at, updatedAt: $at} + (if $project == "" then {} else {project: $project} end)'
}
# Writes tasks.json from task objects, one per line on stdin.
seed_tasks() { mkdir -p "$AMBIENT_HOME"; jq -s '{version: 1, tasks: .}' > "$AMBIENT_HOME/tasks.json"; }
