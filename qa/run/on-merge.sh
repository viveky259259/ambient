#!/bin/zsh
# What the QA Mac does when a pull request is merged (.github/workflows/qa-on-merge.yml):
# build, run the scripted cases the merge touched, publish the dashboard, post to #ambient-qa.
#
#   qa/run/on-merge.sh <commit-before-the-merge>    cases the merge's changes pick
#   QA_ALL=1 qa/run/on-merge.sh                      every scripted case
set -uo pipefail
cd "$(dirname "$0")/../.."
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

before=${1:-}
if [[ -z $before || $before == 0000000000000000000000000000000000000000 ]] || ! git cat-file -e "$before^{commit}" 2>/dev/null; then
  before=$(git rev-parse HEAD~1)
fi

scripts/build-app.sh || exit 2
qa/run/make-qa-app.sh || exit 2

if [[ ${QA_ALL:-0} == 1 ]]; then
  node scripts/qa-run.ts
else
  node scripts/qa-run.ts --changed "$before" --skip-slow
fi
status=$?

# Reporting never hides the run's own result: a reporting failure is printed, not returned.
node scripts/qa-dashboard.ts --publish || echo "warning: the dashboard was not published"
node scripts/qa-slack.ts --send || echo "warning: nothing was posted to Slack"
exit $status
