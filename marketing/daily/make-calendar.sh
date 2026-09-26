#!/bin/zsh
# Builds "Ambient Daily Brief.app" and one Apple Calendar event that repeats daily at 6:25 PM through
# the last Reddit day. Calendar's scripting can't attach an "Open file" target, so set the alert once
# by hand: open the event → Alert → Custom… → Open file → Other… → ~/Applications/Ambient Daily Brief.app.
# Re-running replaces the events in the "Ambient Launch" calendar (and the alert you set).
set -euo pipefail
cd "${0:A:h:h:h}"
BRIEF=$PWD/marketing/daily/brief.sh
APP="$HOME/Applications/Ambient Daily Brief.app"
mkdir -p "$HOME/Applications"
osacompile -o "$APP" -e "do shell script \"/bin/zsh -c '\\\"$BRIEF\\\" > /dev/null 2>&1 &'\""
echo "Built $APP"

read -r FIRST LAST < <(python3 -c 'import json; e=json.load(open("docs/launch/reddit-events.json")); print(e[0]["day"], e[-1]["day"])')
osascript - "$FIRST" "$LAST" <<'OSA'
on run argv
  set {y, m, d} to my ymd(item 1 of argv)
  set untilDay to do shell script "echo " & quoted form of (item 2 of argv) & " | tr -d -"
  tell application "Calendar"
    if not (exists calendar "Ambient Launch") then make new calendar with properties {name:"Ambient Launch"}
    set cal to calendar "Ambient Launch"
    delete (every event of cal)
    set t to current date
    set day of t to 1
    set year of t to y
    set month of t to m
    set day of t to d
    set hours of t to 18
    set minutes of t to 25
    set seconds of t to 0
    make new event at end of events of cal with properties {summary:"Ambient daily brief (today's Reddit post)", start date:t, end date:(t + 5 * minutes), recurrence:("FREQ=DAILY;INTERVAL=1;UNTIL=" & untilDay & "T235959"), description:"The alert on this event opens Ambient Daily Brief: Claude opens today's Reddit post and its rules in Chrome and writes the brief to docs/launch/daily. You submit the post."}
    return (count of events of cal) as string
  end tell
end run
on ymd(s)
  set AppleScript's text item delimiters to "-"
  set parts to text items of s
  return {(item 1 of parts) as integer, (item 2 of parts) as integer, (item 3 of parts) as integer}
end ymd
OSA
echo "Created the repeating event in \"Ambient Launch\" ($FIRST → $LAST, 6:25 PM)."
