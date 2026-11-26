#!/bin/zsh
# Downloads the offline voice's model files into a folder and checks every hash, for building and testing the
# helper without going through the app.
#
#   scripts/fetch-voice-pack.sh build/voice-pack
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=${1:?usage: scripts/fetch-voice-pack.sh <folder>}
mkdir -p "$DEST/voices"
swift run -q ambient voice-files | while read -r rel url sha; do
  file="$DEST/$rel"
  if [[ ! -f $file ]] || [[ $(shasum -a 256 "$file" | cut -d' ' -f1) != "$sha" ]]; then
    echo "Downloading $rel"
    curl -fL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  [[ $(shasum -a 256 "$file" | cut -d' ' -f1) == "$sha" ]] || { echo "Hash mismatch: $rel" >&2; exit 1; }
done
echo "Voice pack ready in $DEST"
