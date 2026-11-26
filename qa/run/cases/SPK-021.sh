#!/bin/zsh
# SPK-021 · The offline model downloads only on Download, from pinned sources, checked by hash and signature.
# needs-app: no
# checks: part
# Left to a person: step 1 making no request; step 2's requests as a network monitor sees them, the helper zip from
# github.com/viveky259259/ambient/releases/download/voice-1 among them; step 3's mismatch message, with nothing left in
# ~/.ambient/voice/kokoro-1; the dev build's signature message.
# Reads the model files compiled into this build with `ambient voice-files` (one "path url sha256" per line), the list
# step 2 downloads besides the helper. Nothing is downloaded.
source "$QA_REPO/qa/run/lib.sh"

out=$(ambient voice-files) || fail "ambient voice-files exited $?"
[[ -n $out ]] || fail "ambient voice-files printed nothing"
pinned='https://huggingface.co/prince-canuma/Kokoro-82M/resolve/e02c9ea'
n=0
while read -r path url sha extra; do
  (( ++n ))
  [[ -z ${extra:-} ]] || fail "line $n has more than three fields: $path $url $sha $extra"
  [[ $url == https://* ]] || fail "$path is not fetched over HTTPS: $url"
  [[ $url == $pinned* ]] || fail "$path comes from outside the pinned Kokoro-82M commit: $url"
  [[ $url == */$path ]] || fail "$path is fetched from a URL for another file: $url"
  [[ $sha =~ '^[0-9a-f]{64}$' ]] || fail "$path has no SHA-256 pin: [$sha]"
  [[ $path != /* && $path != *..* ]] || fail "$path would land outside the pack folder"
done <<< "$out"
note "$n model files, all HTTPS from the pinned commit, each with a SHA-256"
assert_contains "$out" "voices/af_heart.safetensors $pinned" "step 3's voice file in the list"
assert_contains "$out" "kokoro-v1_0.safetensors $pinned" "the model weights in the list"
