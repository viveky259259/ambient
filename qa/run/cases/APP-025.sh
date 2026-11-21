#!/bin/zsh
# APP-025 · The app asks for only the entitlements and permissions it explains.
# Checked on build/Ambient.app, signed with the same Resources/Ambient.entitlements and Info.plist as the release.
source "$QA_REPO/qa/run/lib.sh"

app=$QA_REPO/build/Ambient.app
plist=$app/Contents/Info.plist
ents=$(codesign -d --entitlements :- "$app" 2>/dev/null | plutil -convert json -o - -) || fail "cannot read the entitlements"
assert_eq "$(jq -r 'keys | join(" ")' <<< $ents)" \
  "com.apple.security.automation.apple-events com.apple.security.device.audio-input com.apple.security.personal-information.calendars" \
  "entitlements"
assert_eq "$(jq -r '[.[]] | unique | join(" ")' <<< $ents)" "true" "entitlement values"

reason() { plutil -extract $1 raw "$plist" 2>/dev/null; }
r=$(reason NSAppleEventsUsageDescription)
[[ $r == "Ambient selects the terminal tab your agent is running in"* ]] || fail "Apple Events reason: [$r]"
assert_contains "$(reason NSMicrophoneUsageDescription)" "only while you press its voice shortcut" "microphone reason"
r=$(reason NSSpeechRecognitionUsageDescription)
[[ $r == *"on this Mac. Nothing is sent to Apple or anyone else." ]] || fail "speech recognition reason: [$r]"
for key in NSCalendarsUsageDescription NSCalendarsFullAccessUsageDescription; do
  r=$(reason $key)
  [[ $r == *"your next event today on its living wallpaper. Nothing leaves your Mac." ]] || fail "$key: [$r]"
done

services=$(plutil -extract NSServices json -o - "$plist") || fail "no NSServices"
assert_eq "$(jq -r '[.[].NSMenuItem.default] | join(",")' <<< $services)" "Speak with Ambient" "services offered"
assert_contains "$(jq -r '.[0].NSSendTypes | join(" ")' <<< $services)" "public.utf8-plain-text" "the service's input"
