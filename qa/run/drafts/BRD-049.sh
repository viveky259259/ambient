#!/bin/zsh
# BRD-049 · `ambient task model` shows how the board runs its model.
# needs-app: no
# timeout: 300
# Starts the QA app itself with a fake local-agent gateway (see qa/run/board-lib.sh); the MLX folder and the Python
# with mlx-lm are fakes in the case folder, the Python first on the app's PATH and not on the shell's.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

ID=hf:mlx-community/Qwen2.5-0.5B-Instruct-4bit
gw_config "[$(gw_model $ID chat)]"
fake_gateway
fake_python "$BOARD_BIN/python3"
board_app

# Step 1: summaries off, no model path.
out=$(ambient task model); code=$?
assert_eq "$code" 0 "ambient task model exit code"
print -r -- "$out" | sed 's/^/    /'
lines=("${(@f)out}")
assert_eq "${lines[1]}" "Board model" "first line"
assert_eq "${lines[2]}" "  summaries      off" "summaries line"
assert_eq "${lines[3]}" "  model_id       $ID" "model_id line"
# Resolved as if summaries were on: the gateway lists the id, so it would run there.
assert_eq "${lines[4]}" "  runs           via local-agent" "runs line"
assert_eq "${lines[5]}" "  gateway_model  $ID (chat)" "gateway_model line"
assert_eq "${lines[6]}" "  status         Local LLM ready" "status line"

# Step 2: an MLX folder set.
MODEL=$BOARD_MODELS/Qwen2.5-0.5B-Instruct-4bit
mlx_folder "$MODEL"
ambient task model "$MODEL" >/dev/null || fail "setting the model path failed"
json=$(ambient task model --json); code=$?
assert_eq "$code" 0 "ambient task model --json exit code"
print -r -- "$json" | sed 's/^/    /'
assert_eq "$(print -r -- $json | jq -r 'keys | join(",")')" "format,model_path,runs,runtime,status,summaries" "JSON keys"
assert_eq "$(print -r -- $json | jq -r .summaries)" off "summaries"
assert_eq "$(print -r -- $json | jq -r .model_path)" "$MODEL" "model_path"
assert_eq "$(print -r -- $json | jq -r .format)" "MLX text model" "format"
assert_eq "$(print -r -- $json | jq -r .runs)" "directly with mlx-lm" "runs"
# The app's Python (first on the app's PATH), not the shell's.
assert_eq "$(print -r -- $json | jq -r .runtime)" "$BOARD_BIN/python3" "runtime"
assert_ne "$(whence -p python3)" "$BOARD_BIN/python3" "the shell's python3"
assert_eq "$(print -r -- $json | jq -r .status)" "Local LLM ready" "status"

# Step 3: Ambient not running.
board_stop
out=$(ambient task model 2>&1); code=$?; out=$(unmark "$out")
assert_eq "$code" 1 "exit code with Ambient closed"
assert_eq "$out" "Ambient isn't running. Open Ambient.app, then try again." "message with Ambient closed"
