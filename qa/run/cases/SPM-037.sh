#!/bin/zsh
# SPM-037 · Voice history is kept privately until deleted.
# needs-app: yes
# checks: part
# Left to a person: History's rows and their order; library.json, the audio/ folder and each audio/<id>.aac being
# private once voices have arrived (no second Mac here to send one); Show in Finder, Delete and Delete All.
# Checks what a fresh launch makes in voice sync's folder: the folder and this Mac's hub id.
source "$QA_REPO/qa/run/lib.sh"
vs=$AMBIENT_HOME/voice-sync

wait_for 10 test -f "$vs/hub.id"
assert_mode "$vs" 700
assert_mode "$vs/hub.id" 600
[[ $(<"$vs/hub.id") =~ '^[0-9a-f]{32}$' ]] || fail "hub.id is not a 32-hex id: [$(<"$vs/hub.id")]"
for f in "$vs"/**/*(N); do
  if [[ -d $f ]]; then assert_mode "$f" 700; else assert_mode "$f" 600; fi
done
note "voice-sync holds: $(cd "$vs" && print -l **/*(N) | tr '\n' ' ')"
