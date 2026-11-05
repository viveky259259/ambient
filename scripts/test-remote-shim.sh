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

# What `follow` runs as awk, with a rotation landing while it streams and an `emit` right behind it, as on a busy
# machine. ROTATE=before lands it before awk opens anything; ROTATE=between lands it once awk is done with its first
# file. `$HOME/rotate` is used up, so it happens once. Every other use of awk goes straight through.
race_awk() {
    bin=$ROOT/bin-race
    mkdir -p "$bin"
    cat > "$bin/awk" <<'EOF'
#!/bin/sh
rotate() {
    rm "$HOME/rotate"
    mv -f "$HOME/.ambient/spool/events.jsonl" "$HOME/.ambient/spool/events.1.jsonl"
    printf '%s' '{"session_id":"s-6","cwd":"/x","hook_event_name":"PreToolUse","tool_name":"Bash"}' |
        "$HOME/.ambient/bin/ambient-remote" emit claude
}
case ${2:-} in from=*) [ -e "$HOME/rotate" ] || exec "$REAL_AWK" "$@" ;; *) exec "$REAL_AWK" "$@" ;; esac
from=$2 to=$4 cutoff=$6 program=$7
shift 7
if [ "$ROTATE" = between ]; then
    "$REAL_AWK" -v "$from" -v "$to" -v "$cutoff" "$program" "$1"
    shift
fi
rotate
exec "$REAL_AWK" -v "$from" -v "$to" -v "$cutoff" "$program" "$@"
EOF
    chmod 755 "$bin/awk"
    echo "$bin"
}

# Every awk that reads the voice outbox for `follow`, logged as "whole" for the file or "tail" for what's past an offset.
voice_awk() {
    bin=$ROOT/bin-voice
    mkdir -p "$bin"
    cat > "$bin/awk" <<'EOF'
#!/bin/sh
read_kind=
for arg; do
    case $arg in
        hub=*) [ -n "$read_kind" ] || read_kind=whole ;;
        expect=*) read_kind=tail ;;
    esac
done
[ -z "$read_kind" ] || echo "$read_kind" >> "$HOME/voice-reads"
exec "$REAL_AWK" "$@"
EOF
    chmod 755 "$bin/awk"
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

    # The hub asks a machine who it is before changing anything there, by sending this script on stdin.
    fresh=$ROOT/fresh-$name
    mkdir -p "$fresh"
    HOME=$fresh AMBIENT_REMOTE_HOSTKEYS=/nonexistent PATH=$path $shell -s identity < "$SHIM" > "$home/identity"
    [ "$(cat "$home/identity")" = "id:" ] && [ -z "$(ls -A "$fresh")" ] ||
        { echo "FAIL $name: asking who a machine is changed it"; failures=$((failures + 1)); }

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

    # Events 1 and 2 are in the rotated file and already sent, and 3 to 5 are in the live one when `follow` starts.
    # `quiet` is a rotation with nothing written since, which leaves no live file at all.
    race() {
        rm -rf "$home/.ambient/spool"
        for i in 1 2 3 4 5; do
            [ "$i" -ne 3 ] || mv "$home/.ambient/spool/events.jsonl" "$home/.ambient/spool/events.1.jsonl"
            emit '{"session_id":"s-6","cwd":"/x","hook_event_name":"PreToolUse","tool_name":"Bash"}'
        done
        if [ "$1" = quiet ]; then
            mv "$home/.ambient/spool/events.jsonl" "$home/.ambient/spool/events.1.jsonl"
        else
            : > "$home/rotate"
        fi
        HOME=$home PATH=$(race_awk):$path ROTATE=$1 REAL_AWK=$(PATH=$path; command -v awk) \
            $shell "$home/.ambient/bin/ambient-remote" follow --since 2 --heartbeat 1 > "$home/raced-$1" 2> /dev/null &
        follower=$!
        i=0
        while [ "$i" -lt 50 ] && ! grep -qs "\"seq\":$2," "$home/raced-$1"; do
            sleep 0.1
            i=$((i + 1))
        done
        kill "$follower" 2> /dev/null || :
        wait "$follower" 2> /dev/null || :
    }
    rm "$home/.ambient/remote.conf"
    race before 6
    race between 6
    race quiet 5

    # Voices from the Ambient app on this machine: a hub that says who it is gets only its own, from its cursor on.
    mine=5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a
    theirs=7777777777777777777777777777777f
    mkdir -p "$home/.ambient/voice-sync"
    for voice_line in "1 $mine" "2 $theirs" "3 $mine" "4 $theirs" "5 $mine"; do
        set -- $voice_line
        printf '{"v":1,"type":"voice","vseq":%s,"to":"%s","voice":"%032d","part":"cancel"}\n' "$1" "$2" "$1"
    done > "$home/.ambient/voice-sync/outbox.jsonl"
    # As an app from before 1.0.6 writes it: the vseq alone, so `follow` reads the whole file each time.
    echo 5 > "$home/.ambient/voice-sync/outbox.seq"
    read -r voice_since _ < "$home/.ambient/spool/seq"
    HOME=$home PATH=$path $shell "$home/.ambient/bin/ambient-remote" follow --since "$voice_since" --heartbeat 1 \
        --hub "$mine" --hub-label "Mac Studio" --voice-since 1 > "$home/voices" 2> "$home/voices.err" &
    follower=$!
    sleep 2
    kill "$follower" 2> /dev/null || :
    wait "$follower" 2> /dev/null || :
    cp "$home/.ambient/spool/hubs/$mine" "$home/hub-label" 2> /dev/null || :
    # A hub id that isn't one gets the stream it always did.
    HOME=$home PATH=$path $shell "$home/.ambient/bin/ambient-remote" follow --since "$voice_since" --heartbeat 1 \
        --hub "x;y" --hub-label "Bad'Name" > "$home/voices-bad" 2> /dev/null &
    follower=$!
    sleep 1
    kill "$follower" 2> /dev/null || :
    wait "$follower" 2> /dev/null || :

    # Offsets: the app writes "<epoch> <bytes> <generation>" under the vseq, and `follow` reads on from where the file
    # ended after the last line it sent, until a rewrite moves the generation on. Lines 2 and 3 are the catch-up.
    vdir=$home/.ambient/voice-sync
    vepoch=0123456789abcdef
    vgen=0
    vline() {
        printf '{"v":1,"type":"voice","vseq":%s,"to":"%s","voice":"%032d","part":"cancel"}\n' "$1" "$mine" "$1" >> "$vdir/outbox.jsonl"
    }
    # As the app does it: the line, then outbox.seq replaced.
    vappend() {
        vline "$1"
        set -- "$1" $(wc -c < "$vdir/outbox.jsonl")
        printf '%s\n%s %s %s\n' "$1" "$vepoch" "$2" "$vgen" > "$vdir/outbox.seq.new"
        mv -f "$vdir/outbox.seq.new" "$vdir/outbox.seq"
    }
    # Rewrites the file without line $1, in one step.
    vdrop() {
        grep -v "\"vseq\":$1," "$vdir/outbox.jsonl" > "$vdir/outbox.jsonl.new"
        mv -f "$vdir/outbox.jsonl.new" "$vdir/outbox.jsonl"
    }
    vawait() {
        i=0
        while [ "$i" -lt 50 ] && ! grep -qs "\"vseq\":$1," "$home/offsets"; do
            sleep 0.1
            i=$((i + 1))
        done
    }
    # A machine with no outbox at all, as most a hub follows are: `follow` keeps going, and sends no voices.
    mv -f "$vdir" "$vdir.aside"
    HOME=$home PATH=$path $shell "$home/.ambient/bin/ambient-remote" follow --since "$voice_since" --heartbeat 1 \
        --hub "$mine" --hub-label "Mac Studio" --voice-since 0 --voice-epoch > "$home/no-outbox" 2> "$home/no-outbox.err" &
    follower=$!
    sleep 2.5
    kill "$follower" 2> /dev/null || :
    wait "$follower" 2> /dev/null || :
    mv -f "$vdir.aside" "$vdir"
    : > "$vdir/outbox.jsonl"
    : > "$home/voice-reads"
    for i in 1 2 3; do vappend "$i"; done
    HOME=$home PATH=$(voice_awk):$path REAL_AWK=$(PATH=$path; command -v awk) $shell "$home/.ambient/bin/ambient-remote" \
        follow --since "$voice_since" --heartbeat 1 --hub "$mine" --hub-label "Mac Studio" --voice-since 1 --voice-epoch \
        > "$home/offsets" 2> "$home/offsets.err" &
    follower=$!
    vawait 3
    vappend 4; vawait 4
    vappend 5; vawait 5
    # The app's trim: lines 1 and 2 go, every other line moves, and the generation says so.
    vdrop 1; vdrop 2; vgen=1
    vappend 6; vawait 6
    vappend 7; vawait 7
    # A rewrite the generation doesn't show yet, as when one lands between `follow` reading outbox.seq and opening the
    # file: line 3 goes, so where line 8 should start, line 9 does.
    vdrop 3
    vline 8
    vappend 9; vawait 9
    vappend 10; vawait 10
    # A new outbox: `follow` hangs up by itself, so the hub hears of it in the next hello.
    vepoch=fedcba9876543210
    vappend 11
    i=0
    while [ "$i" -lt 30 ] && kill -0 "$follower" 2> /dev/null; do
        sleep 0.1
        i=$((i + 1))
    done
    if kill -0 "$follower" 2> /dev/null; then echo stayed; else echo hung up; fi > "$home/epoch-change"
    kill "$follower" 2> /dev/null || :
    wait "$follower" 2> /dev/null || :
    # A hub from before 1.0.6 doesn't ask, and gets the hello it knows.
    HOME=$home PATH=$path $shell "$home/.ambient/bin/ambient-remote" follow --since "$voice_since" --heartbeat 1 \
        --hub "$mine" --hub-label "Mac Studio" --voice-since 11 > "$home/offsets-unasked" 2> /dev/null &
    follower=$!
    sleep 1
    kill "$follower" 2> /dev/null || :
    wait "$follower" 2> /dev/null || :

    if python3 scripts/test-remote-shim.py "$home" "$name"; then
        echo "ok   $name"
    else
        echo "FAIL $name"
        failures=$((failures + 1))
    fi
    # Without python3 the hooks are the user's to remove, which is status 3. Everything else still goes.
    want=0
    (PATH=$path; command -v python3) > /dev/null 2>&1 || want=3
    # What uninstall rewrites can hold secrets, so the copy it writes first must be private from the start.
    mkdir -p "$home/wrapped"
    if [ "$want" -eq 0 ]; then
        printf '#!/bin/sh\numask > "$HOME/uninstall-umask"\nexec "%s" "$@"\n' "$(PATH=$path; command -v python3)" > "$home/wrapped/python3"
        chmod 700 "$home/wrapped/python3"
    fi
    got=0
    (umask 022; HOME=$home PATH=$home/wrapped:$path $shell "$home/.ambient/bin/ambient-remote" uninstall > /dev/null) || got=$?
    [ "$got" -eq "$want" ] || { echo "FAIL $name: uninstall exited $got, not $want"; failures=$((failures + 1)); }
    if [ "$want" -eq 0 ]; then
        case $(cat "$home/uninstall-umask") in
            *77) ;;
            *) echo "FAIL $name: uninstall edits configs under a umask of $(cat "$home/uninstall-umask")"; failures=$((failures + 1)) ;;
        esac
    fi
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
