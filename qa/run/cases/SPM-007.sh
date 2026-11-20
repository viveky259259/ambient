#!/bin/zsh
# SPM-007 · Building the driver tests it first.
# needs-app: no
# timeout: 180
# checks: part
# Left to a person: running scripts/build-speaker.sh itself (it writes build/): the driver bundle for arm64 and
# x86_64, the single exported symbol, signing and verifying, loading through build/load-speaker, the closing line,
# a failing test stopping the build, and --if-needed (steps 2 and 3).
# Compiles the driver's own tests exactly as step 1 does (same flags, address and undefined-behaviour sanitizers),
# into this case's folder, and runs them. They drive the driver through a stand-in for coreaudiod: nothing is
# installed and no sound device is touched.
source "$QA_REPO/qa/run/lib.sh"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[[ -d $DEVELOPER_DIR ]] || { echo "Xcode not found at $DEVELOPER_DIR" >&2; exit 2; }
SRC=$QA_REPO/Drivers/AmbientSpeaker
CFLAGS=(-std=c17 -Wall -Wextra -Werror -fvisibility=hidden -mmacosx-version-min=14.0)

xcrun clang "${CFLAGS[@]}" -O1 -g -fsanitize=address,undefined -o "$QA_ROOT/speaker-tests" \
  "$SRC/AmbientSpeaker.c" "$SRC/Tests.c" -framework CoreFoundation || fail "the driver or its tests don't compile cleanly"
out=$("$QA_ROOT/speaker-tests" 2>&1)
code=$?
print -r -- "$out" | sed 's/^/  /'
assert_eq "$code" 0 "exit code of speaker-tests"
assert_contains "$out" "Ambient speaker: all tests passed"
assert_not_contains "$out" "runtime error" "an undefined-behaviour report"
assert_not_contains "$out" "AddressSanitizer" "an address-sanitizer report"
