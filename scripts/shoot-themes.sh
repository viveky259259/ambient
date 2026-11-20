#!/bin/zsh
# Screenshots design-test themes from a local server, for review:
#
#   python3 -m http.server 8788 --directory site &
#   scripts/shoot-themes.sh OUT_DIR almanac iris ...     (no names: every theme in site/themes/manifest.json)
#
# Writes OUT_DIR/<id>-desktop.png (1440 wide, the top 3200 px) and OUT_DIR/<id>-phone.png (390 wide, the top 2400 px).
# Needs Playwright's headless Chromium (npx playwright install chromium-headless-shell).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?usage: scripts/shoot-themes.sh OUT_DIR [theme ...]}; shift
mkdir -p "$OUT"; OUT=${OUT:A}
SHELL_BIN=$(ls -d ~/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-mac-*/chrome-headless-shell | tail -1)
BASE=${BASE:-http://localhost:8788}
ids=("$@")
(( ${#ids} )) || ids=($(python3 -c 'import json;print(" ".join(t["id"] for t in json.load(open("site/themes/manifest.json"))))'))
for id in $ids; do
  "$SHELL_BIN" --hide-scrollbars --window-size=1440,3200 --virtual-time-budget=4000 --timeout=20000 \
    --user-agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36" \
    --screenshot="$OUT/$id-desktop.png" "$BASE/?theme=$id" >/dev/null 2>&1
  "$SHELL_BIN" --hide-scrollbars --window-size=390,2400 --virtual-time-budget=4000 --timeout=20000 \
    --user-agent="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148" \
    --screenshot="$OUT/$id-phone.png" "$BASE/?theme=$id" >/dev/null 2>&1
  echo "$id"
done
