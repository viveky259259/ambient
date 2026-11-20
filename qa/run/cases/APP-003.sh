#!/bin/zsh
# APP-003 · First launch prepares a private ~/.ambient and links the command-line tool.
# needs-app: yes
# timeout: 90
# AMBIENT_HOME stands in for ~/.ambient and build/AmbientQA.app for /Applications/Ambient.app. Step 4 copies the QA
# app into this case's folder and starts the copy there, after stopping the one the runner started.
source "$QA_REPO/qa/run/lib.sh"

gone() { local s; s=$(ps -o stat= -p $1 2>/dev/null); [[ -z $s || $s == Z* ]]; }
up() { ambient status >/dev/null 2>&1; }
trap '[[ -n ${MOVED_PID:-} ]] && kill $MOVED_PID 2>/dev/null' EXIT

me=$(id -un)
for d in "$AMBIENT_HOME" "$AMBIENT_HOME/bin" "$AMBIENT_HOME/backups" "$AMBIENT_HOME/logs"; do
  [[ -d $d ]] || fail "missing folder $d"
  assert_mode "$d" 700
  assert_eq "$(stat -f %Su "$d")" "$me" "owner of $d"
done
assert_eq "$(readlink "$AMBIENT_HOME/bin/ambient")" "$QA_APP/Contents/Helpers/ambient" "the CLI link"

# Step 4: the same app, run from another folder.
kill $QA_APP_PID
wait_for 10 gone $QA_APP_PID
mkdir -p "$QA_ROOT/moved"
cp -R "$QA_APP" "$QA_ROOT/moved/"
moved="$QA_ROOT/moved/${QA_APP:t}"
"$moved/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
MOVED_PID=$!
wait_for 15 up
assert_eq "$(readlink "$AMBIENT_HOME/bin/ambient")" "$moved/Contents/Helpers/ambient" "the CLI link after moving the app"
note "the link follows the app to $moved"
