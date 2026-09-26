#!/bin/zsh
# Prints yaml.cafe's download counts, recorded by netlify/edge-functions/downloads.ts.
#
#   scripts/downloads.sh              totals by day, version, launch tag and country
#   scripts/downloads.sh 2026-09-27   the same for keys starting with a prefix (a day, say)
set -euo pipefail
cd "$(dirname "$0")/.."

netlify blobs:list downloads --json ${1:+--prefix "$1"} | python3 -c '
import json, sys
from collections import Counter
blobs = json.load(sys.stdin)
if isinstance(blobs, dict):
    blobs = blobs.get("blobs", [])
keys = [b["key"] if isinstance(b, dict) else b for b in blobs]
rows = [k.split("/") for k in keys if k.count("/") >= 4]
print(f"Downloads: {len(rows)}")
for title, index in (("By day", 0), ("By version", 1), ("By launch tag", 2), ("By country", 3)):
    print(f"\n{title}")
    for value, n in sorted(Counter(r[index] for r in rows).items(), key=lambda kv: (-kv[1], kv[0]) if index else kv[0]):
        print(f"  {value:<32} {n}")
'
