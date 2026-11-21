#!/bin/zsh
# What the QA Mac does for .github/workflows/qa.yml, after a merge to main or a push to a branch
# with an open pull request: build, run the scripted cases the change touches, publish the
# dashboard, post to #ambient-qa.
#
#   qa/run/ci.sh <base>        cases picked by the changes since <base> (a commit or origin/main)
#   QA_ALL=1 qa/run/ci.sh      every scripted case
#   QA_CONTEXT, QA_RUN_URL     what the run is for and where its log is, shown in Slack and the dashboard
set -uo pipefail
cd "$(dirname "$0")/../.."
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

before=${1:-}
if [[ -z $before || $before == 0000000000000000000000000000000000000000 ]] || ! git rev-parse -q --verify "$before^{commit}" >/dev/null; then
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
