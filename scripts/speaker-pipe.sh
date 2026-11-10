#!/bin/zsh
# Plays what goes to the Ambient speaker on another Mac, through one ssh pipe: a test of streaming before the app does
# it. Pick "Ambient" in Sound settings (or in the app that plays), run this, and play something. ⌃C stops it. It says
# every 2 seconds how late the other Mac plays the sound, and tells macOS, so video here waits for it, even video
# already playing; each change of 30 ms or more costs about 90 ms of silence. ⏯ on the other Mac (its key, headphones,
# Control Center) pauses and plays whatever is playing here.
#
#   scripts/speaker-pipe.sh vivekyadav@daily                 until ⌃C
#   scripts/speaker-pipe.sh vivekyadav@daily --buffer 250    hold more there than 150 ms, if the sound breaks up
#   scripts/speaker-pipe.sh vivekyadav@daily --udp           the sound over UDP: a stall costs a gap, not a delay
#   build/speaker-pipe tone --seconds 5                       meanwhile, a test tone to the Ambient speaker
#
# It copies itself to /tmp/ambient-speaker-pipe on the other Mac, which needs nothing installed.
set -euo pipefail
cd "$(dirname "$0")/.."
(( $# )) || { echo "usage: scripts/speaker-pipe.sh HOST [--udp] [--buffer MS] [--seconds N] [--quiet] [--check HZ]" >&2; exit 64 }
HOST=$1; shift

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build
if [[ ! build/speaker-pipe -nt scripts/speaker-pipe.swift ]]; then
  xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14 -o build/speaker-pipe scripts/speaker-pipe.swift
fi
scp -q -o BatchMode=yes -o ConnectTimeout=10 build/speaker-pipe "$HOST:/tmp/ambient-speaker-pipe" \
  || { echo "Couldn't copy it to $HOST" >&2; exit 1 }
exec build/speaker-pipe send "$HOST" "$@"
