#!/bin/sh
# Runs Resources/ambient-remote under every shell and awk found here, and checks what it writes with a real JSON
# parser. The Swift tests cover the rest of the path, but only on macOS: this is what proves dash, bash, busybox ash,
# mawk, gawk and busybox awk (spec, ER-35), and it's what runs on Linux in CI.
#
#   scripts/test-remote-shim.sh            test every combination available
#   REQUIRE_ALL=1 scripts/test-remote-shim.sh   fail if one is missing, as CI does
set -eu
cd "$(dirname "$0")/.."
SHIM=$PWD/Resources/ambient-remote
SYSTEM_PATH=$PATH
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/shim-test.XXXXXX")
trap 'chmod -R u+rwx "$ROOT"; rm -rf "$ROOT"' EXIT
failures=0

# A bin directory holding this awk, then the system's tools.
with_awk() {
    bin=$ROOT/bin-$1
    mkdir -p "$bin"
    ln -sf "$(command -v "$1")" "$bin/awk"
    echo "$bin:$SYSTEM_PATH"
}

# Only busybox: no python3, no coreutils, nothing to lean on by accident.
busybox_path() {
    bin=$ROOT/bin-busybox
    mkdir -p "$bin"
    busybox --install -s "$bin"
    echo "$bin"
}

check() {
    name=$1 shell=$2 path=$3
    home=$ROOT/home-$name
    mkdir -p "$home/.claude" "$home/.codex" "$home/.ambient/bin"
    cp "$SHIM" "$home/.ambient/bin/ambient-remote"
    chmod 700 "$home/.ambient/bin/ambient-remote"
    remote() { HOME=$home PATH=$path $shell "$home/.ambient/bin/ambient-remote" "$@"; }
    emit() { printf '%s' "$1" | remote emit claude; }

    remote version > "$home/version"
    remote install --redaction full > "$home/install"
    remote install > "$home/reinstall"
    remote status > "$home/status" 2> "$home/status.err"

    emit '{"session_id":"s-1","transcript_path":"/x/t.jsonl","cwd":"\/home\/u\/api","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"session_id":"nested","message":"nested"}}'
    emit '{"session_id":"s-1","cwd":"/home/u/my proj","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Allow \"curl\"? café café \\ done"}'
    emit 'not json'
    emit ''
    emit '{"session_id":"../../etc/passwd","hook_event_name":"Stop"}'
    emit '{"session_id":"s-1","hook_event_name":"Notification","notification_type":"idle_prompt","message":"ignored"}'
    long=$(awk 'BEGIN { for (i = 0; i < 400; i++) printf "é\\\"\\\\ " }')
    emit '{"session_id":"s-1","cwd":"/x","hook_event_name":"Stop","last_assistant_message":"'"$long"'"}'
    big=$(awk 'BEGIN { for (i = 0; i < 5000; i++) printf "line of \\\"quoted\\\" output\\n" }')
    emit '{"session_id":"s-1","cwd":"/x","hook_event_name":"PostToolUse","tool_name":"Read","tool_response":{"stdout":"'"$big"'"}}'
    # Far more than any machine sees, so a lock that lets two writers in shows up on every run.
    i=0
    while [ "$i" -lt 200 ]; do
        emit '{"session_id":"s-2","cwd":"/x","hook_event_name":"PreToolUse","tool_name":"Bash"}' &
        i=$((i + 1))
    done
    wait

    # Not through `remote`: $! has to be the shim itself, not a subshell around it.
    HOME=$home PATH=$path $shell "$home/.ambient/bin/ambient-remote" follow --since 2 --heartbeat 1 > "$home/follow" 2> "$home/follow.err" &
    follower=$!
    sleep 2
    printf '%s\n' 'this line is not json' >> "$home/.ambient/spool/events.jsonl"
    emit '{"session_id":"s-1","cwd":"/x","hook_event_name":"SessionEnd"}'
    printf '%s\n%s\n%s\n\n' 999999 '' ghost > "$home/.ambient/spool/live/claude.ghost-1"
    printf '%s\n%s\n%s\n\n' "$$" '' alive > "$home/.ambient/spool/live/claude.alive-1"
    sleep 7
    kill "$follower" 2> /dev/null || :
    wait "$follower" 2> /dev/null || :

    # A live holder keeps the lock for as long as it takes; one that's gone loses it.
    ln -s "$$" "$home/.ambient/spool/lock.holder"
    emit '{"session_id":"s-4","cwd":"/x","hook_event_name":"PreToolUse","tool_name":"Bash"}' &
    sleep 1
    grep -c '"s-4"' "$home/.ambient/spool/events.jsonl" > "$home/held" || :
    rm "$home/.ambient/spool/lock.holder"
    wait
    ln -s 999999 "$home/.ambient/spool/lock.holder"
    emit '{"session_id":"s-5","cwd":"/x","hook_event_name":"PreToolUse","tool_name":"Bash"}'

    cp "$home/.ambient/spool/events.jsonl" "$home/events"
    sed 's/spool_max_bytes=.*/spool_max_bytes=2048/' "$home/.ambient/remote.conf" > "$home/conf"
    cp "$home/conf" "$home/.ambient/remote.conf"
    i=0
    while [ "$i" -lt 30 ]; do
        emit '{"session_id":"s-3","cwd":"/x","hook_event_name":"PreToolUse","tool_name":"Bash"}'
        i=$((i + 1))
    done
    wc -c "$home/.ambient/spool"/events* | tail -n 1 > "$home/spool-bytes"

    if python3 scripts/test-remote-shim.py "$home" "$name"; then
        echo "ok   $name"
    else
        echo "FAIL $name"
        failures=$((failures + 1))
    fi
    # Without python3 the hooks are the user's to remove, which is status 3. Everything else still goes.
    want=0
    (PATH=$path; command -v python3) > /dev/null 2>&1 || want=3
    got=0
    remote uninstall > /dev/null || got=$?
    [ "$got" -eq "$want" ] || { echo "FAIL $name: uninstall exited $got, not $want"; failures=$((failures + 1)); }
    [ ! -e "$home/.ambient/spool" ] && [ ! -e "$home/.ambient/bin/ambient-remote" ] ||
        { echo "FAIL $name: spool or shim left behind"; failures=$((failures + 1)); }
}

missing() {
    echo "skip $1"
    [ -z "${REQUIRE_ALL:-}" ] || failures=$((failures + 1))
}

if command -v dash > /dev/null 2>&1; then check dash-system dash "$SYSTEM_PATH"; else missing dash-system; fi
if command -v bash > /dev/null 2>&1; then check bash-system "bash --posix" "$SYSTEM_PATH"; else missing bash-system; fi
if command -v mawk > /dev/null 2>&1; then check dash-mawk dash "$(with_awk mawk)"; else missing dash-mawk; fi
if command -v gawk > /dev/null 2>&1; then check bash-gawk bash "$(with_awk gawk)"; else missing bash-gawk; fi
if command -v busybox > /dev/null 2>&1; then check busybox "$(command -v busybox) ash" "$(busybox_path):"; else missing busybox; fi

[ "$failures" -eq 0 ] && echo "All good." || { echo "$failures failed."; exit 1; }
