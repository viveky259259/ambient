#!/bin/zsh
# Builds the offline voice helper into build/ambient-voice/ and zips it as dist/ambient-voice-<version>.zip.
#
#   scripts/build-voice.sh                       ad-hoc signed, for local testing
#   scripts/build-voice.sh --sign <SHA-1>        Developer ID, hardened runtime
#   NOTARY_PROFILE=… scripts/build-voice.sh --sign <SHA-1> --notarize
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_ID="-" NOTARIZE=0
while (( $# )); do
  case "$1" in
    --sign) SIGN_ID="$2"; shift ;;
    --notarize) NOTARIZE=1 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
  shift
done

VERSION=$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/AmbientCore/Speech/VoicePackPin.swift)
DD=build/voice-dd
# MLX's Metal shaders are compiled only by Xcode's build system, not by `swift build`.
LOG=build/voice-build.log
mkdir -p build
if ! (cd Voice && xcodebuild -scheme AmbientVoice -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "../$DD" -skipPackagePluginValidation -skipMacroValidation build) > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u >&2 || tail -20 "$LOG" >&2
  echo "xcodebuild failed; full log in $LOG" >&2
  exit 1
fi
PRODUCTS=$DD/Build/Products/Release

OUT=build/ambient-voice
rm -rf "$OUT" && mkdir -p "$OUT"
cp "$PRODUCTS/ambient-voice" "$OUT/"
# SwiftPM resource bundles (MLX's metallib, Kokoro's config, Misaki's lexicons) are found next to the executable.
for b in "$PRODUCTS"/*.bundle(N); do cp -R "$b" "$OUT/"; done
if [[ -d $PRODUCTS/PackageFrameworks ]]; then
  mkdir -p "$OUT/Frameworks"
  cp -R "$PRODUCTS"/PackageFrameworks/*.framework "$OUT/Frameworks/"
  install_name_tool -add_rpath @executable_path/Frameworks "$OUT/ambient-voice" 2>/dev/null || true
fi

# Each library's own license travels with the helper, and so do Ambient's notices.
mkdir -p "$OUT/licenses"
for dir in "$DD"/SourcePackages/checkouts/*(N/); do
  for f in "$dir"/LICENSE(N) "$dir"/LICENSE.txt(N) "$dir"/LICENSE.md(N); do cp "$f" "$OUT/licenses/${dir:t}.txt"; break; done
done
cp THIRD_PARTY_NOTICES.md "$OUT/"

SIGN_FLAGS=(--force --sign "$SIGN_ID")
[[ $SIGN_ID != "-" ]] && SIGN_FLAGS+=(--options runtime --timestamp)
for f in "$OUT"/Frameworks/*.framework(N); do codesign "${SIGN_FLAGS[@]}" "$f"; done
codesign "${SIGN_FLAGS[@]}" --identifier com.viveky259259.Ambient.voice "$OUT/ambient-voice"
codesign --verify --strict "$OUT/ambient-voice"

mkdir -p dist
ZIP=dist/ambient-voice-$VERSION.zip
rm -f "$ZIP"
ditto -c -k --keepParent "$OUT" "$ZIP"
if (( NOTARIZE )); then
  xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:?set NOTARY_PROFILE}" --wait --timeout 30m
fi
echo "Built $ZIP ($(du -h "$ZIP" | cut -f1), sha256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1), signed: $SIGN_ID)"
