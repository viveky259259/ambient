#!/bin/zsh
# SET-022 · Copilot and OpenCode files don't follow symlinks or keep modes.
# needs-app: no
# Known gap: owned files are written atomically at the link's own path. `ambient install opencode` stands in for
# the Update button (same HookInstaller).
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent opencode
mkdir -p "$HOME/dotfiles" "$HOME/.config/opencode/plugins"
target="$HOME/dotfiles/ambient.js"
print -r -- '// an older Ambient plugin' > "$target"
chmod 600 "$target"
link="$HOME/.config/opencode/plugins/ambient.js"
ln -s "$target" "$link"

ambient install opencode >/dev/null || fail "install exited $?"
[[ -L "$link" ]] || fail "plugins/ambient.js is no longer a symlink"
assert_eq "$(readlink "$link")" "$target" "symlink target"
assert_contains "$(cat "$target")" 'ambient install opencode' "the dotfiles copy's contents"
assert_mode "$target" 600
