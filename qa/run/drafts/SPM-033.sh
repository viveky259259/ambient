#!/bin/zsh
# SPM-033 · A voice for a Mac that's away arrives when it's back.
# needs-app: yes
# checks: part
# Left to a person: step 1's "Desk gets it when it's back"; step 2's arrival within a few seconds of Desk reconnecting;
# the outbox staying under 40 MB.
# Stands in for Lap after step 3: its outbox (~/.ambient/voice-sync in this case's HOME) holds a voice for Desk
# recorded 25 hours ago and one recorded an hour ago when Ambient starts. Lines are written as VoiceOutbox writes
# them; no second Mac is involved.
source "$QA_REPO/qa/run/lib.sh"
box=$HOME/.ambient/voice-sync
DESK=dddddddddddddddddddddddddddddddd
OLD=0000000000000000000000000000000a NEW=0000000000000000000000000000000b
now=$EPOCHSECONDS

line() { print -r -- '{"v":1,"type":"voice","vseq":'$1',"to":"'$DESK'","voice":"'$2'","part":"'$3'"'${4:-}'}'; }
outbox_has() { grep -q "\"voice\":\"$1\"" "$box/outbox.jsonl"; }
old_gone() { ! outbox_has $OLD; }

# The runner has already started the app, which tidied an empty outbox. Seed the outbox, then start it again so
# the next launch tidies this one.
app=$QA_APP_PID
trap '[[ $app != $QA_APP_PID ]] && kill $app 2>/dev/null' EXIT
kill -TERM $app 2>/dev/null
end=$((SECONDS + 10))
while [[ -n $(ps -o stat= -p $app 2>/dev/null | grep -v Z) ]]; do   # a zombie (Z) has quit: the runner reaps it later
  (( SECONDS >= end )) && fail "the QA app (pid $app) did not quit within 10 s"
  sleep 0.2
done

mkdir -p -m 700 "$box"
{
  line 1 $OLD start ',"ts":'$((now - 25 * 3600))
  line 2 $OLD end ',"text":"old words"'
  line 3 $NEW start ',"ts":'$((now - 3600))
  line 4 $NEW end ',"text":"new words"'
} > "$box/outbox.jsonl"
chmod 600 "$box/outbox.jsonl"
print -r -- $'4\n0123456789abcdef '$(stat -f %z "$box/outbox.jsonl")$' 0' > "$box/outbox.seq"
outbox_has $OLD && outbox_has $NEW || fail "could not seed the outbox"

"$QA_APP/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
app=$!
wait_for 15 ambient status

wait_for 10 old_gone
outbox_has $NEW || fail "the voice from an hour ago was dropped from the outbox too"
assert_eq "$(grep -c "\"voice\":\"$NEW\"" "$box/outbox.jsonl")" 2 "lines of the voice from an hour ago"
assert_mode "$box/outbox.jsonl" 600
note "outbox after launch: $(wc -l < "$box/outbox.jsonl" | tr -d ' ') lines, seq $(head -1 "$box/outbox.seq")"
