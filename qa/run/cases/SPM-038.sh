#!/bin/zsh
# SPM-038 · Unpairing keeps a Mac's voices; purging deletes them.
# needs-app: no
# checks: part
# Left to a person: the rows in Settings › Voice Sync › History before and after.
# Stands in for Desk: a voice library holding two voices received from Lap, one sent to Lap and one from another Mac,
# and Lap paired in machines.json (written here, as `ambient remote add` would over ssh). Then runs the case's
# `ambient remote remove lap` and `ambient remote purge lap`, which only touch this case's AMBIENT_HOME.
source "$QA_REPO/qa/run/lib.sh"
vs=$AMBIENT_HOME/voice-sync
lib=$vs/library.json
mkdir -p -m 700 "$vs/audio" "$AMBIENT_HOME/remote"

pair_lap() {
  print -r -- '{"version":1,"machines":[{"id":"lap","label":"Lap","transport":["ssh","lap"],"fingerprint":"id:0123456789abcdef0123456789abcdef","pairedAt":0}]}' \
    > "$AMBIENT_HOME/remote/machines.json"
}
pair_lap
FROM1=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1 FROM2=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2
SENT=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1 OTHER=ccccccccccccccccccccccccccccccc1
cat > "$lib" <<JSON
{"version":1,"cursors":{"lap":7,"studio":3},"epochs":{"lap":"0123456789abcdef"},"voices":[
 {"id":"$FROM1","direction":"received","peer":{"id":"lap","label":"Lap"},"recordedAt":"2026-11-20T10:00:00Z","seconds":4,"text":"first from lap"},
 {"id":"$FROM2","direction":"received","peer":{"id":"lap","label":"Lap"},"recordedAt":"2026-11-20T11:00:00Z","seconds":5,"text":null},
 {"id":"$SENT","direction":"sent","peer":{"id":"lap","label":"Lap"},"recordedAt":"2026-11-20T12:00:00Z","seconds":6,"text":"to lap"},
 {"id":"$OTHER","direction":"received","peer":{"id":"studio","label":"Studio"},"recordedAt":"2026-11-20T13:00:00Z","seconds":7,"text":"from studio"}
]}
JSON
for id in $FROM1 $FROM2 $SENT $OTHER; do print -n "audio $id" > "$vs/audio/$id.aac"; done
ids() { jq -c '[.voices[].id] | sort' "$lib"; }

# Step 1: unpairing keeps every voice.
out=$(ambient remote remove lap 2>&1) || fail "ambient remote remove lap exited $?: $out"
note "remove: $out"
assert_eq "$(ids)" "$(print -r -- "[\"$FROM1\",\"$FROM2\",\"$SENT\",\"$OTHER\"]" | jq -c 'sort')" "voices after unpairing"
for id in $FROM1 $FROM2 $SENT $OTHER; do assert_file "$vs/audio/$id.aac"; done
assert_eq "$(jq -c '.machines | map(.id)' "$AMBIENT_HOME/remote/machines.json")" '[]' "paired machines after unpairing"

# Step 2: pair again, then purge: Lap's voices go, with their audio; the one sent to Lap and Studio's stay.
pair_lap
out=$(ambient remote purge lap 2>&1) || fail "ambient remote purge lap exited $?: $out"
note "purge: $out"
assert_eq "$(ids)" "$(print -r -- "[\"$SENT\",\"$OTHER\"]" | jq -c 'sort')" "voices after purging lap"
assert_no_file "$vs/audio/$FROM1.aac"
assert_no_file "$vs/audio/$FROM2.aac"
assert_file "$vs/audio/$SENT.aac"
assert_file "$vs/audio/$OTHER.aac"
assert_eq "$(jq -c '.cursors' "$lib")" '{"studio":3}' "voice cursors after purging lap"
