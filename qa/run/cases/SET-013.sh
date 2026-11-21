#!/bin/zsh
# SET-013 · Antigravity alone also makes Gemini CLI look installed.
# needs-app: no
# checks: part
# Known gap. Checks the README promise (*hook up every agent it found*): with only Antigravity's folder, connecting
# everything must not write Gemini CLI hooks. `ambient install` with no agent uses the same detection
# (HookInstaller.agentExists) as Connect All, which only adds the not-connected filter.
# Left to a person: the Gemini CLI badge in Settings › Agents and the Connect All button itself.
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

mkdir -p "$HOME/.gemini/antigravity"
doc=$(ambient doctor 2>&1)
note "doctor before: $(print -r -- "$doc" | grep 'Gemini:')"
ambient install >/dev/null 2>&1
assert_file "$HOME/.gemini/config/hooks.json"
assert_no_file "$HOME/.gemini/settings.json"
