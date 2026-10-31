# Security

Ambient runs locally. Its attack surface is the Unix socket at `~/.ambient/ambient.sock` (mode 0600 inside a 0700
directory), the agent config files it edits, and, if you pair remote machines, what those machines send back.

## Remote machines

Ambient follows only machines you pair, over a transport you configure (your own `ssh` by default). It never forwards
or exposes the socket, opens no listening port, and stores no remote credentials, and the `ssh` command it builds
forwards nothing. A paired machine's output goes through a separate, strict decoder and can only become display data:
it can't reach the socket, and no focus route, pid check, tty, tmux or AppleScript ever runs for a remote session.

A remote machine you don't trust can't run anything on your Mac, but it can do more than lie about itself. It can show
you false states and text, raise notifications and chimes for them, and use up its own limits: 50 events a second, 1,000
sessions and 5,000 board tasks, which pushes out its own older tasks and costs the app some work. It can claim the
identity you pinned, because that's something it reports about itself. An agent on that machine can do all of this if
something it reads talks it into it, since it runs as the same user as the spool and the shim.

The threat model is in [the spec](docs/superpowers/specs/2026-10-28-remote-agents-design.md#threat-model-stride-er-40).

## What Ambient reads on your Mac

Besides agent hook events and the config files it edits, Ambient reads two things to keep hooks working, and
keeps them on your Mac:

- **Agent processes**, once a minute: for agent sessions attached to a terminal (Claude Code, Codex, `agy`), the
  process id, executable path, start time, CPU time and whether a terminal is attached, to spot a busy session
  whose hooks never reached Ambient. Never arguments, environment or output.
- **Agent executables**: the path, size and modification date of each agent's executable, held in memory only, to
  notice when an agent updates. `~/.ambient/agents.json` stores only which agents you connected.

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

Separately, paired remote machines are reached through the transport command you chose. Ambient runs that command and
makes no other connection for them.

Please report vulnerabilities privately through GitHub's *Report a vulnerability* on this repository
rather than in a public issue. You'll get a reply within a week.
