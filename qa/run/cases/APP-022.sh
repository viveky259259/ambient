#!/bin/zsh
# APP-022 · Ambient needs macOS 14 or later.
# checks: part
# Left to a person: Finder refusing to open it on macOS 13, and it working on macOS 14.
# Checked on build/Ambient.app, built from the same Info.plist and Package.swift as the release.
source "$QA_REPO/qa/run/lib.sh"

app=$QA_REPO/build/Ambient.app
assert_eq "$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")" "14.0" "LSMinimumSystemVersion"
# The binaries are built for macOS 14 too, so the plist is not the only thing holding the line.
for bin in MacOS/Ambient Helpers/ambient; do
  minos=$(otool -l "$app/Contents/$bin" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "minos" { print $2; exit }')
  assert_eq "$minos" "14.0" "minimum macOS of Contents/$bin"
done
