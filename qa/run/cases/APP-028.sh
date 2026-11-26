#!/bin/zsh
# APP-028 · `ambient help` lists every command.
source "$QA_REPO/qa/run/lib.sh"

version=$(sed -n 's/.*current = "\(.*\)".*/\1/p' "$QA_REPO/Sources/AmbientBase/Version.swift")
for args in help --help -h ""; do
  # With AMBIENT_HOME empty, paths fall back to ~/.ambient (the throwaway home's), as on a user's Mac.
  out=$(AMBIENT_HOME= ambient ${=args} 2>&1)
  assert_eq "$?" 0 "exit code of [ambient $args]"
  assert_eq "${out%%$'\n'*}" "ambient $version — ambient desktop status for coding agents" "first line of [ambient $args]"
  usage=${out#*$'\n'Usage$'\n'}
  [[ $usage != "$out" ]] || fail "no Usage section in [ambient $args]"
  for cmd in install uninstall status tasks task memory mcp remote doctor emit demo open ack version; do
    print -r -- "$usage" | grep -qE "^  ambient $cmd( |$)" || fail "[ambient $args] does not list $cmd"
  done
  assert_contains "$out" "set AMBIENT_DEBUG=1 to log them to ~/.ambient/logs/hook.log" "[ambient $args]"
done
