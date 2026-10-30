#!/bin/zsh
# Measures what Ambient costs this Mac, feature by feature. Everything stays on this Mac: no telemetry.
#
#   scripts/measure-perf.sh [path/to/Ambient.app] [seconds per scenario]
#
# Runs a separate copy of the app with its own bundle id, preferences and home folder, so the Ambient you use and its
# settings are left alone. Sounds and notifications are off in the copy. "Agents working" scenarios feed it a tool
# event every two seconds through its own socket. Prints a Markdown table: average and peak CPU (percent of one core),
# macOS's energy impact, and memory.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=${1:-build/Ambient.app}
DURATION=${2:-60}
ID=com.viveky259259.Ambient.perf
[[ -d $APP ]] || { echo "No app at $APP; run scripts/build-app.sh first." >&2; exit 66; }

# $TMPDIR keeps the socket path under macOS's 104-byte limit.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ambient-perf.XXXX")
COPY="$WORK/Ambient Perf.app"
PID="" FEEDER=""
cleanup() {
  # The event feeder first, or an interrupted run leaves it looping.
  [[ -n $FEEDER ]] && kill $FEEDER 2>/dev/null || true
  [[ -n $PID ]] && kill $PID 2>/dev/null || true
  defaults delete $ID >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$ID.plist"
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

cp -R "$APP" "$COPY"
plutil -replace CFBundleIdentifier -string $ID "$COPY/Contents/Info.plist"
plutil -replace CFBundleName -string "Ambient Perf" "$COPY/Contents/Info.plist"
codesign --force --sign - "$COPY" 2>/dev/null
CLI="$COPY/Contents/Helpers/ambient"
mkdir -p "$WORK/home"

defaults write $ID setupCompleted -bool true
defaults write $ID notificationsEnabled -bool false
defaults write $ID soundsEnabled -bool false
defaults write $ID wallpaperOnLockScreen -bool false
defaults write $ID wallpaperCalendar -bool false
defaults write $ID wallpaperScene garden
defaults write $ID islandShowsWorking -bool true

cpu_seconds() { ps -o time= -p $1 | awk -F'[:.]' '{ if (NF == 4) print $1*3600 + $2*60 + $3 + $4/100; else print $1*60 + $2 + $3/100 }'; }

# name, Dock glow, wallpaper, pet, agents working (1/0)
scenario() {
  local name=$1 glow=$2 wallpaper=$3 pet=$4 active=$5
  defaults write $ID islandEnabled -bool true
  defaults write $ID dockGlowEnabled -bool $glow
  defaults write $ID wallpaperEnabled -bool $wallpaper
  defaults write $ID petEnabled -bool $pet
  HOME="$WORK/home" "$COPY/Contents/MacOS/Ambient" >/dev/null 2>&1 &
  PID=$!
  sleep 8
  if (( active )); then
    ( while true; do HOME="$WORK/home" "$CLI" emit working --agent claude --project perf --message "npm test" >/dev/null 2>&1; sleep 2; done ) &
    FEEDER=$!
    sleep 4
  fi
  local c0=$(cpu_seconds $PID) t0=$(date +%s)
  local samples=$(top -l $(( DURATION / 5 + 1 )) -s 5 -pid $PID -stats pid,cpu,power,mem 2>/dev/null | awk -v p=$PID '$1 == p { print $2, $3, $4 }' | tail -n +2)
  local c1=$(cpu_seconds $PID) t1=$(date +%s)
  [[ -n $FEEDER ]] && kill $FEEDER 2>/dev/null; FEEDER=""
  kill $PID 2>/dev/null; wait $PID 2>/dev/null || true; PID=""
  print -r -- "$samples" | awk -v name="$name" -v avg=$(( (c1 - c0) / (t1 - t0) * 100 )) '
    { if ($1 > peak) peak = $1; power += $2; n++; mem = $3 }
    END { printf "| %s | %.1f%% | %.1f%% | %.1f | %s |\n", name, avg, peak, (n ? power / n : 0), mem }'
}

echo "| Scenario | CPU, average | CPU, peak | Energy impact | Memory |"
echo "| --- | --- | --- | --- | --- |"
scenario "Island only, nothing happening" false false false 0
scenario "Island only, agents working" false false false 1
scenario "Island and Dock glow, agents working" true false false 1
scenario "Island and living wallpaper, nothing happening" false true false 0
scenario "Island and desktop pet, nothing happening" false false true 0
scenario "Everything on, agents working" true true true 1
echo
echo "$(sysctl -n machdep.cpu.brand_string), macOS $(sw_vers -productVersion), $DURATION s per scenario."
