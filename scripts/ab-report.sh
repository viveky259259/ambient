#!/bin/zsh
# Prints the homepage design test's results: visitors and downloads per design, each design's download rate with
# a 95% range, and whether the differences are more than chance.
#
#   scripts/ab-report.sh                         every count since the test began
#   scripts/ab-report.sh --since 2026-11-21      only from a day on (after changing the designs, say)
#   scripts/ab-report.sh --target 1000           the number of downloads to wait for (default 1000)
#
# Visitors come from netlify/edge-functions/ab.ts (one record per new visitor), downloads from downloads.ts (only
# the homepage button's, which carry ?v=). Neither stores anything that identifies anyone.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
netlify blobs:list ab-views --json > "$tmp/views.json"
netlify blobs:list downloads --json > "$tmp/downloads.json"
node --import tsx scripts/ab-stats.ts "$tmp/views.json" "$tmp/downloads.json" "$@"
