#!/bin/zsh
# APP-004 · Ambient is a menu-bar app that shows in the Dock only while a window is open.
# needs-app: yes
# timeout: 90
# checks: part
# Left to a person: the menu bar's status orb, and Ambient leaving the Dock when Settings is closed.
# Checked through Launch Services' application type: "Foreground" apps have a Dock icon and a ⌘-Tab entry,
# "UIElement" apps have neither. Settings opens by itself on a fresh setup, which stands in for choosing Settings….
source "$QA_REPO/qa/run/lib.sh"

DOMAIN=com.viveky259259.Ambient.qa
gone() { local s; s=$(ps -o stat= -p $1 2>/dev/null); [[ -z $s || $s == Z* ]]; }
up() { ambient status >/dev/null 2>&1; }
trap '[[ -n ${APP_PID:-} ]] && kill $APP_PID 2>/dev/null' EXIT
app_type() { lsappinfo info -only applicationtype "$(lsappinfo find pid=$1)" | sed -n 's/.*"ApplicationType"="\([^"]*\)".*/\1/p'; }
is_type() { [[ $(app_type $1) == "$2" ]]; }

assert_eq "$(plutil -extract LSUIElement raw "$QA_APP/Contents/Info.plist")" true "LSUIElement"

# Step 2: while Settings is open, Ambient is in the Dock and ⌘-Tab.
wait_for 5 is_type $QA_APP_PID Foreground

# Step 1: setup completed, Settings closed: no Dock icon, no ⌘-Tab entry.
kill $QA_APP_PID
wait_for 10 gone $QA_APP_PID
defaults write $DOMAIN setupCompleted -bool true
"$QA_APP/Contents/MacOS/AmbientQA" >/dev/null 2>&1 &
APP_PID=$!
wait_for 15 up
sleep 1
assert_eq "$(app_type $APP_PID)" "UIElement" "application type with Settings closed"
