#!/bin/zsh
# MEM-012 · Text over 32 KB, files over 50 MB and a 201st entry are refused with a way forward.
# needs-app: yes
# timeout: 240
source "$QA_REPO/qa/run/lib.sh"
source "$QA_REPO/qa/run/mem-lib.sh"

git_repo "$QA_ROOT/qa-mem"
cd "$QA_ROOT/qa-mem"
too_big="The value is 32 KB; text is limited to 32 KB. Share it as a file instead."

head -c 32768 /dev/zero | tr '\0' a | ambient memory set big >/dev/null || fail "step 1: 32,768 bytes refused"
err=$(head -c 32769 /dev/zero | tr '\0' a | ambient memory set big 2>&1); code=$?
assert_eq "$code" 1 "step 1: 32,769 bytes exit code"
assert_contains "$err" "$too_big" "step 1: 32,769 bytes"
# UTF-8 bytes, not characters: 16,385 two-byte characters are 32,770 bytes.
err=$(printf 'é%.0s' {1..16385} | ambient memory set big 2>&1)
assert_contains "$err" "$too_big" "16,385 é (32,770 bytes)"

err=$(ambient memory set empty "" 2>&1)
assert_contains "$err" "The value is empty. Use memory_forget to remove an entry." "step 2"

mkfile 51m big.bin
ln -s big.bin link.bin
for f in big.bin link.bin; do
  err=$(ambient memory set bin --file $f 2>&1)
  assert_contains "$err" "The file is 51 MB; shared files are limited to 50 MB." "step 3 $f"
done
copies=$(ls "$AMBIENT_HOME/memory" 2>/dev/null | grep -cE '^[0-9a-f]{64}$')
assert_eq "$copies" 0 "step 3 copies made under memory/"

git_repo "$QA_ROOT/scratch"
cd "$QA_ROOT/scratch"
for i in {0..199}; do ambient memory set k$i x >/dev/null || fail "write k$i"; done
err=$(ambient memory set k200 x 2>&1); code=$?
assert_eq "$code" 1 "step 4 k200 exit code"
assert_contains "$err" "scratch already holds 200 entries. Forget some first." "step 4 k200"
ambient memory set k0 y >/dev/null || fail "step 4 replacing k0 refused"
ambient memory set k200 x --global >/dev/null || fail "step 4 k200 --global refused"

# Expired entries don't count toward the 200.
git_repo "$QA_ROOT/scratch2"
cd "$QA_ROOT/scratch2"
ambient memory set short x --ttl 1 >/dev/null || fail "write short"
made=$EPOCHSECONDS
for i in {1..199}; do ambient memory set k$i x >/dev/null || fail "scratch2 write k$i"; done
sleep_until $(( made + 62 ))
ambient memory set k200 x >/dev/null || fail "an expired entry still counted toward the 200"
