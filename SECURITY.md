# Security

Ambient runs locally. Its attack surface is the Unix socket at `~/.ambient/ambient.sock` (mode 0600 inside a 0700
directory) and the agent config files it edits.

## Network

Ambient makes network requests only for reading aloud, and only when you choose to:

- **Offline voice download**, when you click Download in Settings › Voice: the Kokoro-82M model and voices from
  Hugging Face at a fixed commit, and the `ambient-voice` helper from this repository's `voice-<version>` release.
  Every file is checked against a SHA-256 hash compiled into Ambient, and the helper's code signature must belong to
  Ambient's Developer ID team, before anything is moved into `~/.ambient/voice`. A failed check installs nothing.
- **Online voice**, if you choose one: the text you select is sent to OpenAI, ElevenLabs or the server URL you
  entered, with your API key. Keys are stored only in your login Keychain, under the service
  `com.viveky259259.Ambient.voice`, never in files or preferences.

With a Mac voice or the installed offline model, reading aloud makes no network requests.

Please report vulnerabilities privately through GitHub's *Report a vulnerability* on this repository
rather than in a public issue. You'll get a reply within a week.
