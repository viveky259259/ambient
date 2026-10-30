# Security

Ambient runs locally. Its attack surface is the Unix socket at `~/.ambient/ambient.sock` (mode 0600 inside a 0700
directory) and the agent config files it edits.

## What Ambient reads on your Mac

Besides agent hook events and the config files it edits, Ambient reads two things to keep hooks working, and
keeps them on your Mac:

- **Agent processes**, once a minute: for agent sessions attached to a terminal (Claude Code, Codex, `agy`), the
  process id, executable path, start time, CPU time and whether a terminal is attached, to spot a busy session
  whose hooks never reached Ambient. Never arguments, environment or output.
- **Agent executables**: the path, size and modification date of each agent's executable, saved with the agents
  you connected in `~/.ambient/agents.json`, to notice when an agent updates.

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
