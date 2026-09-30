#!/bin/zsh
# Asks Bing and the other IndexNow engines to recrawl every page in site/sitemap.xml. Run it after
# a production deploy; the key file site/$KEY.txt must already be live on yaml.cafe.
#
#   scripts/indexnow.sh
set -euo pipefail
cd "$(dirname "$0")/.."

KEY=5a4c4044279ccebedeca3a293062905a
[[ -f site/$KEY.txt ]] || { echo "Missing site/$KEY.txt." >&2; exit 1; }

BODY=$(python3 -c '
import json, re, sys
key = sys.argv[1]
urls = re.findall(r"<loc>(.*?)</loc>", open("site/sitemap.xml").read())
print(json.dumps({"host": "yaml.cafe", "key": key,
                  "keyLocation": f"https://yaml.cafe/{key}.txt", "urlList": urls}))
' "$KEY")
echo "Submitting $(print -r -- "$BODY" | python3 -c 'import json, sys; print(len(json.load(sys.stdin)["urlList"]))') URLs"

STATUS=$(curl -sS -o /dev/null -w '%{http_code}' -X POST https://api.indexnow.org/indexnow \
  -H 'Content-Type: application/json; charset=utf-8' --data-binary "$BODY")
echo "HTTP $STATUS"
[[ $STATUS == 200 || $STATUS == 202 ]]
