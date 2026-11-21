#!/bin/zsh
# SET-017 · Remove takes out only Ambient's entries.
# needs-app: no
# checks: part
# Left to a person: the Not connected badge and the menu bar showing no hooks-removed problem. The CLI's
# install/uninstall stand in for Connect and Remove (same HookInstaller and agent record).
source "$QA_REPO/qa/run/lib.sh"
export AMBIENT_HOME="$HOME/.ambient"

fake_agent claude
f="$HOME/.claude/settings.json"
# As Claude Code writes it: two-space JSON, the user's own PreToolUse group and other settings.
cat > "$f" <<'JSON'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "model": "opus",
  "env": {
    "FOO": "bar"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo mine"
          }
        ]
      }
    ]
  },
  "includeCoAuthoredBy": false,
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
JSON
cp -p "$f" "$QA_ROOT/before.json"
ambient install claude >/dev/null || fail "install exited $?"
assert_json "$AMBIENT_HOME/agents.json" '.connected | index("claude") != null' true
ambient uninstall claude >/dev/null || fail "uninstall exited $?"
d=$(diff "$QA_ROOT/before.json" "$f") || fail "settings.json differs after connect then remove:
$d"
assert_json "$AMBIENT_HOME/agents.json" '.connected | index("claude") == null' true
note "byte-for-byte as before; agents.json no longer lists claude"
