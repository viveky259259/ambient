#!/bin/zsh
# Prints yaml.cafe's download counts, recorded by netlify/edge-functions/downloads.ts.
#
#   scripts/downloads.sh              totals by day, version, launch tag and country
#   scripts/downloads.sh 2026-09-27   the same for keys starting with a prefix (a day, say)
#
# Launch tags: give every link you post its own ?ref=, on the homepage or the DMG itself, and its downloads are
# counted under that tag: https://yaml.cafe/?ref=hn, https://yaml.cafe/?ref=reddit-macapps,
# https://yaml.cafe/?ref=yt-<creator>. The site carries a homepage's ?ref= on to its download button. Tags are
# lowercased and keep only a-z, 0-9, ".", "_" and "-", up to 60 characters. Taken by Ambient itself:
#   brew     Homebrew installs (the cask downloads with ?ref=brew)
#   ci       the Deploy site workflow checking the published DMG's checksum, once per deploy
#   site     the download button, reached without a tag
#   direct   no tag and no referring page (a pasted link, curl)
# Without a tag, a link from another site counts under that site's hostname.
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
