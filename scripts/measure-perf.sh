#!/bin/zsh
# Measures what Ambient costs this Mac, feature by feature. Everything stays on this Mac: no telemetry.
#
#   scripts/measure-perf.sh [--board TASKS] [path/to/Ambient.app] [seconds per scenario]
#
# Runs a separate copy of the app with its own bundle id, preferences and home folder, so the Ambient you use and its
# settings are left alone. Sounds and notifications are off in the copy. "Agents working" scenarios feed it a tool
# event every two seconds through its own socket. Prints a Markdown table: average and peak CPU (percent of one core),
# macOS's energy impact, and memory.
#
# --board measures the task board instead, on a made-up board of that many tasks shaped like a long-lived real one,
# with no window open, Settings › Board open, Settings closed again, and the Task Board window open. The copy opens
# its windows itself, so this needs a local build (scripts/build-app.sh), and they appear on screen while it runs.
set -euo pipefail
cd "$(dirname "$0")/.."

BOARD=0
if [[ ${1:-} == --board ]]; then BOARD=${2:?--board needs a number of tasks}; shift 2; fi
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
defaults write $ID settingsPane board

cpu_seconds() { ps -o time= -p $1 | awk -F'[:.]' '{ if (NF == 4) print $1*3600 + $2*60 + $3 + $4/100; else print $1*60 + $2 + $3/100 }'; }

# A fresh board for each scenario, as the app saves what it changes: TASKS tasks in the proportions of a real board
# of 4,193 (two thirds done, a quarter in progress, a few blocked), nearly all with a model's summary.
seed_board() {
  mkdir -p "$WORK/home/.ambient"
  awk -v n=$BOARD -v now=$(( $(date +%s) - 978307200 )) 'BEGIN {
    srand(7); split("claude codex cursor gemini opencode", agents, " ")
    split("ambient site voice remote-shim notes infra", projects, " ")
    printf "{\"version\":1,\"tasks\":["
    for (i = 0; i < n; i++) {
      r = i % 1000
      status = r < 4 ? "blocked" : r < 88 ? "backlog" : r < 332 ? "inProgress" : "done"
      agent = agents[int(rand() * 5) + 1]; at = now - rand() * 30 * 86400
      printf "%s{\"id\":\"task-%08x\",\"title\":\"Board task %d\",\"status\":\"%s\",", (i ? "," : ""), i, i, status
      printf "\"summary\":\"Made the change, ran the tests, and noted what still needs a look before it ships.\","
      printf "\"summarySource\":\"localLLM\",\"summarizedAt\":%f,\"project\":\"%s\",", at, projects[int(rand() * 6) + 1]
      printf "\"agents\":[\"%s\"],\"sessionIds\":[\"%s:s%08x\"],\"lastSessionId\":\"%s:s%08x\",", agent, agent, i, agent, i
      printf "\"manual\":false,\"createdAt\":%f,\"updatedAt\":%f}", at - 600, at
    }
    print "]}"
  }' > "$WORK/home/.ambient/tasks.json"
}

# name, Dock glow, wallpaper, pet, agents working (1/0), window to open (board scenarios)
scenario() {
  local name=$1 glow=$2 wallpaper=$3 pet=$4 active=$5 window=${6:-}
  defaults write $ID islandEnabled -bool true
  defaults write $ID dockGlowEnabled -bool $glow
  defaults write $ID wallpaperEnabled -bool $wallpaper
  defaults write $ID petEnabled -bool $pet
  (( BOARD )) && seed_board
  HOME="$WORK/home" AMBIENT_PERF_OPEN=$window "$COPY/Contents/MacOS/Ambient" >/dev/null 2>&1 &
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
    END { if (avg + 0 > peak) peak = avg + 0  # the average comes from ps, the samples from top
      printf "| %s | %.1f%% | %.1f%% | %.1f | %s |\n", name, avg, peak, (n ? power / n : 0), mem }'
}

echo "| Scenario | CPU, average | CPU, peak | Energy impact | Memory |"
echo "| --- | --- | --- | --- | --- |"
if (( BOARD )); then
  scenario "$BOARD tasks, no window open, agents working" false false false 1
  scenario "$BOARD tasks, Settings › Board open, agents working" false false false 1 settings
  scenario "$BOARD tasks, Settings closed on Board, agents working" false false false 1 settings-closed
  scenario "$BOARD tasks, Task Board window open, agents working" false false false 1 board
  echo
  echo "$(sysctl -n machdep.cpu.brand_string), macOS $(sw_vers -productVersion), $DURATION s per scenario."
  exit 0
fi
scenario "Island only, nothing happening" false false false 0
scenario "Island only, agents working" false false false 1
scenario "Island and Dock glow, agents working" true false false 1
scenario "Island and living wallpaper, nothing happening" false true false 0
scenario "Island and desktop pet, nothing happening" false false true 0
scenario "Everything on, agents working" true true true 1
echo
echo "$(sysctl -n machdep.cpu.brand_string), macOS $(sw_vers -productVersion), $DURATION s per scenario."
