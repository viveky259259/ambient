# Read aloud

Id prefix: `SPK-`

Reading a selection aloud: the shortcut (⌥⎋ by default), *Read Selection Aloud* in the menu bar and *Services › Speak
with Ambient*; the text it makes of markdown; the Mac voice, the offline Kokoro model and the online voices; the island's
speaking row; ⏯ and headphone controls; and where an online voice's key is kept. Settings live under
*Settings › Voice & Sound › Read Aloud*.

Shared setup for most cases: an agent reply in Claude's desktop app with a heading, a bulleted list, a link, a fenced code
block and a long file path in it, for example a reply to "Summarise what `Sources/AmbientApp/Speech/SpeechPlayer.swift`
does, with one code example and a link to the AVFoundation docs".

### SPK-001 · ⌥⎋ reads the selection in Claude's desktop app

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/ShortcutCenter.swift`, `Sources/AmbientApp/Speech/HotKey.swift`, `Sources/AmbientApp/Speech/SelectionReader.swift`, `Sources/AmbientApp/Speech/SpeechController.swift`, `Sources/AmbientApp/AppDelegate.swift`
- **Automated by:** `SpeechToggleTests`
- **Needs:** Accessibility allowed for Ambient; a voice already chosen (Mac voice is enough); Claude desktop app

**Steps**

1. In Claude's desktop app, select two sentences of an agent's reply with the mouse.
2. Press ⌥⎋.

**Expected**

- Within about a second the island shows a speaker icon and *Getting ready…*, then *Speaking* with a five-bar level meter.
- The two selected sentences are read, and nothing before or after them.
- When it finishes, the speaking row goes away and the island returns to what it showed before.
- Console (`log stream --predicate 'subsystem == "com.viveky259259.Ambient" AND category == "speech"'`) shows
  `selection: N characters from com.anthropic.claudefordesktop via Accessibility`.

### SPK-002 · ⌥⎋ reads the selection in Codex's desktop app

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/SelectionReader.swift`
- **Automated by:** none
- **Needs:** Accessibility allowed; Codex desktop app

**Steps**

1. In a Codex thread, select one paragraph of the agent's reply.
2. Press ⌥⎋.

**Expected**

- The paragraph is read aloud. Ambient turns on `AXManualAccessibility` for the Electron app, so the selection is read
  through Accessibility: the log line says `via Accessibility`, not `via copy`.

### SPK-003 · ⌥⎋ reads a selection in Terminal and iTerm2

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/SelectionReader.swift`
- **Automated by:** none
- **Needs:** Accessibility allowed; a Claude Code or Codex session in Terminal, and one in iTerm2

**Steps**

1. In Terminal, select a few lines of the agent's output.
2. Press ⌥⎋.
3. Repeat in iTerm2.

**Expected**

- In both apps the selected lines are read aloud, starting within about a second.
- The terminal's own scrollback and clipboard are unchanged.

### SPK-004 · Without an Accessibility selection, the copy fallback reads it and puts the clipboard back

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/SelectionReader.swift`
- **Automated by:** none
- **Needs:** Accessibility allowed; an app whose text view doesn't expose `AXSelectedText` (a web page in a browser
  usually works; check the log line)
- **Known gap:** The README says the shortcut reads the selection through Accessibility. When that gives nothing, the
  code presses ⌘C in the frontmost app, reads the clipboard, and writes the old contents back. For about half a second
  the selection is on the general pasteboard, so a clipboard history app can record it.

**Steps**

1. Copy the word `marker` to the clipboard.
2. In the browser, select a sentence and press ⌥⎋.
3. After it starts speaking, paste into TextEdit.

**Expected**

- The sentence is read aloud, and the log says `via copy`.
- Pasting gives `marker`, not the sentence: the clipboard was put back.
- If the browser copies nothing within about 0.5 s (20 × 25 ms), the island shows *Select some text first*.

### SPK-005 · Without Accessibility, the shortcut explains once, then points to Settings

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/AppDelegate.swift`, `Sources/AmbientApp/Speech/SelectionReader.swift`
- **Automated by:** none
- **Needs:** Ambient removed from System Settings › Privacy & Security › Accessibility; `defaults delete com.viveky259259.Ambient speechAccessExplained`

**Steps**

1. Select text in Claude and press ⌥⎋.
2. Click *Not Now*.
3. Press ⌥⎋ again.

**Expected**

- Step 1 shows an alert titled *Let Ambient read your selection*, saying it needs Accessibility, reads only the
  selection and only when you press the shortcut, with *Open Accessibility Settings* and *Not Now*.
- Nothing is read and no text is copied.
- Step 3 shows no alert. The island shows an orange warning icon and *This app needs Accessibility to read selections —
  Settings › Voice & Sound* for 5 seconds.

### SPK-006 · The Accessibility row in Settings follows the permission

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/VoicePane.swift`, `Sources/AmbientApp/Speech/SelectionReader.swift`
- **Automated by:** none
- **Needs:** Accessibility not yet allowed for Ambient

**Steps**

1. Open Settings › Voice & Sound › Read Aloud.
2. Click *Allow…* on the *Accessibility* row, allow Ambient in System Settings, and switch back to Ambient.

**Expected**

- The row reads *Lets Ambient read the selected text when you press the shortcut.* and shows *Allow…* before.
- Clicking it opens macOS's Accessibility prompt.
- On returning to Ambient the row shows a green *Allowed* badge without reopening Settings.

### SPK-007 · Read Selection Aloud in the menu bar reads the app you were in

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/MenuBarController.swift`, `Sources/AmbientApp/Speech/SelectionReader.swift`
- **Automated by:** none
- **Needs:** Accessibility allowed; a voice chosen

**Steps**

1. Select a sentence in Claude.
2. Open Ambient's menu bar menu.
3. Choose *Read Selection Aloud*.

**Expected**

- The menu item shows the current read-aloud shortcut beside it (⌥⎋, or the one you set).
- The sentence selected in Claude is read: opening the menu didn't take focus from Claude.

### SPK-008 · Services › Speak with Ambient reads without Accessibility

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/SelectionService.swift`, `Resources/Info.plist`
- **Automated by:** none
- **Needs:** Accessibility *not* allowed for Ambient; TextEdit

**Steps**

1. In TextEdit, type and select `Hello from the Services menu.`
2. Choose TextEdit › Services › Speak with Ambient.

**Expected**

- The text is read aloud, with no Accessibility alert and no *This app needs Accessibility* message.
- Choosing it again while it's still speaking the same text stops it.

### SPK-009 · Pressing the shortcut again on the same text stops it

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Speech/SpeechToggle.swift`, `Sources/AmbientApp/Speech/SpeechController.swift`
- **Automated by:** `SpeechToggleTests.pressingAgainOnTheSameTextStops`, `SpeechToggleTests.pressingWithNothingSelectedWhileSpeakingStops`
- **Needs:** Accessibility allowed; a voice chosen

**Steps**

1. Select a long paragraph and press ⌥⎋.
2. While it's speaking, press ⌥⎋ again without changing the selection.
3. Start it again, click elsewhere so nothing is selected, and press ⌥⎋.

**Expected**

- Steps 2 and 3 each stop the voice at once and the speaking row leaves the island. No *Select some text first*
  message appears.

### SPK-010 · New text replaces what's being read

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Speech/SpeechToggle.swift`, `Sources/AmbientApp/Speech/SpeechController.swift`, `Sources/AmbientApp/Speech/SpeechPlayer.swift`
- **Automated by:** `SpeechToggleTests.newTextWhileSpeakingRestarts`
- **Needs:** Accessibility allowed; a voice chosen

**Steps**

1. Select paragraph A and press ⌥⎋.
2. While A is speaking, select paragraph B and press ⌥⎋.

**Expected**

- A stops mid-word and B starts from its beginning. No audio from A plays after B starts, and the two never overlap.

### SPK-011 · Nothing selected says so

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Speech/SpeechController.swift`, `Sources/AmbientApp/Speech/SpeechRow.swift`
- **Automated by:** `SpeechToggleTests.nothingSelectedWhileIdle`
- **Needs:** Accessibility allowed

**Steps**

1. With nothing selected and nothing being read, press ⌥⎋.

**Expected**

- macOS's *Tink* sound plays.
- The island shows an orange warning icon and *Select some text first* for 5 seconds, then clears.

### SPK-012 · The first press asks which voice to use

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Speech/VoiceChooser.swift`, `Sources/AmbientApp/Speech/VoiceSections.swift`, `Sources/AmbientCore/Speech/SpeechToggle.swift`
- **Automated by:** `SpeechToggleTests.firstUseAsksForAVoice`
- **Needs:** `defaults delete com.viveky259259.Ambient speechEngine`; Accessibility allowed

**Steps**

1. Select a sentence and press ⌥⎋.
2. Leave *Mac voice* chosen and click *Play*.

**Expected**

- A window titled *Choose a Voice* opens, asking *How should Ambient read aloud?*, with *Mac voice*, *Offline model* and
  *Online model* as radio buttons, and *Preview*, *Cancel* and *Play*.
- Under *Mac voice* it reads *Free and offline. Nothing leaves your Mac.* and a voice picker.
- The caption reads *You can change this in Settings › Voice & Sound.*
- After *Play* the window closes and the selected sentence is read with the Mac voice.
- The next ⌥⎋ reads straight away, without the window.

### SPK-013 · Closing the voice chooser reads nothing and asks again next time

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/VoiceChooser.swift`
- **Automated by:** none
- **Needs:** no voice chosen yet

**Steps**

1. Press ⌥⎋ on a selection. In *Choose a Voice*, click *Preview*, then *Cancel* while the preview plays.
2. Press ⌥⎋ again.

**Expected**

- *Preview* reads *Hi. This is the voice Ambient will use to read your agents' replies.*
- *Cancel* (or the close button, or Esc) stops the preview, closes the window and reads nothing.
- Step 2 opens *Choose a Voice* again: nothing was saved.

### SPK-014 · Markdown is read as sentences, without symbols

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Speech/SpeechText.swift`
- **Automated by:** `SpeechTextTests`
- **Needs:** a voice chosen; a reply containing `## Next steps`, a `- [ ] item` list, `**bold**`, a `[docs](https://developer.apple.com/documentation/avfoundation)` link, a bare `https://github.com/x/y` URL, `__init__.py` in backticks and an emoji

**Steps**

1. Select the whole reply and press ⌥⎋.

**Expected**

- No `#`, `*`, `-`, `[ ]`, backtick or emoji is pronounced.
- The heading and each list item end with a pause, as if each ended with a full stop.
- The link is read by its label (*docs*); the bare URL by its host (*github.com*).
- `__init__.py` keeps its underscores ("underscore underscore init…", depending on the voice).

### SPK-015 · Code blocks are summarised, or read out when Read code blocks is on

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Speech/SpeechText.swift`, `Sources/AmbientApp/Settings/Panes/VoicePane.swift`
- **Automated by:** `SpeechTextTests.codeBlocksAreSummarized`, `SpeechTextTests.codeBlocksCanBeReadOut`, `SpeechTextTests.unclosedFenceStillCounts`
- **Needs:** a reply with a 12-line fenced code block

**Steps**

1. With Settings › Voice & Sound › Read Aloud › *Read code blocks* off, select the reply including the code and press ⌥⎋.
2. Turn *Read code blocks* on and repeat.
3. Select from the middle of the code block to its end, with the opening fence left out, and press ⌥⎋.

**Expected**

- The toggle's subtitle reads *Off: a code block is read as "code block, 12 lines".*
- Step 1 says *Code block, 12 lines.* in place of the code.
- Step 2 reads each non-blank code line.
- Step 3 still reads sensibly: a selection that ends inside a block is handled like a closed block.

### SPK-016 · Long paths and tables read well

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Speech/SpeechText.swift`
- **Automated by:** `SpeechTextTests.longPathsKeepTheirLastTwoParts`, `SpeechTextTests.tablesReadRowByRow`
- **Needs:** a reply mentioning `Sources/AmbientApp/Speech/SpeechPlayer.swift` and `and/or`, and a two-column markdown table

**Steps**

1. Select the reply and press ⌥⎋.

**Expected**

- The path is read as *Speech/SpeechPlayer.swift*, its last two parts only.
- *and/or* is read as written.
- The table's separator row isn't read; each row is read as its cells separated by commas, ending with a pause.

### SPK-017 · A long selection starts quickly and plays without gaps

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Speech/SpeechText.swift`, `Sources/AmbientCore/Speech/SpeechPipeline.swift`, `Sources/AmbientApp/Speech/SpeechPlayer.swift`
- **Automated by:** `SpeechChunkTests`, `SpeechPipelineTests.preparesTheNextChunkWhileOnePlays`, `SpeechPipelineTests.playsInOrder`
- **Needs:** a selection of about 5,000 characters; try once with the Mac voice and once with an online voice

**Steps**

1. Select the long text and press ⌥⎋. Time from the key press to the first word.
2. Listen through at least five sentences.

**Expected**

- The first words play about as soon as a short sentence would: the text goes to the voice in chunks of at most 300
  characters, split at sentence ends, then clauses, then words.
- Chunks play in order with no audible gap and no repeated or skipped sentence: chunk n+1 is prepared while chunk n plays.
- Decimals such as *3.5* don't cause a pause in the middle.

### SPK-018 · The Mac voice reads offline

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/MacVoice.swift`, `Sources/AmbientApp/Speech/SpeechEngine.swift`
- **Automated by:** none
- **Needs:** Read with *Mac voice*; Wi-Fi off, or a network monitor such as Little Snitch or `nettop -p Ambient`

**Steps**

1. Turn Wi-Fi off.
2. Select a paragraph and press ⌥⎋.

**Expected**

- The paragraph is read with no error.
- Ambient makes no network connection while reading.

### SPK-019 · Choosing a Mac voice and the speed

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/VoiceSections.swift`, `Sources/AmbientApp/Speech/MacVoice.swift`, `Sources/AmbientApp/Settings/Panes/VoicePane.swift`
- **Automated by:** none
- **Needs:** at least one Premium or Enhanced voice downloaded in System Settings › Accessibility › Spoken Content

**Steps**

1. In Settings › Voice & Sound › Read Aloud, choose *Mac voice* under *Read with*.
2. Open the *Voice* picker.
3. Pick a Premium voice, move *Speed* to the hare end (2×), and click *Preview* under *Try it*.

**Expected**

- *Read with*'s subtitle reads *Free and offline. Nothing leaves your Mac.*
- The *Voice* row's subtitle points to *System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.*
- The picker starts with *System voice*, then voices in your language, best first, labelled *(Premium)* or *(Enhanced)*.
- The preview reads *Hi. This is the voice Ambient will use to read your agents' replies.* in the chosen voice, clearly
  faster than at 1×. The slider runs from 0.5× to 2× in steps of 0.1.
- While it plays, the button reads *Stop*, and clicking it stops the preview.

### SPK-020 · Downloading the offline model

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/VoicePackInstaller.swift`, `Sources/AmbientApp/Speech/FileDownload.swift`, `Sources/AmbientApp/Speech/VoiceSections.swift`, `Sources/AmbientCore/Speech/VoicePack.swift`, `Sources/AmbientCore/Speech/VoicePackPin.swift`
- **Automated by:** `VoicePackTests`
- **Needs:** Apple silicon Mac on macOS 15 or later; network; `~/.ambient/voice/kokoro-1` absent

**Steps**

1. In Settings › Voice & Sound › Read Aloud, choose *Offline model*.
2. Click *Download* and watch until it finishes.
3. Open the *Voice* picker.

**Expected**

- Before: *Read with*'s subtitle reads *Kokoro runs on your Mac. Natural, offline, and free after a one-time download.*
  The *Offline model* row reads *One download of ≈344 MB, then it runs on this Mac.*
- During: *Downloading… N%* with a progress bar and *Cancel*, the percentage rising about ten times a second.
- After: the row becomes *Voice* with six voices: Heart, Bella, Nicole, Michael (American) and Emma, George (British).
  A row *Offline model* reads *≈344 MB on this Mac.* with *Remove*.
- `~/.ambient/voice/kokoro-1/` holds `ambient-voice/ambient-voice`, `kokoro-v1_0.safetensors` and six files in
  `voices/`; no `.staging-*` folder is left in `~/.ambient/voice/`.

### SPK-021 · The offline model downloads only on Download, from pinned sources, checked by hash and signature

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/Speech/VoicePackInstaller.swift`, `Sources/AmbientApp/Speech/FileDownload.swift`, `Sources/AmbientCore/Speech/VoicePack.swift`, `Sources/AmbientCore/Speech/VoicePackPin.swift`
- **Automated by:** `VoicePackTests.everyDownloadIsHTTPSAndPinned`, `VoicePackTests.pathsStayInsideThePack`, `VoicePackTests.hashesAFile`
- **Needs:** a network monitor (Little Snitch or a proxy such as mitmproxy with its certificate trusted); the offline model not installed

**Steps**

1. Open Settings › Voice & Sound › Read Aloud and choose *Offline model*, without clicking *Download*. Wait a minute.
2. Click *Download*.
3. Repeat with the proxy rewriting one byte of `voices/af_heart.safetensors`.

**Expected**

- Step 1 makes no request to huggingface.co or github.com.
- Step 2 requests only `https://github.com/viveky259259/ambient/releases/download/voice-1/ambient-voice-1.zip` and
  `https://huggingface.co/prince-canuma/Kokoro-82M/resolve/e02c9ea…/…` files, all HTTPS.
- Step 3 ends with the orange/red message *A downloaded file didn't match, so nothing was installed. Try again.* and
  *Download* again; `~/.ambient/voice/kokoro-1` does not exist.
- In a dev build whose `VoicePackPin` is pinned to an ad-hoc signed helper zip (`scripts/build-voice.sh` without
  `--sign`), the download ends with *The offline voice's signature didn't check out, so nothing was installed.*: the
  helper must be signed by team `CU3457GT8T`.

### SPK-022 · Cancelling the offline download leaves nothing behind

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/VoicePackInstaller.swift`, `Sources/AmbientApp/Speech/FileDownload.swift`
- **Automated by:** none
- **Needs:** network; offline model not installed
- **Known gap:** There's no resume. A cancelled or failed download starts again at 0% and fetches every file again
  (≈344 MB), since each attempt uses a new `.staging-<UUID>` folder that's deleted when it ends.

**Steps**

1. Click *Download* and, at about 30%, click *Cancel*.
2. Click *Download* again.

**Expected**

- After *Cancel* the row goes back to *One download of ≈344 MB, then it runs on this Mac.* with *Download*, and no error.
- No `.staging-*` folder remains in `~/.ambient/voice/`.
- The second download starts at 0%.

### SPK-023 · A failed offline download says why and can be tried again

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/VoicePackInstaller.swift`, `Sources/AmbientApp/Speech/FileDownload.swift`, `Sources/AmbientApp/Speech/VoiceSections.swift`
- **Automated by:** none
- **Needs:** network you can turn off mid-download

**Steps**

1. Click *Download*. At about 20%, turn Wi-Fi off.
2. Turn Wi-Fi back on and click *Download*.

**Expected**

- Step 1 ends with the row's subtitle in the error colour: *The download failed:* followed by macOS's description
  (for example *The Internet connection appears to be offline.*), and *Download* is shown again.
- A server answer other than 200 reads *The download failed: The server answered 404.* (or the code given).
- Step 2 downloads from 0% and installs.

### SPK-024 · The offline model isn't offered where it can't run

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/VoicePackInstaller.swift`, `Sources/AmbientCore/Speech/VoicePack.swift`
- **Automated by:** `VoicePackTests.support`, `VoicePackTests.publishedOnlyWithAPinnedHelper`
- **Needs:** an Intel Mac, or a Mac on macOS 14

**Steps**

1. Open Settings › Voice & Sound › Read Aloud and choose *Offline model*.

**Expected**

- On Intel the *Offline model* row reads *The offline model needs a Mac with Apple silicon.* with no Download button.
- On macOS 14 it reads *The offline model needs macOS 15 or later.*
- *Try it* › *Preview* is disabled.
- A build whose `VoicePackPin.helperSHA256` isn't 64 hex characters reads *This copy of Ambient doesn't come with it.*

### SPK-025 · Reading with the offline model never goes online

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/KokoroVoice.swift`, `Voice/**`
- **Automated by:** none
- **Needs:** offline model installed; Wi-Fi off, or a network monitor watching Ambient and `ambient-voice`

**Steps**

1. Turn Wi-Fi off.
2. Select a paragraph and press ⌥⎋ with *Offline model* chosen.

**Expected**

- The paragraph is read in the chosen Kokoro voice. The first selection after launch may take a few seconds while the
  model loads; later ones start within about a second.
- Neither Ambient nor `ambient-voice` opens any network connection.

### SPK-026 · The offline helper stays loaded for five idle minutes, then exits

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/KokoroVoice.swift`
- **Automated by:** none
- **Needs:** offline model installed

**Steps**

1. Read a selection with the offline model. Run `pgrep -fl ambient-voice`.
2. Read another selection within a minute.
3. Wait six minutes and run `pgrep -fl ambient-voice` again.

**Expected**

- After step 1 one `ambient-voice` process runs, with the pack folder as its argument.
- Step 2 starts faster than step 1 and the process id is the same.
- After step 3 no `ambient-voice` process runs (it ends 300 seconds after its last chunk).
- The helper's stderr goes to `~/.ambient/logs/voice.log`.

### SPK-027 · A stuck or crashed offline helper is reported, with a way out

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/KokoroVoice.swift`, `Sources/AmbientCore/Speech/VoiceWire.swift`, `Sources/AmbientApp/Speech/SpeechRow.swift`
- **Automated by:** `VoiceWireTests`
- **Needs:** offline model installed

**Steps**

1. Start reading a long selection with the offline model.
2. While it reads, run `pkill -STOP ambient-voice` (it stops answering) and wait 30 seconds.
3. Click *Use Mac voice*.

**Expected**

- Within about 30 seconds of the stall, the helper is killed and the island shows *Offline voice stopped* in orange
  with a *Use Mac voice* button, for 10 seconds.
- *Use Mac voice* sets *Read with* to *Mac voice*; the next ⌥⎋ reads with it.
- `pkill -KILL ambient-voice` during a read gives the same message at once.

### SPK-028 · Removing the offline model

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/VoicePackInstaller.swift`, `Sources/AmbientApp/Settings/Panes/VoicePane.swift`, `Sources/AmbientApp/AppDelegate.swift`
- **Automated by:** none
- **Needs:** offline model installed

**Steps**

1. Start reading a long selection with the offline model.
2. In Settings › Voice & Sound › Read Aloud, click *Remove* on the *Offline model* row.
3. Press ⌥⎋ on a selection.

**Expected**

- Reading stops at once and `ambient-voice` exits.
- `~/.ambient/voice/kokoro-1` is gone and the row reads *One download of ≈344 MB, then it runs on this Mac.* with *Download*.
- Step 3 shows *The offline voice isn't installed. Download it in Settings › Voice & Sound.* with *Use Mac voice*.

### SPK-029 · Reading with OpenAI

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/OnlineVoice.swift`, `Sources/AmbientCore/Speech/OnlineSpeech.swift`, `Sources/AmbientApp/Speech/VoiceSections.swift`
- **Automated by:** `OnlineSpeechTests.openAIRequest`, `OnlineSpeechTests.providerDefaults`, `OnlineSpeechTests.pcm16ToFloat`
- **Needs:** an OpenAI API key

**Steps**

1. Choose *Online model*, then *OpenAI* in the *Service* control.
2. Paste the key into *API key* and click *Preview*.
3. Select a paragraph and press ⌥⎋.

**Expected**

- The *Service* row reads *The text you select is sent to OpenAI.*
- *Voice* is `alloy` and *Model* `gpt-4o-mini-tts` by default.
- *Try it* › *Preview* stays disabled while *API key* is empty.
- The preview and the paragraph are read in the OpenAI voice, the paragraph starting within a couple of seconds.

### SPK-030 · Reading with ElevenLabs

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/OnlineVoice.swift`, `Sources/AmbientCore/Speech/OnlineSpeech.swift`
- **Automated by:** `OnlineSpeechTests.elevenLabsRequest`
- **Needs:** an ElevenLabs API key

**Steps**

1. Choose *Online model* › *ElevenLabs*, paste the key, and press ⌥⎋ on a selection.
2. Change *Voice* to `bad voice!` and press ⌥⎋ again.

**Expected**

- Switching to ElevenLabs sets *Voice* to `21m00Tcm4TlvDq8ikWAM` and *Model* to `eleven_flash_v2_5`, and the key field
  shows the ElevenLabs key (or nothing), not the OpenAI one.
- Step 1 reads the selection in the ElevenLabs voice.
- Step 2 sends nothing and shows *Check the online voice's settings in Settings › Voice & Sound.* with *Use Mac voice*.

### SPK-031 · Reading with your own server

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/OnlineVoice.swift`, `Sources/AmbientCore/Speech/OnlineSpeech.swift`, `Sources/AmbientApp/Speech/VoiceSections.swift`
- **Automated by:** `OnlineSpeechTests.customServerWithoutKey`
- **Needs:** an OpenAI-compatible speech server on this Mac, such as Kokoro-FastAPI on port 8880

**Steps**

1. Choose *Online model* › *Your server*. Leave *API key* empty.
2. Press ⌥⎋ on a selection.
3. Set *Server* to `ftp://localhost` and press ⌥⎋ again.
4. Stop the server and press ⌥⎋ again.

**Expected**

- *Server* shows `http://localhost:8880/v1` by default; *Voice* is `af_heart` and *Model* `kokoro`; the key row says *Optional.*
- The *Service* row reads *The text you select is sent to your server.*
- Step 2 reads the selection with no key (the request goes to `…/v1/audio/speech` without an `Authorization` header).
- Step 3 shows *Check the online voice's settings in Settings › Voice & Sound.*
- Step 4 shows *Couldn't reach your server:* and macOS's reason, with *Use Mac voice*.

### SPK-032 · An online voice's key is kept in the Keychain and nowhere else

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/KeychainStore.swift`, `Sources/AmbientApp/Speech/VoiceSections.swift`, `Sources/AmbientApp/Settings/Panes/VoicePane.swift`
- **Automated by:** none
- **Needs:** a test key such as `sk-qa-keychain-check-0001` (it needn't work)

**Steps**

1. In *Online model* › *OpenAI*, type the test key and close Settings.
2. Run `security find-generic-password -s com.viveky259259.Ambient.voice -a openAI -w`.
3. Run `defaults read com.viveky259259.Ambient | grep -c sk-qa-keychain` and
   `grep -rl sk-qa-keychain ~/.ambient ~/Library/Preferences ~/Library/Application\ Support 2>/dev/null`.
4. Reopen Settings › Voice & Sound › Read Aloud.

**Expected**

- Step 2 prints the test key: it was saved when the pane closed (it's also saved on *Preview*, not on every keystroke).
- Step 3 finds nothing: the key is in no preference or file.
- Step 4 fills the *API key* field (dots) from the Keychain.
- Each provider has its own item: accounts `openAI`, `elevenLabs` and `custom` under service `com.viveky259259.Ambient.voice`.

### SPK-033 · Emptying the key field forgets the key; a failed read never deletes it

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/KeychainStore.swift`, `Sources/AmbientApp/Speech/VoiceSections.swift`
- **Automated by:** none
- **Needs:** an OpenAI key saved as in SPK-032

**Steps**

1. Run `security lock-keychain ~/Library/Keychains/login.keychain-db`. Open Read Aloud settings, cancel the unlock
   prompt, and close Settings.
2. Run `security find-generic-password -s com.viveky259259.Ambient.voice -a openAI`.
3. Reopen Settings (unlock the Keychain this time), clear the *API key* field and close Settings.
4. Run the command in step 2 again.

**Expected**

- After step 1 the field was empty, but step 2 still finds the item: a field still holding what was read is never saved back.
- Step 4 finds no item: an emptied field forgets the key.

### SPK-034 · No key or a refused key offers the Mac voice

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Speech/OnlineVoice.swift`, `Sources/AmbientCore/Speech/OnlineSpeech.swift`, `Sources/AmbientApp/Speech/SpeechRow.swift`, `Sources/AmbientApp/Speech/SpeechController.swift`
- **Automated by:** `OnlineSpeechTests.failureMessages`
- **Needs:** *Online model* › *OpenAI* chosen

**Steps**

1. Delete the key (`security delete-generic-password -s com.viveky259259.Ambient.voice -a openAI`) and press ⌥⎋ on a selection.
2. Save a wrong key and press ⌥⎋.
3. Click *Use Mac voice*.

**Expected**

- Step 1 sends no request and shows *Add your OpenAI API key in Settings › Voice & Sound.*
- Step 2 shows *OpenAI didn't accept the API key.* (HTTP 401 or 403).
- Both are orange, with *Use Mac voice*, for 10 seconds.
- Step 3 switches *Read with* to *Mac voice* and clears the message.

### SPK-035 · Online failures are said plainly

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientApp/Speech/OnlineVoice.swift`, `Sources/AmbientCore/Speech/OnlineSpeech.swift`
- **Automated by:** `OnlineSpeechTests.failureMessages`
- **Needs:** *Online model* with a working key; a way to go offline; a local server or proxy that can answer 429, 500 or hang

**Steps**

1. Turn Wi-Fi off and press ⌥⎋.
2. Make the service answer 429, then 500 with `{"error":{"message":"Model overloaded"}}`, then not answer for 20 s.

**Expected**

- Offline: *You're offline, so OpenAI can't be reached.*
- 429: *OpenAI is limiting requests. Try again in a minute.*
- 500: *OpenAI couldn't read it aloud (error 500). Model overloaded* (the detail cut to 120 characters).
- No answer: after 15 seconds, *OpenAI took too long to answer.*
- Every one offers *Use Mac voice*. For *Your server* the messages say *your server* mid-sentence.

### SPK-036 · Read aloud goes online only with an online voice, and only with the selection

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/OnlineVoice.swift`, `Sources/AmbientCore/Speech/OnlineSpeech.swift`, `Sources/AmbientApp/AppDelegate.swift`, `Sources/AmbientApp/Speech/SpeechController.swift`
- **Automated by:** `OnlineSpeechTests.openAIRequest`
- **Needs:** an OpenAI key saved; mitmproxy (certificate trusted) or Little Snitch showing Ambient's connections

**Steps**

1. With *Mac voice* chosen and a key still saved, read a selection. Repeat with *Offline model*.
2. Choose *Online model* › *OpenAI* and read a two-sentence selection from a reply that also contains other text.
3. Open Settings › Voice & Sound › Read Aloud and leave it open for a minute without clicking *Preview*.

**Expected**

- Step 1 makes no request to api.openai.com, api.elevenlabs.io or any server.
- Step 2 sends only `POST https://api.openai.com/v1/audio/speech`. Each request's `input` is a chunk of the selection's
  spoken text; together they hold the two sentences and nothing else from the reply, the app or the session.
- Step 3 makes no request.

### SPK-037 · The island shows speaking, with pause, continue and stop

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/SpeechRow.swift`, `Sources/AmbientApp/Speech/SpeechController.swift`, `Sources/AmbientApp/Speech/SpeechPlayer.swift`
- **Automated by:** `SpeechPipelineTests.cancelDuringPlayStopsEverything`
- **Needs:** Mac with a notch, or the desktop pet turned on

**Steps**

1. Read a long selection.
2. Click the pause button, wait five seconds, then click the play button.
3. Click the stop button.

**Expected**

- While reading: speaker icon, *Speaking*, five white bars that follow the voice, a pause button (*Pause speaking* to
  VoiceOver) and a stop button (*Stop speaking*).
- Paused: icon without waves, *Paused*, bars flat, a play button (*Continue speaking*). Sound stops at once.
- Continue picks up mid-sentence where it paused, not from the start of the chunk.
- Stop silences it at once and the row disappears. The pet shows the same controls when it's on.

### SPK-038 · ⏯ and headphones pause and continue, then go back to the music app

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Speech/NowPlaying.swift`
- **Automated by:** none
- **Needs:** a keyboard with ⏯; AirPods or other Bluetooth headphones; Music with a song paused

**Steps**

1. Read a long selection. Press ⏯ on the keyboard, then again.
2. Tap or squeeze an AirPod stem, then again. Take one AirPod out.
3. Open Control Center's Now Playing while reading.
4. Let it finish (or stop it), then press ⏯.

**Expected**

- Each ⏯ press or stem tap toggles between *Paused* and *Speaking* in the island; taking an AirPod out pauses it.
- Control Center shows *Reading your selection* by *Ambient*, paused or playing as the island is.
- After reading ends, ⏯ starts Music again: Ambient gave Now Playing back.

### SPK-039 · Changing the read-aloud shortcut

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/Speech/ShortcutRecorder.swift`, `Sources/AmbientApp/Speech/ShortcutCenter.swift`, `Sources/AmbientApp/Speech/HotKey.swift`, `Sources/AmbientCore/Speech/Shortcut.swift`
- **Automated by:** `ShortcutTests`
- **Needs:** nothing special

**Steps**

1. In Read Aloud settings, click the shortcut button and press ⌘S.
2. Press ⌥S.
3. Press ⌃⌥R.
4. Click *Reset*.
5. Click the shortcut button, press Esc; click it again, press Delete.

**Expected**

- While recording, the button reads *Type a shortcut…* and the caption *Esc cancels · Delete restores ⌥⎋*.
- ⌘S: *Use ⌃ or ⌥ in the shortcut, so it doesn't take a key from your apps.* and it keeps recording.
- ⌥S: *⌥ with that key types a character. Add ⌃ or ⌘, or pick another key.*
- ⌃⌥R is saved: the button shows ⌃⌥R, a *Reset* button appears, ⌃⌥R reads a selection, and the menu bar item shows ⌃⌥R.
  ⌥⎋ no longer reads.
- *Reset* and Delete both bring back ⌥⎋; Esc cancels without changing it.
- F-keys (for example F5) are accepted without modifiers.

### SPK-040 · The default shortcut gives way when it's taken

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientApp/Speech/ShortcutCenter.swift`, `Sources/AmbientApp/Speech/HotKey.swift`, `Sources/AmbientCore/Speech/Shortcut.swift`
- **Automated by:** `ShortcutTests.defaultAvoidsMacOSSpeakSelection`
- **Needs:** ability to turn on System Settings › Accessibility › Spoken Content › Speak selection; another app that registers a global hotkey

**Steps**

1. Turn on macOS's *Speak selection* (which uses ⌥⎋) and relaunch Ambient.
2. Turn it off, and in another app register ⌃⌥R as a global shortcut. Set Ambient's shortcut to ⌃⌥R.

**Expected**

- Step 1: the shortcut shows ⌃⌥S, with the orange note *macOS Speak Selection already uses ⌥⎋, so Ambient uses ⌃⌥S.*;
  ⌃⌥S reads a selection.
- Step 2: the note reads *⌃⌥R is used by another app. Pick another shortcut.*

### SPK-041 · A one-time tip says how to hear a reply

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientApp/AppDelegate.swift`, `Sources/AmbientApp/Speech/SpeechController.swift`, `Sources/AmbientApp/Speech/SpeechRow.swift`
- **Automated by:** none
- **Needs:** `defaults delete com.viveky259259.Ambient speechHintShown`; alerts not quieted; an agent session

**Steps**

1. Relaunch Ambient and let an agent finish a turn.
2. Let another agent finish later.

**Expected**

- About 8 seconds after the first finish, the island shows a keyboard icon and *Select part of the reply and press ⌥⎋ to
  hear it* for 7 seconds (with your shortcut if you changed it).
- It never appears again, including after a relaunch, and not at all if you'd already pressed the shortcut.
- With *Quiet alerts* on it isn't shown.

### SPK-042 · An Anthropic key for skill bootstrap is read from the Keychain or the environment only

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientBase/SecretStore.swift`
- **Automated by:** none
- **Needs:** the `ambient` CLI; no `ANTHROPIC_API_KEY` set; no Anthropic item in the Keychain

**Steps**

1. Run `ambient task skill-bootstrap`.
2. Run `security add-generic-password -s com.viveky259259.Ambient -a anthropic -w '   '` (spaces only), then step 1 again.
3. Store a real key, run step 1 again, then search for the key's first 16 characters with
   `grep -rlF "<first 16 characters>" ~/.ambient ~/Library/Preferences 2>/dev/null`.

**Expected**

- Step 1 fails with *No Anthropic key in Keychain or ANTHROPIC_API_KEY. Stash it first, then re-run.* and suggests
  `security add-generic-password -s com.viveky259259.Ambient -a anthropic -w`.
- Step 2 fails the same way: a blank key counts as none.
- Step 3 finds the key in no file: `~/.ambient/task-skill.json` holds examples, not the key.

### SPK-043 · The offline helper builds, signs and answers with audio

- **Priority:** P2
- **Type:** both
- **Covers:** `Voice/**`, `scripts/build-voice.sh`, `scripts/smoke-voice.sh`, `Sources/AmbientCore/Speech/VoiceWire.swift`
- **Automated by:** `VoiceWireTests`
- **Needs:** Xcode; an Apple silicon Mac; a pack folder holding the Kokoro model and voices (`build/voice-pack`)

**Steps**

1. Run `scripts/build-voice.sh`.
2. Run `scripts/smoke-voice.sh build/voice-pack`.
3. Send it a request for voice `xx`: `echo '{"id":"1","speed":1,"text":"hi","voice":"xx"}' | build/ambient-voice/ambient-voice build/voice-pack | head -1`.

**Expected**

- Step 1 ends with *Built dist/ambient-voice-1.zip (…, sha256 …, signed: -)*; `codesign --verify --strict
  build/ambient-voice/ambient-voice` passes, and `build/ambient-voice/licenses/` and `THIRD_PARTY_NOTICES.md` are in it.
- Step 2 prints *ok: N s of audio* with N at least 1.0, at 24 kHz.
- Step 3's header line has an `error` field (`unknown voice xx`) and no frames follow.
