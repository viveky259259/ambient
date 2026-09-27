#!/bin/zsh
# Checks that site/ states one version everywhere it's stated (download links, structured data, fine print,
# llms.txt) and has no placeholders left.
#
#   scripts/check-site.sh            the app's current version
#   scripts/check-site.sh 0.2.2      a specific version
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:-$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/AmbientCore/Version.swift)}
fail() { echo "site: $1" >&2; exit 1; }

grep -q "Ambient-$VERSION.dmg" site/index.html || fail "index.html doesn't link Ambient-$VERSION.dmg."
grep -q "Ambient-$VERSION.dmg" site/thanks.html || fail "thanks.html doesn't link Ambient-$VERSION.dmg."
grep -q "\"softwareVersion\": \"$VERSION\"" site/index.html || fail "index.html's softwareVersion isn't $VERSION."
grep -q "Version $VERSION" site/index.html || fail "index.html's fine print doesn't say Version $VERSION."
grep -q "Current version: $VERSION" site/llms.txt || fail "llms.txt doesn't say Current version: $VERSION."
! grep -rl "UMAMI_WEBSITE_ID" site >/dev/null || fail "the UMAMI_WEBSITE_ID placeholder is still there."
echo "site: states $VERSION everywhere"
