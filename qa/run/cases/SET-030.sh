#!/bin/zsh
# SET-030 · ambient uninstall removes only Ambient's hooks, from every agent.
# needs-app: no
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

for a in claude codex gemini cursor copilot opencode; do fake_agent $a; done
mkdir -p "$HOME/.gemini/antigravity" "$HOME/.gemini/config"
own() { # file event-key
  cat > "$1" <<JSON
{
  "hooks": {
    "$2": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo mine"
          }
        ]
      }
    ]
  }
}
JSON
}
own "$HOME/.claude/settings.json" PreToolUse
own "$HOME/.codex/hooks.json" Stop
own "$HOME/.gemini/settings.json" AfterAgent
cat > "$HOME/.cursor/hooks.json" <<'JSON'
{
  "version": 1,
  "hooks": {
    "stop": [
      {
        "command": "say done"
      }
    ]
  }
}
JSON
cat > "$HOME/.gemini/config/hooks.json" <<'JSON'
{
  "mine": {
    "Stop": [
      {
        "type": "command",
        "command": "echo mine",
        "timeout": 3
      }
    ]
  }
}
JSON
print -r -- '{"model":"gpt-5"}' > "$HOME/.copilot/config.json"
print -r -- '{}' > "$HOME/.config/opencode/opencode.json"
dirs=(.claude .codex .gemini .cursor .copilot .config/opencode)
snapshot() { (cd "$HOME" && find $dirs -type f -exec shasum {} + | sort) }
before=$(snapshot)

ambient install >/dev/null 2>&1 || fail "install exited $?"
out=$(ambient uninstall 2>&1); code=$?
assert_eq "$code" 0 "uninstall exit code"
want="✓ Claude: hooks removed from ~/.claude/settings.json
✓ Codex: hooks removed from ~/.codex/hooks.json
✓ Gemini: hooks removed from ~/.gemini/settings.json
✓ Antigravity: hooks removed from ~/.gemini/config/hooks.json
✓ Cursor: hooks removed from ~/.cursor/hooks.json
✓ Copilot: hooks removed from ~/.copilot/hooks/ambient.json
✓ OpenCode: hooks removed from ~/.config/opencode/plugins/ambient.js"
assert_eq "$out" "$want" "uninstall output"

hits=$(cd "$HOME" && grep -rl 'bin/ambient' $dirs 2>/dev/null)
assert_eq "$hits" "" "files still naming bin/ambient"
assert_no_file "$HOME/.copilot/hooks/ambient.json"
assert_no_file "$HOME/.config/opencode/plugins/ambient.js"
assert_json "$HOME/.gemini/config/hooks.json" 'has("ambient")' false
assert_json "$HOME/.gemini/config/hooks.json" '.mine.Stop[0].command' "echo mine"
after=$(snapshot)
d=$(diff <(print -r -- "$before") <(print -r -- "$after")) || fail "config files differ from before connecting:
$d"
assert_json "$AMBIENT_HOME/agents.json" '.connected | length' 0

out=$(ambient uninstall 2>&1) || fail "second uninstall exited $?"
for name in Claude Codex Gemini Antigravity Cursor Copilot OpenCode; do
  assert_contains "$out" "– $name: nothing to remove" "second uninstall"
done
note "seven agents removed, every file as before, agents.json empty"
