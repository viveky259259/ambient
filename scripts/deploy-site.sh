#!/bin/zsh
# Deploys site/ to Netlify with the current release's DMG. In CI, NETLIFY_AUTH_TOKEN and NETLIFY_SITE_ID
# stand in for the local `netlify login` and link.
#
#   scripts/deploy-site.sh           draft deploy (a unique preview URL)
#   scripts/deploy-site.sh --prod    production (yaml.cafe)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/AmbientBase/Version.swift)
DMG=dist/Ambient-$VERSION.dmg
[[ -f $DMG ]] || { echo "Missing $DMG. Run scripts/release.sh first." >&2; exit 1; }
scripts/check-site.sh "$VERSION"

# The site states the download's size (structured data, fine print, llms.txt): set it from this DMG, in MB as
# Finder counts them. A changed size shows up in git status, to commit with the release.
SIZE=$(awk -v bytes="$(stat -f %z "$DMG")" 'BEGIN { printf "%.1f", bytes / 1e6 }')
sed -i '' -E -e "s/\"fileSize\": \"[0-9]+\.[0-9]+ MB\"/\"fileSize\": \"$SIZE MB\"/" \
  -e "s/[0-9]+\.[0-9]+&nbsp;MB/$SIZE\&nbsp;MB/" site/index.html
sed -i '' -E "s/[0-9]+\.[0-9]+ MB universal disk image/$SIZE MB universal disk image/" site/llms.txt
grep -q "\"fileSize\": \"$SIZE MB\"" site/index.html && grep -q "$SIZE&nbsp;MB" site/index.html \
  && grep -q "$SIZE MB universal disk image" site/llms.txt \
  || { echo "Couldn't state the DMG's size, $SIZE MB, everywhere the site gives it." >&2; exit 1; }

rm -rf site/downloads && mkdir -p site/downloads
cp "$DMG" site/downloads/

netlify deploy --dir site ${1:+--prod} --message "Ambient $VERSION"
