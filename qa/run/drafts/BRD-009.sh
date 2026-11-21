#!/bin/zsh
# BRD-009 · Settings › Board shows each column's latest eight cards and links to the rest.
# needs-app: yes
# checks: part
# Left to a person: Settings › Board drawing 8 cards, *3 more in the Task Board* and its tooltip, the window it opens.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/board-lib.sh"

for i in $(seq 1 11); do ambient task upsert --title "Backlog $i" >/dev/null || fail "upsert $i failed"; sleep 0.05; done
json=$(ambient tasks --json)
assert_eq "$(print -r -- $json | jq '[.[] | select(.status == "backlog")] | length')" 11 "backlog tasks (the header's count)"
# Newest first: the column's first 8 are Backlog 11 … Backlog 4.
assert_eq "$(print -r -- $json | jq -r '[.[] | select(.status == "backlog")][0:8] | map(.title) | join(",")')" \
  "Backlog 11,Backlog 10,Backlog 9,Backlog 8,Backlog 7,Backlog 6,Backlog 5,Backlog 4" "the latest eight, newest first"
