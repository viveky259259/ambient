#!/bin/zsh
# One-time setup of the secrets the Release and Deploy site workflows need. Values come from files and
# hidden prompts and go straight to `gh secret set`; nothing is printed. Optionally keeps a copy in the
# private secrets repo, per the secrets policy.
set -euo pipefail
REPO=viveky259259/ambient
SECRETS_ROOT=${SECRETS_ROOT:-$HOME/Documents/Projects/secrets}
SECRETS_DIR=$SECRETS_ROOT/ambient-notification

ask_file() {
  local answer
  read "answer?$1: "
  answer=${answer/#\~/$HOME}
  answer=${answer//\\ / }
  [[ -f $answer ]] || { echo "Not found: $answer" >&2; exit 1; }
  print -r -- "$answer"
}
ask_hidden() {
  local answer
  read -s "answer?$1: "
  echo >&2
  [[ -n $answer ]] || { echo "Nothing entered." >&2; exit 1; }
  print -rn -- "$answer"
}
put() { gh secret set "$1" -R "$REPO" >/dev/null && echo "  ✓ $1"; }

gh auth status >/dev/null 2>&1 || { echo "Sign in to gh first: gh auth login" >&2; exit 1; }

cat <<'TXT'

1/3  Developer ID certificate
     Keychain Access → My Certificates → "Developer ID Application: Vivek Yadav (CU3457GT8T)"
     (any one of the identical copies) → File → Export Items… → Personal Information Exchange (.p12),
     with a password. Include only that one certificate.
TXT
P12=$(ask_file "Path to the .p12")
P12_PASSWORD=$(ask_hidden "The .p12's password")
base64 -i "$P12" | put DEVELOPER_ID_P12_BASE64
print -rn -- "$P12_PASSWORD" | put DEVELOPER_ID_P12_PASSWORD

cat <<'TXT'

2/3  Notarization API key
     App Store Connect → Users and Access → Integrations → Team Keys → "+" (access: Developer).
     Download the AuthKey_XXXXXXXXXX.p8 (possible only once) and note the Key ID and Issuer ID.
TXT
P8=$(ask_file "Path to the .p8")
read "KEY_ID?Key ID: "
read "ISSUER_ID?Issuer ID: "
base64 -i "$P8" | put NOTARY_KEY_P8_BASE64
print -rn -- "$KEY_ID" | put NOTARY_KEY_ID
print -rn -- "$ISSUER_ID" | put NOTARY_ISSUER_ID

cat <<'TXT'

3/3  Netlify
     app.netlify.com → User settings → Applications → Personal access tokens → New access token.
TXT
NETLIFY_TOKEN=$(ask_hidden "Token")
print -rn -- "$NETLIFY_TOKEN" | put NETLIFY_AUTH_TOKEN

if [[ -d $SECRETS_ROOT/.git ]]; then
  echo
  read "yn?Also keep a copy in $SECRETS_DIR and push the secrets repo? [y/N] "
  if [[ $yn == [yY] ]]; then
    mkdir -p "$SECRETS_DIR"
    cp "$P12" "$SECRETS_DIR/developer-id.p12"
    cp "$P8" "$SECRETS_DIR/notary-${KEY_ID}.p8"
    umask 077
    {
      print -r -- "DEVELOPER_ID_P12_PASSWORD=$P12_PASSWORD"
      print -r -- "NOTARY_KEY_ID=$KEY_ID"
      print -r -- "NOTARY_ISSUER_ID=$ISSUER_ID"
      print -r -- "NETLIFY_AUTH_TOKEN=$NETLIFY_TOKEN"
    } > "$SECRETS_DIR/ci.env"
    git -C "$SECRETS_ROOT" add ambient-notification
    git -C "$SECRETS_ROOT" commit -q -m "ambient-notification: CI release secrets"
    git -C "$SECRETS_ROOT" push -q && echo "  ✓ secrets repo updated"
  fi
fi

echo
echo "Done. Secrets now set:"
gh secret list -R "$REPO"
