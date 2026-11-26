#!/bin/zsh
# Pins a published helper zip into the app: its SHA-256 and size go into VoicePackPin.swift.
#
#   scripts/pin-voice-helper.sh dist/ambient-voice-1.zip
set -euo pipefail
cd "$(dirname "$0")/.."
ZIP=${1:?usage: scripts/pin-voice-helper.sh <zip>}
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
BYTES=$(stat -f %z "$ZIP")
FILE=Sources/AmbientCore/Speech/VoicePackPin.swift
sed -i '' -e "s/helperSHA256 = \".*\"/helperSHA256 = \"$SHA\"/" -e "s/helperBytes: Int64 = .*/helperBytes: Int64 = $BYTES/" "$FILE"
grep -E 'helperSHA256|helperBytes' "$FILE"
