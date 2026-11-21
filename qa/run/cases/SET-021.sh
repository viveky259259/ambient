#!/bin/zsh
# SET-021 · A symlinked config stays a symlink and keeps its permissions.
# needs-app: no
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
mkdir -p "$HOME/dotfiles/claude"
target="$HOME/dotfiles/claude/settings.json"
printf '{\n  "model": "opus"\n}\n' > "$target"
chmod 600 "$target"
ln -s "$target" "$HOME/.claude/settings.json"

ambient install claude >/dev/null || fail "install exited $?"
[[ -L "$HOME/.claude/settings.json" ]] || fail "~/.claude/settings.json is no longer a symlink"
assert_eq "$(readlink "$HOME/.claude/settings.json")" "$target" "symlink target"
assert_eq "$(jq '.hooks.Stop | length' "$target")" 1 "Ambient's Stop group in the target"
assert_contains "$(cat "$target")" 'hook claude' "the target's hooks"
assert_mode "$target" 600
note "still a link to the dotfiles copy, mode 600"
