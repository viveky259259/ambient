#!/bin/zsh
# MEM-010 · A shared file is a read-only copy whose path `memory_read` returns.
# needs-app: yes
# Stand-in Claude Code (working in qa-mem/src) and Codex processes call `ambient mcp`, as the real agents would.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
mkdir -p "$QA_ROOT/qa-mem/src"
src=$(real "$QA_ROOT/qa-mem/src")
print 'build ok' > "$src/build.log"
mkdir "$src/folder"
mkfifo "$src/pipe"

out=$(agent_run claude mem-010 "$src" <<EOF
$(call memory_write_file '{"key":"build-log","path":"build.log"}')
$(call memory_write_file '{"key":"f","path":"folder"}')
$(call memory_write_file '{"key":"f","path":"missing.log"}')
$(call memory_write_file '{"key":"f","path":"pipe"}')
EOF
)
w=$(sed -n 2p <<< $out)
note "write: $w"
assert_eq "$(jq -r .isError <<< $w)" false "step 1 isError (relative to the folder the agent works in)"
file=$(jq -r .text <<< $w | jq -r .file)
[[ $file =~ "^$AMBIENT_HOME/memory/[0-9a-f]{64}/build.log\$" ]] || fail "step 1 file is [$file]"
assert_eq "$(jq -r .text <<< $w | jq -r .size)" 9 "step 1 size"

r=$(agent_run codex mem-010-codex "$(real "$QA_ROOT/qa-mem")" <<EOF | sed -n 2p
$(call memory_read '{"key":"build-log"}')
EOF
)
assert_eq "$(jq -r .text <<< $r | jq -r .file)" "$file" "step 2 memory_read returns the copy's path"
err=$( { print 'appended' >> "$file"; } 2>&1 ); code=$?
assert_ne "$code" 0 "step 2 append to the copy succeeded"
assert_contains "$err" "ermission denied" "step 2 append error"
assert_mode "$file" 400
assert_mode "${file:h}" 700

print 'build changed' > "$src/build.log"
assert_eq "$(ambient memory get build-log --in "$src" | xargs cat)" "build ok" "step 3 the copy keeps the original content"

print "build ok" > "$src/build.log"
ambient memory set build-log-2 --file "$src/build.log" >/dev/null || fail "step 4 share"
assert_eq "$(ls "$AMBIENT_HOME/memory" | grep -cE '^[0-9a-f]{64}$')" 1 "step 4 copy folders"

assert_eq "$(sed -n 3p <<< $out | jq -r .text)" "$src/folder is a folder. Share its files one at a time, or an archive of it." "folder refusal"
assert_eq "$(sed -n 4p <<< $out | jq -r .text)" "There's no file at $src/missing.log." "missing file refusal"
assert_eq "$(sed -n 5p <<< $out | jq -r .text)" "$src/pipe isn't a regular file." "named pipe refusal"
