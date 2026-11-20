#!/bin/zsh
# APP-027 · `ambient --version` matches the app.
# needs-app: yes
# timeout: 60
# checks: part
# Left to a person: Settings › General › Version. build/AmbientQA.app stands in for /Applications/Ambient.app.
source "$QA_REPO/qa/run/lib.sh"

gone() { local s; s=$(ps -o stat= -p $1 2>/dev/null); [[ -z $s || $s == Z* ]]; }
version=$(sed -n 's/.*current = "\(.*\)".*/\1/p' "$QA_REPO/Sources/AmbientBase/Version.swift")
check() {
  local arg out
  for arg in --version version -v; do
    out=$(ambient $arg 2>&1)
    assert_eq "$?" 0 "exit code of ambient $arg ($1)"
    assert_eq "$out" "ambient $version" "ambient $arg ($1)"
  done
}
check "Ambient running"
kill $QA_APP_PID
wait_for 10 gone $QA_APP_PID
check "Ambient quit"

assert_eq "$(plutil -extract CFBundleShortVersionString raw "$QA_APP/Contents/Info.plist")" "$version" "CFBundleShortVersionString"
build=$(plutil -extract CFBundleVersion raw "$QA_APP/Contents/Info.plist")
[[ $build == <1-> ]] || fail "CFBundleVersion is not a build number: [$build]"
note "version $version, build $build"
