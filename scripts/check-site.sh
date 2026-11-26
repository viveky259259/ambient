#!/bin/zsh
# Checks that site/ states one version everywhere it's stated (download links, structured data, fine print,
# llms.txt) and has no placeholders left.
#
#   scripts/check-site.sh            the app's current version
#   scripts/check-site.sh 0.2.2      a specific version
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${1:-$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/AmbientBase/Version.swift)}
fail() { echo "site: $1" >&2; exit 1; }

grep -q "Ambient-$VERSION.dmg" site/index.html || fail "index.html doesn't link Ambient-$VERSION.dmg."
grep -q "Ambient-$VERSION.dmg" site/thanks.html || fail "thanks.html doesn't link Ambient-$VERSION.dmg."
grep -q "\"softwareVersion\": \"$VERSION\"" site/index.html || fail "index.html's softwareVersion isn't $VERSION."
grep -q "Version $VERSION" site/index.html || fail "index.html's fine print doesn't say Version $VERSION."
grep -q "Current version: $VERSION" site/llms.txt || fail "llms.txt doesn't say Current version: $VERSION."
! grep -rl "UMAMI_WEBSITE_ID" site >/dev/null || fail "the UMAMI_WEBSITE_ID placeholder is still there."
python3 - <<'PY' || fail "the design test's themes are incomplete; run node scripts/build-themes.mjs."
import json, os, re, sys
themes = json.load(open("site/themes/manifest.json"))
listed = re.search(r"const THEMES = (\[.*?\]);", open("site/themes/loader.js").read()).group(1)
problems = [f"{t['id']}: no {f}" for t in themes for f in ("theme.css", "fonts.css") if not os.path.exists(f"site/themes/{t['id']}/{f}")]
if [t["id"] for t in json.loads(listed)] != [t["id"] for t in themes]: problems.append("loader.js and manifest.json list different themes")
if not any(t["id"] == "almanac" and not t["off"] for t in themes): problems.append("the default theme, almanac, is missing or off")
for p in problems: print("site:", p, file=sys.stderr)
sys.exit(1 if problems else 0)
PY
echo "site: states $VERSION everywhere"
