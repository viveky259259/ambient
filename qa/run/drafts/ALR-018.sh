#!/bin/zsh
# ALR-018 · Mark All as Seen appears only when something finished or failed.
# needs-app: yes
# checks: part
# Left to a person: whether the menu offers Mark All as Seen, the dimmed green dot and the orb's colour.
# Mark All as Seen and `ambient ack` both call AppModel.acknowledgeAll; this checks what it does to a done session.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/prm-lib.sh"

ambient emit working --session alr-018-w --agent Build >/dev/null
ambient emit working --session alr-018-d --agent Build >/dev/null
ambient emit done --session alr-018-d --agent Build >/dev/null
wait_for 3 sess_is alr-018-d '.activity | keys[0]' done
assert_eq "$(sess alr-018-d .acknowledged)" false "a fresh done session is unseen"

ambient ack || fail "ambient ack failed"
wait_for 3 sess_is alr-018-d .acknowledged true
assert_eq "$(sess alr-018-d '.activity | keys[0]')" done "the done session keeps its result"
assert_eq "$(sess alr-018-w .acknowledged)" false "a working session is not marked seen"
