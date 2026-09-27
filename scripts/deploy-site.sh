#!/bin/zsh
# Deploys site/ to Netlify with the current release's DMG.
#
#   scripts/deploy-site.sh           draft deploy (a unique preview URL)
#   scripts/deploy-site.sh --prod    production (yaml.cafe)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/AmbientCore/Version.swift)
DMG=dist/Ambient-$VERSION.dmg
[[ -f $DMG ]] || { echo "Missing $DMG. Run scripts/release.sh first." >&2; exit 1; }
grep -q "Ambient-$VERSION.dmg" site/index.html || { echo "site/ doesn't link Ambient-$VERSION.dmg." >&2; exit 1; }
# The version is also stated for search engines and AI assistants; keep those facts current.
grep -q "\"softwareVersion\": \"$VERSION\"" site/index.html || { echo "site/index.html's softwareVersion isn't $VERSION." >&2; exit 1; }
grep -q "Version $VERSION" site/index.html || { echo "site/index.html's fine print doesn't say Version $VERSION." >&2; exit 1; }
! grep -rl "UMAMI_WEBSITE_ID" site >/dev/null || { echo "site/ still has the UMAMI_WEBSITE_ID placeholder; add the Umami website ID first." >&2; exit 1; }
grep -q "Current version: $VERSION" site/llms.txt || { echo "site/llms.txt doesn't say Current version: $VERSION." >&2; exit 1; }

rm -rf site/downloads && mkdir -p site/downloads
cp "$DMG" site/downloads/

netlify deploy --dir site ${1:+--prod} --message "Ambient $VERSION"
