#!/bin/zsh
# Builds a universal, Developer ID–signed, notarized and stapled DMG in dist/.
#
#   NOTARY_PROFILE=my-profile scripts/release.sh
#
# Environment:
#   SIGN_ID          signing identity name or SHA-1 (default: the first "Developer ID Application" identity)
#   NOTARY_PROFILE   keychain profile from `xcrun notarytool store-credentials` (default: ambient-notary)
#   SKIP_NOTARIZE=1  sign only, for a local dry run
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | awk '/Developer ID Application/ { print $2; exit }')}
NOTARY_PROFILE=${NOTARY_PROFILE:-ambient-notary}
VERSION=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/AmbientCore/Version.swift)
[[ -n $SIGN_ID ]] || { echo "No Developer ID Application identity found. Set SIGN_ID." >&2; exit 1; }

swift test
scripts/build-app.sh --universal --sign "$SIGN_ID"

APP=build/Ambient.app
mkdir -p dist
DMG=dist/Ambient-$VERSION.dmg
ZIP=dist/Ambient-$VERSION.zip
rm -f "$DMG" "$ZIP"

notarize() {
  [[ ${SKIP_NOTARIZE:-0} == 1 ]] && { echo "Skipping notarization of $1"; return; }
  echo "Notarizing $1…"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
}

# Notarize and staple the app itself, so it launches cleanly even when copied out of the DMG offline.
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
[[ ${SKIP_NOTARIZE:-0} == 1 ]] || xcrun stapler staple "$APP"

# A plain drag-to-Applications disk image.
STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Ambient.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Ambient $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
notarize "$DMG"
if [[ ${SKIP_NOTARIZE:-0} != 1 ]]; then
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -vv "$DMG"
  spctl --assess --type execute -vv "$APP"
fi

# The zip of the stapled app is handy for Homebrew and direct downloads.
rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
(cd dist && shasum -a 256 "Ambient-$VERSION.dmg" "Ambient-$VERSION.zip" > "Ambient-$VERSION.sha256")
echo "Release artifacts:"
ls -lh dist/Ambient-$VERSION.*
