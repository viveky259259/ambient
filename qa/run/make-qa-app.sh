#!/bin/zsh
# Turns build/Ambient.app into build/AmbientQA.app: the same code under its own bundle id and
# executable name, so it keeps its own settings domain and can run beside an installed Ambient
# without either one touching the other. Build the app first with scripts/build-app.sh.
#
#   qa/run/make-qa-app.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

SRC=build/Ambient.app
DEST=build/AmbientQA.app
[[ -d $SRC ]] || { echo "No $SRC. Run scripts/build-app.sh first." >&2; exit 1; }

rm -rf "$DEST"
cp -R "$SRC" "$DEST"
mv "$DEST/Contents/MacOS/Ambient" "$DEST/Contents/MacOS/AmbientQA"
PLIST="$DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.viveky259259.Ambient.qa" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable AmbientQA" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName AmbientQA" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName AmbientQA" "$PLIST" 2>/dev/null || true

# Ad-hoc signatures, inside out, as scripts/build-app.sh signs them.
codesign --force --sign - --identifier com.viveky259259.Ambient.qa.cli "$DEST/Contents/Helpers/ambient"
codesign --force --sign - --identifier com.viveky259259.Ambient.qa.speaker-stream \
  --entitlements Resources/AmbientSpeaker.entitlements "$DEST/Contents/Helpers/ambient-speaker"
codesign --force --sign - --entitlements Resources/Ambient.entitlements "$DEST"
codesign --verify --strict "$DEST"
echo "Built $DEST ($("$DEST/Contents/Helpers/ambient" version))"
