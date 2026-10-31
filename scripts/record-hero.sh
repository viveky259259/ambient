#!/bin/zsh
# Records the README's hero GIF: about ten seconds of the real notch island going through its states.
#
#   scripts/record-hero.sh [path/to/Ambient.app] [docs/assets/island.gif]
#
# Uses a separate copy of the app (own bundle id, preferences and home folder), fed demo sessions through its own
# socket, so the Ambient you use and your real sessions aren't involved. It records the top centre of the main display:
# first clear what's under the notch (a plain wallpaper, no windows there), since the open island's glass shows it.
# Your terminal needs Screen Recording permission. Needs ffmpeg (brew install ffmpeg).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=${1:-build/Ambient.app}
OUT=${2:-docs/assets/island.gif}
ID=com.viveky259259.Ambient.hero
[[ -d $APP ]] || { echo "No app at $APP; run scripts/build-app.sh first." >&2; exit 66; }
command -v ffmpeg >/dev/null || { echo "Needs ffmpeg: brew install ffmpeg" >&2; exit 69; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ambient-hero.XXXX")
COPY="$WORK/Ambient Hero.app"
PID=""
cleanup() {
  [[ -n $PID ]] && kill $PID 2>/dev/null || true
  defaults delete $ID >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$ID.plist"
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

cp -R "$APP" "$COPY"
plutil -replace CFBundleIdentifier -string $ID "$COPY/Contents/Info.plist"
codesign --force --sign - "$COPY" 2>/dev/null
CLI="$COPY/Contents/Helpers/ambient"
mkdir -p "$WORK/home"
for key in setupCompleted islandShowsWorking; do defaults write $ID $key -bool true; done
for key in notificationsEnabled soundsEnabled dockGlowEnabled wallpaperEnabled petEnabled; do defaults write $ID $key -bool false; done

HOME="$WORK/home" "$COPY/Contents/MacOS/Ambient" >/dev/null 2>&1 &
PID=$!
sleep 4

# The island's open card is at most 440 points wide and 112 tall below the notch: record a little more.
# The island sits on the display with the menu bar, the first screen, whose top-left corner is 0,0.
WIDTH=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSScreen.screens.objectAtIndex(0).frame.size.width')
WIDTH=${WIDTH%.*}
X=$(( (WIDTH - 560) / 2 ))
screencapture -x -v -V 11 -R "$X,0,560,170" "$WORK/island.mov" &
REC=$!
emit() { HOME="$WORK/home" "$CLI" emit "$@" >/dev/null; }
sleep 0.5
emit working --agent claude --project api --message "npm test"
sleep 2
emit working --agent codex --project web --message "cargo build"
sleep 2
emit waiting --agent claude --project api --message "Bash: rm -rf build"
sleep 3
emit done --agent codex --project web --message "All 42 tests pass."
sleep 3.5
wait $REC

mkdir -p "$(dirname "$OUT")"
ffmpeg -loglevel error -y -i "$WORK/island.mov" \
  -vf "fps=20,scale=560:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
  "$OUT"
echo "Wrote $OUT ($(du -h "$OUT" | cut -f1)). Check it, then add it to the top of the README."
