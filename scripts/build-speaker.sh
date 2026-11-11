#!/bin/zsh
# Tests the Ambient speaker driver, then builds build/AmbientSpeaker.driver. scripts/install-speaker.sh installs it.
#
#   scripts/build-speaker.sh                 ad-hoc signed, for this Mac
#   scripts/build-speaker.sh --sign "Developer ID Application: Name (TEAMID)"
#   scripts/build-speaker.sh --if-needed     only if the driver, its number or its signature would change
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="${AMBIENT_SIGN_ID:--}" IF_NEEDED=0
while (( $# )); do
  case "$1" in
    --sign) SIGN_ID="$2"; shift ;;
    --if-needed) IF_NEEDED=1 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
  shift
done

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SRC=Drivers/AmbientSpeaker
DRIVER=build/AmbientSpeaker.driver
STAMP=build/AmbientSpeaker.driver.stamp
CFLAGS=(-std=c17 -Wall -Wextra -Werror -fvisibility=hidden -mmacosx-version-min=14.0)
mkdir -p build

VERSION=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/AmbientCore/Version.swift)
# The driver's own number: the commits up to its last change. Each app carries the driver, and offers to install it
# when it's newer than the one installed, so a new app with the same driver mustn't look newer.
BUILD_NUMBER=$(git rev-list --count "$(git log -1 --format=%H -- "$SRC")" 2>/dev/null || echo 1)
BUILT_AS="$SIGN_ID|$VERSION|$BUILD_NUMBER"
if (( IF_NEEDED )) && [[ -d $DRIVER && -f $STAMP && $(<$STAMP) == "$BUILT_AS" ]] \
  && [[ -z $(find "$SRC" "$0" -newer "$STAMP" -print -quit) ]]; then
  echo "$DRIVER $VERSION ($BUILD_NUMBER) is up to date"
  exit 0
fi

xcrun clang "${CFLAGS[@]}" -O1 -g -fsanitize=address,undefined -o build/speaker-tests \
  "$SRC/AmbientSpeaker.c" "$SRC/Tests.c" -framework CoreFoundation
build/speaker-tests

rm -rf "$DRIVER" "$STAMP"
mkdir -p "$DRIVER/Contents/MacOS"
xcrun clang "${CFLAGS[@]}" -O2 -arch arm64 -arch x86_64 -bundle -o "$DRIVER/Contents/MacOS/AmbientSpeaker" \
  "$SRC/AmbientSpeaker.c" -framework CoreFoundation
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" "$SRC/Info.plist" > "$DRIVER/Contents/Info.plist"
plutil -lint -s "$DRIVER/Contents/Info.plist"

# coreaudiod finds the driver by the factory Info.plist names, so it must be the one symbol the bundle exports.
EXPORTED=$(nm -gU -arch arm64 "$DRIVER/Contents/MacOS/AmbientSpeaker" | awk '{ print $NF }')
[[ $EXPORTED == _AmbientSpeaker_Create ]] || { echo "Unexpected exports: $EXPORTED" >&2; exit 1; }

SIGN_FLAGS=(--force --sign "$SIGN_ID")
if [[ $SIGN_ID != "-" ]]; then SIGN_FLAGS+=(--options runtime --timestamp); fi
codesign "${SIGN_FLAGS[@]}" "$DRIVER"
codesign --verify --strict "$DRIVER"

xcrun clang "${CFLAGS[@]}" -O1 -o build/load-speaker "$SRC/Load.c" -framework CoreFoundation
build/load-speaker "$DRIVER"
print -r -- "$BUILT_AS" > "$STAMP"
echo "Built $DRIVER $VERSION ($BUILD_NUMBER)"
