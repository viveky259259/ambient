#!/bin/zsh
# The daily Ambient launch brief, started by an Apple Calendar alert (see make-calendar.sh).
#
#   brief.sh              open today's Reddit post and its rules in Chrome, then have Claude write the brief
#   brief.sh --dry-run    everything except opening Chrome
#
# Claude only ever sees counts, never names or email addresses from the waitlist.
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/opt/node@20/bin:/usr/local/bin:/usr/bin:/bin"

# Unattended runs sign in with a long-lived token kept in the Keychain (see README in this folder).
if TOKEN=$(security find-generic-password -a "$USER" -s ambient-brief-claude -w 2>/dev/null); then
  export CLAUDE_CODE_OAUTH_TOKEN=$TOKEN
fi

REPO=${0:A:h:h:h}
cd "$REPO"
TODAY=${AMBIENT_BRIEF_DATE:-$(date +%F)}
DRY=0
[[ ${1:-} == --dry-run ]] && DRY=1
SITE_ID=5ff1015d-3777-4586-9fa8-eecd1b009152
OUT=docs/launch/daily
mkdir -p "$OUT"

notify() {
  local text=${1//\"/\'}
  osascript -e "display notification \"$text\" with title \"Ambient launch\" sound name \"Glass\"" || true
}

# Today's post from the schedule: number, community, title, prefilled link, rules link.
IFS=$'\t' read -r N COMMUNITY TITLE URL RULES < <(python3 - "$TODAY" <<'EOF' || true
import json, sys, re, html
events = json.load(open("docs/launch/reddit-events.json"))
for e in events:
    if e["day"] == sys.argv[1]:
        links = re.findall(r'href="([^"]+)"', e["description"])
        rules = html.unescape(links[0])
        post = html.unescape(links[1])
        title = re.sub(r"<[^>]+>", "", e["description"].split("<br>")[0])
        print("\t".join([str(e["n"]), e["community"], html.unescape(title), post, rules]))
EOF
)
if [[ -z ${N:-} ]]; then
  echo "$TODAY: no Reddit post scheduled."
  exit 0
fi

(( DRY )) || open -a "Google Chrome" "$RULES" "$URL"

# Waitlist counts: total and the last 24 hours.
read -r TOTAL NEW < <(python3 - "$SITE_ID" <<'EOF' || echo "? ?"
import json, subprocess, sys
from datetime import datetime, timedelta, timezone
def api(method, data):
    out = subprocess.run(["netlify", "api", method, "--data", json.dumps(data)], capture_output=True, text=True, check=True).stdout
    return json.loads(out)
form = next(f for f in api("listSiteForms", {"site_id": sys.argv[1]}) if f["name"] == "waitlist")
subs, page = [], 1
while True:
    batch = api("listFormSubmissions", {"form_id": form["id"], "per_page": 100, "page": page})
    subs += batch
    if len(batch) < 100: break
    page += 1
since = datetime.now(timezone.utc) - timedelta(hours=24)
new = sum(1 for s in subs if datetime.fromisoformat(s["created_at"].replace("Z", "+00:00")) >= since)
print(len(subs), new)
EOF
)

PROMPT="You're writing today's launch brief for Ambient, a free macOS app at https://yaml.cafe.
Today is $TODAY. Today's Reddit post is #$N of the schedule, in $COMMUNITY, titled: \"$TITLE\".
The user has it open in Chrome to check the rules and submit it themselves; you do not post anything.
Waitlist so far: $TOTAL sign-ups, $NEW in the last 24 hours.

1. Write $OUT/$TODAY.md with: today's subreddit and title; the waitlist numbers; and three short,
   specific suggestions for replying to comments on this post in $COMMUNITY during its first hour.
2. Then reply with one line under 150 characters for a notification, like:
   \"$COMMUNITY is up next · waitlist $TOTAL (+$NEW) · brief in docs/launch/daily\""

LINE=$(claude -p "$PROMPT" --permission-mode dontAsk --allowedTools "Edit($OUT/**)" --add-dir "$REPO" 2>>"$OUT/brief.log" | tail -1) || LINE=""
[[ -n $LINE ]] || LINE="$COMMUNITY is up next · waitlist $TOTAL (+$NEW)"
notify "$LINE"
echo "$(date '+%F %T') #$N $COMMUNITY · waitlist $TOTAL (+$NEW) · $LINE" >> "$OUT/brief.log"
echo "$LINE"
