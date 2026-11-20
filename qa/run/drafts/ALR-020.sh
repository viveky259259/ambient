#!/bin/zsh
# ALR-020 · Quiet alerts end on their own.
# needs-app: yes
# checks: part
# Left to a person: the slash leaving the orb, the menu offering Quiet Alerts again, and the needs-you banner and chime.
# Ambient starts with quiet alerts set (in the QA app's own settings domain) to end 12 s later; the stored end time
# must be cleared within about 5 s of passing.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

D=com.viveky259259.Ambient.qa
end=$(( EPOCHSECONDS + 12 ))
setup() { defaults write $D quietUntil -date "$(date -u -r $end '+%Y-%m-%d %H:%M:%S +0000')"; }
own_app b setup
defaults read $D quietUntil >/dev/null 2>&1 || fail "quietUntil was cleared at launch, while still in the future"
while (( EPOCHSECONDS < end - 1 )); do sleep 0.5; done
defaults read $D quietUntil >/dev/null 2>&1 || fail "quietUntil was cleared before its time"
while defaults read $D quietUntil >/dev/null 2>&1; do
  (( EPOCHSECONDS > end + 7 )) && fail "quiet alerts still set $((EPOCHSECONDS - end)) s after they should have ended"
  sleep 0.25
done
note "cleared $(( EPOCHSECONDS - end )) s after the end time"
