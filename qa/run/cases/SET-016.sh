#!/bin/zsh
# SET-016 · Connect OpenCode writes the plugin, and edits to it are put back.
# needs-app: yes
# timeout: 180
# checks: part
# The header and CLI path are checked in a second throwaway home whose AMBIENT_HOME is ~/.ambient (the app's
# AMBIENT_HOME here is outside HOME, which makes the plugin use an absolute path). The repair is checked against the
# running QA app. Left to a person: an OpenCode session on the island, and Settings › Agents briefly showing
# Needs update.
source "$QA_REPO/qa/run/lib.sh"

# The plugin as written on a Mac with the default layout.
h2="$QA_ROOT/home2"
mkdir -p "$h2/.config/opencode"
HOME=$h2 AMBIENT_HOME=$h2/.ambient ambient install opencode >/dev/null || fail "install in the second home exited $?"
p2="$h2/.config/opencode/plugins/ambient.js"
src=$(<"$p2")
assert_contains "$src" '`ambient install opencode` wrote this file' "plugin header"
assert_contains "$src" 'Edits are overwritten.' "plugin header"
assert_contains "$src" 'const cli = join(homedir(), ".ambient/bin/ambient")' "how the plugin finds the CLI"
assert_eq "$(grep -c '^export default' "$p2")" 1 "default exports"
exports=$(HOME=$h2 PLUGIN=$p2 node --input-type=module -e '
  const m = await import(process.env.PLUGIN)
  const d = m.default
  console.log(JSON.stringify({ named: Object.keys(m).filter((k) => k !== "default"), keys: Object.keys(d), id: d.id,
    server: typeof d.server, setup: typeof d.setup }))') || fail "node could not load the plugin"
assert_eq "$exports" '{"named":[],"keys":["id","server","setup"],"id":"ambient","server":"function","setup":"function"}' "the plugin's exports"

# An edit is put back by the running app's hook check, with the edited copy backed up.
fake_agent opencode
p="$HOME/.config/opencode/plugins/ambient.js"
ambient install opencode >/dev/null || fail "install exited $?"
cp "$p" "$QA_ROOT/ambients.js"
print -r -- '// my comment' >> "$p"
cp "$p" "$QA_ROOT/edited.js"
start=$SECONDS
wait_for 150 cmp -s "$p" "$QA_ROOT/ambients.js"
note "rewritten $((SECONDS - start)) s after the edit"
found=0
for b in "$AMBIENT_HOME"/backups/opencode-ambient-*.js(N); do cmp -s "$b" "$QA_ROOT/edited.js" && found=1; done
assert_eq "$found" 1 "a backup holding the edited plugin"
