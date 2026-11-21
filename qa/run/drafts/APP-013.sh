#!/bin/zsh
# APP-013 · First run opens on Welcome until you get started.
# needs-app: yes
# timeout: 90
# checks: part
# Left to a person: that the window is on Welcome, what Get Started and the red close button do, and the notification
# prompt. Checked: at launch the Settings window opens while setup isn't complete, and doesn't once it is.
# Windows are read from the window server (owner and size only); the QA app's settings domain stands in for
# com.viveky259259.Ambient.
source "$QA_REPO/qa/run/lib.sh"

DOMAIN=com.viveky259259.Ambient.qa
gone() { local s; s=$(ps -o stat= -p $1 2>/dev/null); [[ -z $s || $s == Z* ]]; }
up() { ambient status >/dev/null 2>&1; }
trap '[[ -n ${APP_PID:-} ]] && kill $APP_PID 2>/dev/null' EXIT
# The app's ordinary (layer 0) windows on screen, one "width height name" line each.
windows() {
  /usr/bin/osascript -l JavaScript - $1 <<'JS'
ObjC.import('CoreGraphics');
function run(argv) {
  const pid = parseInt(argv[0]);
  const all = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0))) || [];
  return all.filter(w => w.kCGWindowOwnerPID === pid && w.kCGWindowLayer === 0)
    .map(w => [Math.round(w.kCGWindowBounds.Width), Math.round(w.kCGWindowBounds.Height), w.kCGWindowName || ''].join(' ')).join('\n');
}
JS
}
has_window() { [[ -n $(windows $1) ]]; }

# Fresh settings (the runner cleared them): Settings opens by itself at launch.
wait_for 5 has_window $QA_APP_PID
note "at first launch: $(windows $QA_APP_PID)"
assert_eq "$(defaults read $DOMAIN setupCompleted 2>/dev/null)" "" "setupCompleted before getting started"

# Setup completed (what Get Started saves): no window at launch.
kill $QA_APP_PID
wait_for 10 gone $QA_APP_PID
defaults write $DOMAIN setupCompleted -bool true
"$QA_APP/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
APP_PID=$!
wait_for 15 up
sleep 2
assert_eq "$(windows $APP_PID)" "" "windows at launch once setup is complete"
