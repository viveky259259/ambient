# Speak selection

Date: 2026-10-12
Status: decisions approved in chat; spec awaiting review on `feat/speak-selection`

## Problem

Agent replies are long, and reading them pins you to the screen. You already pick out the part that matters by
selecting it in the Claude app, the Codex app or a terminal. macOS can read a selection aloud (Accessibility ›
Spoken Content › Speak selection, ⌥⎋), but it reads markdown symbols, file paths and code character by
character, shows nothing while it speaks, and only offers system voices.

## Goal

Select text in the window the agent runs in, press one shortcut, and Ambient reads it aloud: cleaned up for
listening, in the voice you chose, with a visible way to stop it. You never select anything in Ambient.

Non-goals: picking a whole chat or session to read, reading replies automatically as they arrive, pause, skip
and scrubbing, a speaker button on the island or the pet, chats in Claude's or ChatGPT's regular Chat tab
(they live on those services' servers), and engines other than the three below.

## Decisions

| Topic | Decision |
| --- | --- |
| Where the selection is made | In the host app: Claude desktop, the Codex app, Terminal, iTerm2 (and any other app, best effort). Ambient reads only the selected text, not transcripts |
| Trigger | One global shortcut, changeable. Default ⌃⌥⌘S for Ambient's own hotkey; an app can only give a Services item ⌘ or ⌘⇧ plus a key, so on the Services route the default is ⌘⇧ plus a free key chosen in the probe, and the user can rebind it in System Settings › Keyboard › Keyboard Shortcuts › Services. Press it to read the selection; press it again while speaking to stop; press it with a new selection to stop and read the new one. The same action is also **Services › Speak with Ambient** in each app's menu, which needs no permission |
| How the shortcut gets the text | Decided by the probe below. If a Services shortcut delivers the selection in all four host apps, the shortcut is that Services shortcut and needs no permission. Otherwise Ambient registers its own hotkey and reads the selection through Accessibility (`AXSelectedText` of the focused element, then copy-and-restore the clipboard), which needs Accessibility; the Services entry stays as the no-permission route |
| Engines | **A. Mac voice**: `AVSpeechSynthesizer`, offline, free, includes Premium/Enhanced voices and Personal Voice. **B. Offline model**: Kokoro-82M in a downloadable helper. **C. Online model**: OpenAI, ElevenLabs, or any OpenAI-compatible `/v1/audio/speech` URL, with your key |
| First use | The first time the shortcut fires (and no engine is chosen), a chooser offers A, B and C, with Mac voice preselected, a voice picker per engine, **Preview** and **Play**. B shows **Download (≈350 MB)** with progress, and is disabled with the reason on macOS 14 or Intel. C asks for a key and says plainly that the selected text is sent to that service. Play saves the choice and reads the selection. The chooser never appears again; Settings › Voice changes it |
| What is read | Markdown is turned into speech: no symbols, links read by their label, headings and list items as sentences, tables row by row, long paths shortened to their last two parts, code blocks read as "code block, N lines" (or read out, by setting). Text is split into sentence chunks of at most 300 characters so audio starts within about a second |
| While speaking | The island shows a "Speaking" line with a level meter and a stop button; without the island, the menu bar icon does. The pet, if on, talks. Nothing else |
| Errors | Nothing selected: "Select some text first" and a soft chime. Accessibility needed and not granted: one explanation prompt, then "This app needs Accessibility to read selections — Settings › Voice". Online failure (offline, bad key, rate limit): the island says why. Offline helper missing or crashed: "Offline voice stopped — Retry / Use Mac voice". Ambient never quietly switches engines, so it never sends text somewhere you didn't choose |
| Settings › Voice | Engine and voice per engine, speed, read code blocks, the shortcut, the offline pack's size with **Remove**, and the online key's status with **Change key** and **Forget key** |
| Secrets | API keys live in the login Keychain (service `com.viveky259259.Ambient.voice`), never in files or preferences |
| Privacy promise | "Everything stays on your Mac" becomes: nothing leaves your Mac except the one-time offline pack download you start, and your selections when you choose an online voice. README and SECURITY.md say exactly this |

## Probe (first task)

Add a Services provider (`NSServices`, send type `NSStringPboardType`, a ⌘⇧ key equivalent that no host app already uses) and check, in
Claude desktop, the Codex app, Terminal and iTerm2: does the item appear in the app menu's Services, does the
shortcut deliver the selection, and does it work while a turn is streaming? The answer picks the trigger route
in the table above. The probe also checks that `AXSelectedText` returns the selection in the two Electron apps,
which the Accessibility route depends on.

## Architecture

```
selection ─▶ SelectionReader ─▶ SpeechText (clean, chunk) ─▶ SpeechEngine ─▶ SpeechPlayer ─▶ speakers
                                                              │                 │
                                    MacVoice / KokoroVoice / OnlineVoice        └─▶ AppModel.speech ─▶ island · menu bar · pet
```

### AmbientCore (pure, unit tested, no dependencies)

- **`SpeechText`**: `spoken(_ markdown: String, readCode: Bool) -> String` and
  `chunks(_ text: String, max: Int = 300) -> [String]`. Splits on sentence ends, then clauses, then words; never
  splits inside a word.
- **`VoiceSettings`**: engine (`mac`, `kokoro`, `online`), voice id per engine, online provider and base URL,
  speed, read code, and whether the chooser has run. Stored with the other preferences.
- **`VoiceWire`**: the helper protocol. Request: one JSON line `{"id","text","voice","speed"}`. Response: a JSON
  header line `{"id","sampleRate":24000,"channels":1}` then frames of `UInt32` little-endian byte count +
  float32 PCM, ending with a zero-length frame; or `{"id","error"}`. Encoder and decoder both live here so tests
  cover both sides.
- **`VoicePackManifest`**: helper version, helper zip URL and SHA-256, model file URLs (Hugging Face, pinned
  commit) and SHA-256s, required macOS version, required architecture, and the signing team (`CU3457GT8T`).
  Compiled into the app.

### AmbientApp

- **`Speech/SelectionReader`**: the Services provider (`speakWithAmbient(_:userData:error:)`), and if the probe
  requires it, the global hotkey (Carbon `RegisterEventHotKey`, which needs no permission) plus the Accessibility
  reader with clipboard fallback. It hands plain text to `SpeechController`.
- **`Speech/SpeechEngine`**: `protocol SpeechEngine { func audio(for chunk: String) async throws -> AVAudioPCMBuffer }`.
  - **`MacVoice`**: `AVSpeechSynthesizer.write(_:toBufferCallback:)`, collected into one buffer per chunk.
  - **`KokoroVoice`**: starts `~/.ambient/voice/kokoro-<version>/ambient-voice`, keeps it running across
    requests, and ends it after 5 idle minutes or when Ambient quits.
  - **`OnlineVoice`**: OpenAI (`response_format: "pcm"`, 24 kHz s16le), ElevenLabs (`output_format: pcm_24000`),
    or a custom OpenAI-compatible base URL. Timeouts of 15 s per chunk.
- **`Speech/SpeechPlayer`**: one `AVAudioEngine` with an `AVAudioPlayerNode`, converting every engine's output to
  its format. It keeps one chunk prepared ahead of the one playing, and publishes
  `SpeechState` (`idle`, `preparing`, `speaking(level:)`, `failed(reason:)`).
- **`Speech/SpeechController`**: owns the current job: the toggle logic, the first-run chooser, and error
  messages. `AppModel` exposes its state to the island, menu bar and pet.
- **`Speech/KeychainStore`**: get, set and delete a key per provider.
- **`Speech/VoicePackInstaller`**: downloads into a temporary folder with progress, checks every SHA-256 against
  the manifest and the helper's code signature against the team, then moves the folder into place with one
  rename. **Remove** deletes the folder. A partial download is never left in `~/.ambient/voice`.
- **UI**: `VoiceChooser` (first run), `Settings/Panes/VoicePane`, a "Speaking" row in the island and menu bar, and
  a talking pose for the pet.

### `ambient-voice` helper (`Voice/`)

A separate Swift package, so Ambient's own `Package.swift` keeps no dependencies. It depends on kokoro-ios (MLX
Swift, MIT) and MisakiSwift (grapheme-to-phoneme, no espeak), requires macOS 15 and Apple Silicon, loads the
model once, serves `VoiceWire` on stdin and stdout, and exits when stdin closes. FluidAudio's Kokoro path was
rejected because it links espeak-ng (GPL-3).

### Release

- `release.sh` builds, signs and notarizes the helper and attaches `ambient-voice-<version>-arm64.zip` (≈30 MB)
  to the GitHub release. The manifest in the app pins its hash.
- Kokoro weights and voices (≈330 MB, Apache-2.0) download from Hugging Face at a pinned commit; we don't re-host
  them.
- THIRD_PARTY_NOTICES gains kokoro-ios, MisakiSwift, MLX Swift and Kokoro-82M.

## Testing

- Unit tests (AmbientCore): the markdown cleaner (headings, lists, links, inline and fenced code, tables, paths,
  emoji), the chunker (limits, sentence and word boundaries, very long words), `VoiceWire` round trips and
  malformed input, and manifest checks (hash mismatch, wrong team, wrong architecture).
- Helper smoke test: run `ambient-voice`, send one request, expect a header and non-empty PCM.
- Manual: each engine in Claude desktop, the Codex app, Terminal and iTerm2; first-run chooser for each choice;
  stop and re-trigger mid-speech; pack download, cancel, remove; online with no network and with a bad key;
  Reduce Motion and VoiceOver on the chooser and the island row.

## Probe results (2026-10-14)

| App | "Speak with Ambient" in app menu › Services with text selected | Notes |
| --- | --- | --- |
| TextEdit | yes | Native text view; also lists Look Up, Search With Google |
| Claude desktop | no | No text services at all: the chat view doesn't offer its selection to Services |
| Codex app | not checked | Same Electron setup as Claude |
| Terminal, iTerm2 | not checked | |

Decision: **hotkey route**. The shortcut is ⌃⌥⌘S, registered by Ambient, reading the selection through Accessibility
(`AXSelectedText`, then copy-and-restore the clipboard). Services › Speak with Ambient stays, without a shortcut, for
apps that support it.
