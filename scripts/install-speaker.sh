#!/bin/zsh
# Installs the Ambient speaker driver, so "Ambient" shows up in Sound settings, then restarts Core Audio, which cuts
# the Mac's sound for a moment. macOS asks for an administrator's password.
#
#   scripts/install-speaker.sh            install build/AmbientSpeaker.driver (scripts/build-speaker.sh builds it)
#   scripts/install-speaker.sh --remove   take it out again
set -euo pipefail
cd "$(dirname "$0")/.."

HAL=/Library/Audio/Plug-Ins/HAL
DRIVER=AmbientSpeaker.driver
case "${1:-}" in
  "")
    [[ -d build/$DRIVER ]] || { echo "Build it first: scripts/build-speaker.sh" >&2; exit 1 }
    # macOS keeps root out of ~/Documents and the like, so root copies it from a folder of ours that it can read.
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE"' EXIT
    cp -R "build/$DRIVER" "$STAGE/"
    STEPS="rm -rf '$HAL/$DRIVER' && cp -R '$STAGE/$DRIVER' '$HAL/' && chown -R root:wheel '$HAL/$DRIVER'"
    ;;
  --remove) STEPS="rm -rf '$HAL/$DRIVER'" ;;
  *) echo "Unknown option: $1" >&2; exit 64 ;;
esac

# coreaudiod only looks for drivers when it starts, and launchd starts it again at once.
osascript -e "do shell script \"$STEPS && (killall coreaudiod || true)\" with administrator privileges" >/dev/null
sleep 2
if [[ -z ${1:-} ]]; then
  system_profiler SPAudioDataType | grep -q '^ *Ambient:$' && echo "Installed: Ambient is in Sound settings." \
    || { echo "Installed, but Core Audio doesn't list Ambient yet. Try: log show --last 2m --predicate 'process CONTAINS \"coreaudiod\" OR process CONTAINS \"Core Audio\"'" >&2; exit 1 }
else
  echo "Removed."
fi
