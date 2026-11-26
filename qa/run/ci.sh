#!/bin/zsh
# What the QA Mac does for .github/workflows/qa.yml, after a merge to main or a push to a branch
# with an open pull request: build, run the scripted cases the change touches, publish the
# dashboard, post to #ambient-qa.
#
#   qa/run/ci.sh <base>        cases picked by the changes since <base> (a commit or origin/main)
#   QA_ALL=1 qa/run/ci.sh      every scripted case
#   QA_CONTEXT, QA_RUN_URL     what the run is for and where its log is, shown in Slack and the dashboard
#
# A change to the QA harness itself runs every scripted case: that is when the harness needs proof.
# Slow cases (# slow: yes) are left out unless QA_ALL=1.
set -uo pipefail
cd "$(dirname "$0")/../.."
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Kept outside the checkout: each job's checkout wipes build/, and with it every earlier run.
export QA_RESULTS_DIR=${QA_RESULTS_DIR:-$HOME/ambient-qa/results}

base=${1:-}
if [[ -z $base || $base == 0000000000000000000000000000000000000000 ]] || ! git rev-parse -q --verify "$base^{commit}" >/dev/null; then
  base=$(git rev-parse HEAD~1)
fi

all=${QA_ALL:-0}
if git diff --name-only "$base...HEAD" | grep -qE '^(qa/run/(lib\.sh|ci\.sh|make-qa-app\.sh|[a-z]+-lib\.sh)|scripts/qa-run\.ts)$'; then
  echo "The QA harness changed: running every scripted case."
  [[ $all == 1 ]] || all=harness
fi

scripts/build-app.sh || exit 2
qa/run/make-qa-app.sh || exit 2

newest() { ls -td "$QA_RESULTS_DIR"/*/ 2>/dev/null | head -1; }
before_run=$(newest)
case $all in
  1) node scripts/qa-run.ts ;;
  harness) node scripts/qa-run.ts --skip-slow ;;
  *) node scripts/qa-run.ts --changed "$base" --skip-slow ;;
esac
qa_status=$?

# Nothing to report when no scripted case matched: the newest results are an older run's.
if [[ $(newest) == "$before_run" ]]; then
  echo "No scripted case covers this change; nothing to report."
  exit $qa_status
fi

# Reporting never hides the run's own result: a reporting failure is printed, not returned.
node scripts/qa-dashboard.ts --publish || echo "warning: the dashboard was not published"
node scripts/qa-slack.ts --send || echo "warning: nothing was posted to Slack"
exit $qa_status
