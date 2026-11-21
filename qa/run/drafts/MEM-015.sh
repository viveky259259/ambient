#!/bin/zsh
# MEM-015 · Secret files and files from `~/.ssh`, `~/.aws`, `~/.gnupg` are refused.
# needs-app: yes
# ~ is this case's throwaway home: its .ssh and .aws hold made-up files, never the real ones.
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"
mkdir -p "$HOME/.ssh" "$HOME/.aws" "$HOME/.gnupg"
print 'Host qa-nowhere' > "$HOME/.ssh/config"
print '[default]' > "$HOME/.aws/config"
print 'x' > "$HOME/.gnupg/gpg.conf"
copies() { ls -A "$AMBIENT_HOME/memory" 2>/dev/null | wc -l | tr -d ' '; }
before=$(copies)

for name in .env .env.local prod.env server.pem id_ed25519 .npmrc credentials.json; do
  print 'one line' > $name
  err=$(ambient memory set f --file $name 2>&1); code=$?
  assert_eq "$code" 1 "step 1 $name exit code"
  assert_contains "$err" "$name usually holds secrets, and every agent on this Mac can read shared memory, so Ambient doesn't share it." "step 1 $name"
done
for dir in .ssh .aws .gnupg; do
  f=$(ls "$HOME/$dir" | head -1)
  err=$(ambient memory set f --file ~/$dir/$f 2>&1)
  assert_contains "$err" "Anything in ~/$dir usually holds secrets, and every agent on this Mac can read shared memory, so Ambient doesn't share it." "step 2 ~/$dir/$f"
done
ln -s "$HOME/.ssh/config" notes.txt
err=$(ambient memory set f --file notes.txt 2>&1)
assert_contains "$err" "Anything in ~/.ssh usually holds secrets" "step 3 a link is judged by what it points to"

print "aws_access_key_id = AKIA${(l:16::Q:)}" > config.yml
err=$(ambient memory set f --file config.yml 2>&1)
assert_contains "$err" "That looks like it contains an AWS access key." "step 4 config.yml"
assert_eq "$(copies)" "$before" "entries under memory/ after the refusals"

print 'API_KEY=' > .env.example
ambient memory set example --file .env.example >/dev/null || fail "step 4 .env.example refused"

# Only the first 1 MB is scanned.
{ head -c 1048576 /dev/zero | tr '\0' x; print "\nghp_${(l:36::a:)}"; } > late.log
ambient memory set late --file late.log >/dev/null || fail "a token after the first 1 MB was caught"
