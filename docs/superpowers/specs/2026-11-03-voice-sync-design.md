# Voice sync: talk on one Mac, paste on another

Date: 2026-11-03
Status: built on `feat/voice-sync`. Not released.

## Problem

People with two Macs, such as a laptop on the couch and a desktop running the agents, want to say something on one Mac
and use it on the other: a prompt for an agent, a note, a reply. Today they record it, AirDrop it, wait, and
transcribe it by hand. Voice sync sends a voice from one Mac to another as it's recorded. When the recording stops,
both the audio and the transcript are already on the other Mac, one click away. Both Macs keep every voice until the
user deletes it.

There's no account, relay or backend. Voices travel over the link remote agents already use: the user's own SSH, with
the receiving Mac dialing out.

## What the user sees

**On the sending Mac**

- The voice shortcut (⌃⌥V by default) starts recording for the chosen destination. Pressing it again sends the voice.
  The notch shows the destination, the elapsed time, a level meter, the live transcript, and Cancel and Send buttons.
- Destinations are the Macs that follow this one: each receiving Mac registers itself every time it connects. Settings
  › Voice Sync picks the default. With a single destination, that one is used.
- If no Mac follows this one, the shortcut explains how to pair: `ambient remote add` on the receiving Mac.
- A destination that's offline (asleep, or off the network) still gets the voice. It waits in the outbox and arrives
  when the link comes back, for up to 24 hours.
- A recording stops by itself at 10 minutes.

**On the receiving Mac**

- While the other Mac records, the notch's wings show a pulsing waveform and the elapsed time. There's nothing to
  accept or decline: it only says that a voice is being recorded for you.
- When the recording ends, a card drops from the notch with the transcript and three buttons: Copy Text, Copy Audio and
  Play. It stays for one minute by default (Settings › Voice Sync › Show Copy For: 30 s, 1, 2 or 5 minutes).
- Settings › Voice Sync lists every voice sent and received, with Copy Text, Copy Audio, Play and Delete.

## Key decisions

1. **The remote-agents link carries voices.** The receiving Mac already runs
   `ssh <sender> ambient-remote follow --since N`. `follow` gains three arguments, `--hub ID --hub-label NAME
   --voice-since N`, and streams the outbox lines addressed to that hub along with the events. This adds no listener,
   port, relay or credentials, and no new trust boundary. It also inherits ProxyJump, Tailscale SSH, certificates and
   the rest. Each direction is its own pairing: to send both ways, each Mac pairs the other.
2. **Real time, by streaming chunks.** The sender writes about 0.5 s of AAC at a time, and every 5 s the transcript so
   far, as JSON lines. Each `text` line carries the whole transcript, so sending it with every chunk would make a long
   voice's text outweigh its audio; the `end` carries the final words.
   `follow` normally polls once a second. While `outbox.live` exists, it checks the outbox every 0.2 s, so a line
   reaches the hub in roughly 0.2 s plus the SSH round trip. The receiver doesn't play the voice live. Streaming means
   the voice is complete the moment it ends, and the destination knows a voice is coming.
3. **Transcription is on the sending Mac, and on-device only.** `SFSpeechRecognizer` runs with
   `requiresOnDeviceRecognition`, so audio never reaches Apple's servers. Where on-device recognition isn't available
   for the language, the voice is sent as audio only. It never falls back to a server.
4. **AAC in ADTS frames.** ADTS frames can be cut at any boundary, so each chunk can be checked on its own and the
   chunks add up to a playable `.aac` file. Mono, 24 kHz, about 32 kbit/s, which is 4 KB/s, so a minute is about
   240 KB on the wire. Copy Audio converts the file to `.m4a`.
5. **Voice lines are quarantined like events.** They pass a strict decoder with their own allowlist and caps. The audio
   has to be well-formed ADTS (AAC-LC, mono, a fixed set of sample rates) before it's written to disk. The transcript is
   plain text and capped. Nothing from a voice is ever executed, opened or spoken. AVFoundation parses the audio only
   when the user presses Play or Copy Audio.
6. **The hub's label goes to the sender.** This is the one new thing the hub tells a machine. It's the Mac's computer
   name, cut to ASCII letters, digits, spaces, `.`, `_` and `-`, at most 40 characters, on the command line. The remote
   side checks the same pattern again.

## Protocol

### Hub identity

`~/.ambient/voice-sync/hub.id`: 32 random lowercase hex digits, created the first time they're needed. The label is the
computer name, sanitized as above.

### Sender files (in the user's home, `0700` and `0600`)

| Path | Written by | What |
|---|---|---|
| `~/.ambient/voice-sync/outbox.jsonl` | the app | Voice lines, oldest first. |
| `~/.ambient/voice-sync/outbox.seq` | the app | The newest `vseq`, replaced atomically after each append. |
| `~/.ambient/voice-sync/outbox.live` | the app | Present while recording; `follow` polls fast. |
| `~/.ambient/spool/hubs/<hub id>` | `follow` | The hub's label. The file's mtime is when the hub was last connected, refreshed with each heartbeat. |

The app is the outbox's only writer. It appends a line, then updates `outbox.seq`, so `follow`, which reads only up to
`outbox.seq`, never sees half a line. When the app starts, and every hour while it runs, it trims the outbox to voices
from the last 24 hours (40 MB at most), rewriting the file atomically without changing any `vseq`. The hourly trim
leaves a voice being recorded alone. At start, it also writes a `cancel` for any voice a crash left open, and removes a
stale `outbox.live`.

### Voice line

Every line starts with these fields in this order, which is what `follow`'s `awk` filter matches:
`{"v":1,"type":"voice","vseq":N,"to":"<hub id>",`

| Field | Type and cap | Required | Notes |
|---|---|---|---|
| `v` | integer | yes | Same protocol version as events. |
| `type` | `"voice"` | yes | |
| `vseq` | integer, 1…2^53 | yes | The outbox's own order. |
| `to` | 32 lowercase hex | yes | The destination hub. `follow` sends a hub only its own lines. |
| `voice` | 32 lowercase hex | yes | The voice's random id. |
| `part` | `start`, `audio`, `text`, `end`, `cancel` | yes | |
| `ts` | Unix seconds | `start` | When recording began, for display only. |
| `n` | integer, 0…100000 | `audio` | The chunk's index. Chunks must arrive in order. |
| `data` | base64, ≤ 48 KB | `audio` | Whole ADTS frames. |
| `text` | string ≤ 10,000 characters | `text`, optional on `end` | The whole transcript so far, which replaces the last one. |

Any other field, a wrong type or a bad value rejects the line. The line cap stays at 64 KB.

### The handshake

When `follow` is given a valid `--hub`, its hello adds `"voice":<newest vseq>`. A hub whose voice cursor is past that
number has seen a different outbox: it resets the cursor to 0 and reconnects. Saved voice ids keep the reset from
duplicating anything. Without `--hub`, the hello is exactly what it was, so hubs from before voice sync never see
anything new. A new hub running against an older shim gets no `voice` capability, and Settings asks the user to update
that machine.

### Delivery

- `VoiceInbox` runs on the link's thread and assembles voices. On each line it checks:
  - that `to` is this hub;
  - that `vseq` is above what it has seen;
  - that the voice has a `start`;
  - that chunk numbers are in order;
  - that the ADTS sample rate doesn't change;
  - the caps: 10 minutes, 4 MB of audio, and two voices in flight per machine.

  A voice that breaks any of these is dropped and recorded in the audit log, without content.
- **Cursor.** The voice cursor is saved in `library.json` after the voices it passes, never before, so a hub killed at
  any moment loses no voice, and one it gets again is already known, so none is kept twice. A voice the library can't
  store holds that machine's cursor where it was until the app starts again, and then it comes again. The cursor
  never passes the `start` of a voice still in flight. A link that drops mid-voice discards the partial voice, and the
  reconnect replays it from its `start`.
- **Library file.** A `library.json` this version can't read is moved aside to `library.unreadable-<time>.json` by
  the first save, not replaced.
- A voice with no line for 2 minutes on a live link is dropped. That's a sender that crashed; its next launch cancels
  the voice.

### Hub storage

`~/.ambient/voice-sync/library.json` (`0600`) lists each voice: its id, sent or received, the peer's id and label, when
it was recorded, its length and its transcript. It also holds the per-machine voice cursors. The audio is in
`~/.ambient/voice-sync/audio/<id>.aac`. Both Macs keep voices until the user deletes them. Remove (unpairing) drops the
machine's cursor. Purge also deletes every voice received from that machine (ER-14).

## Requirements this changes

- **ER-6 / one way.** The hub still sends nothing but the command line. The command line now carries the hub's random
  id and its sanitized label.
- **ER-11 data inventory.** A voice's audio and transcript leave the sending Mac, but only for a destination the user
  picked and only when the user presses the shortcut. Voices don't depend on the redaction level: the user sends them
  on purpose.
- **ER-13 egress.** A received transcript goes to the clipboard only when the user clicks Copy. It's never spoken, sent
  online or summarized.
- **ER-14 retention.** On the sender, the outbox keeps voices for 24 hours (40 MB at most), and the library keeps them
  until the user deletes them. On the hub, voices stay until deleted or purged.

## Threat model additions

| Threat | Mitigation | Residual risk |
|---|---|---|
| A paired machine sends crafted audio to exploit a codec. | The ADTS framing is checked on arrival: sync word, AAC-LC, mono, an allowlisted sample rate, frames that fill the chunk exactly. Audio is parsed only when the user presses Play or Copy Audio. | A bug in Apple's AAC decoder reachable with well-framed packets. |
| A machine floods voices or fills the disk. | 64 KB lines, 48 KB of audio per chunk, 4 MB and 10 minutes per voice, two in flight per machine, and the link's rate limit. Every voice is shown, so a flood is visible. | A machine can fill the history with small voices until it's unpaired. |
| A voice meant for one hub reaches another. | `follow` filters by `to`, and the hub checks `to` again. | Root on the sender can read the outbox; root is trusted on its own machine. |
| A transcript tricks the user. | Plain text only: control and bidirectional characters are removed, and it's shown as text, never as a link or Markdown. | The words themselves. |

## Not in this version

- Live playback on the receiving Mac.
- Sending to more than one Mac at once.
- Re-sending a voice from history.
- An iPhone app.
