#!/bin/zsh
# Builds build/Ambient.app.
#
#   scripts/build-app.sh                 release build for this Mac, ad-hoc signed
#   scripts/build-app.sh --universal     arm64 + x86_64
#   scripts/build-app.sh --sign "Developer ID Application: Name (TEAMID)"
#   scripts/build-app.sh --run           build, then (re)launch the app
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=0 RUN=0 SIGN_ID="${AMBIENT_SIGN_ID:--}"
while (( $# )); do
  case "$1" in
    --universal) UNIVERSAL=1 ;;
    --run) RUN=1 ;;
    --sign) SIGN_ID="$2"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
  shift
done

VERSION=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/AmbientCore/Version.swift)
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}

ARCH_FLAGS=()
(( UNIVERSAL )) && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCH_FLAGS[@]}" --product AmbientApp
swift build -c release "${ARCH_FLAGS[@]}" --product ambient
# Where SwiftPM puts products differs between single- and multi-arch builds and between versions.
BIN=$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)

APP=build/Ambient.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/AmbientApp" "$APP/Contents/MacOS/Ambient"
cp "$BIN/ambient" "$APP/Contents/Helpers/ambient"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE" 2>/dev/null || true

# The icon is drawn by code; re-render only when the script changes.
ICNS=build/AppIcon.icns
if [[ ! -f $ICNS || scripts/make-icon.swift -nt $ICNS ]]; then
  ICONSET=build/AppIcon.iconset
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift scripts/make-icon.swift build/icon-1024.png
  for pt in 16 32 128 256 512; do
    sips -z $pt $pt build/icon-1024.png --out "$ICONSET/icon_${pt}x${pt}.png" >/dev/null
    sips -z $((pt * 2)) $((pt * 2)) build/icon-1024.png --out "$ICONSET/icon_${pt}x${pt}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICNS"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

# Sign inside-out: the helper, then the app. Hardened runtime and a timestamp for real identities.
SIGN_FLAGS=(--force --sign "$SIGN_ID")
if [[ $SIGN_ID != "-" ]]; then SIGN_FLAGS+=(--options runtime --timestamp); fi
codesign "${SIGN_FLAGS[@]}" --identifier com.viveky259259.Ambient.cli "$APP/Contents/Helpers/ambient"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION build $BUILD_NUMBER, signed: $SIGN_ID)"

if (( RUN )); then
  pkill -x Ambient 2>/dev/null && sleep 0.5 || true
  open "$APP"
fi
