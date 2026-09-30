#!/bin/zsh
# Moderates the feature-request board at yaml.cafe/requests (Netlify Blobs store "requests").
#
#   scripts/requests.sh new                         requests since you last looked
#   scripts/requests.sh list                        everything, by votes
#   scripts/requests.sh status <id> planned         open | planned | in-progress | shipped
#   scripts/requests.sh merge <id> <into>           fold a duplicate into the original
#   scripts/requests.sh remove <id>                 hide a request (kept, marked removed)
#   scripts/requests.sh purge <id>                  delete a request and its votes (test data)
#   scripts/requests.sh prune [--all]               drop old daily-limit records
set -euo pipefail
cd "$(dirname "$0")/.."
exec node --import tsx scripts/requests.ts "$@"
