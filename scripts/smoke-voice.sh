#!/bin/zsh
# Runs build/ambient-voice once from another folder and checks that it answers with at least a second of audio.
#
#   scripts/smoke-voice.sh build/voice-pack
set -euo pipefail
cd "$(dirname "$0")/.."
PACK=$(cd "${1:?usage: scripts/smoke-voice.sh <pack folder>}" && pwd)
HELPER=$PWD/build/ambient-voice/ambient-voice
OUT=$PWD/build/voice-smoke.bin
printf '%s\n' '{"id":"smoke","speed":1,"text":"Hello from Ambient. This is the offline voice.","voice":"af_heart"}' \
  | (cd / && "$HELPER" "$PACK") > "$OUT"
python3 -I - "$OUT" <<'EOF'
import json, struct, sys
data = open(sys.argv[1], "rb").read()
header, rest = data.split(b"\n", 1)
h = json.loads(header)
assert "error" not in h, h
assert h["sampleRate"] == 24000, h
samples = 0
while True:
    (n,) = struct.unpack("<I", rest[:4]); rest = rest[4:]
    if n == 0: break
    samples += n // 4; rest = rest[n:]
assert samples >= 24000, samples
print(f"ok: {samples / 24000:.1f} s of audio")
EOF
