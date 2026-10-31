# Remote agents: one hub Mac for agents on any machine

Date: 2026-10-28
Status: P0 and P1 are built. P2 and P3 are not started. The threat model (ER-40) still needs its review by someone
other than its author before P1 ships.

## Problem

Coding agents increasingly run away from the laptop: on devboxes, cloud VMs, a Mac mini in the closet, or
Codespaces and Coder workspaces, usually inside tmux over SSH. Ambient can't see any of them, and those are
the sessions people babysit most. The goal is for sessions from any machine the user can reach to show up
on one Mac they choose, the **hub**. They get the same island, notifications, pet, wallpaper and board as
local sessions. There are no accounts, no relay and no telemetry, and the design has to be one an
enterprise security team can approve.

## What the code does today (constraints)

- Hooks call `ambient hook`. It sends one JSON line to `~/.ambient/ambient.sock` with a 0.25 s timeout
  (`Sources/ambient/Hook.swift`).
- That socket is the app's **whole RPC surface** (`WireMessage`, `Sources/AmbientCore/Wire.swift`). Besides
  `event`, it serves:
  - `status`: every session.
  - `open`: runs focus routes, which use AppleScript, tmux and deep links.
  - `acknowledgeAll` and `upsertTask`.
  - `setTaskModel`: its `pythonPath` is later executed by the app.

  So whoever can write to the socket can run code on the Mac. That is safe today only because the socket is
  local and owned by the user.
- `AgentEvent.host` (`HostInfo`) is a *local* return address: pids, `agentPid` (session liveness), tty, the
  tmux socket and pane, and cmux ids. On a remote event these would point at unrelated local processes,
  Terminal tabs and tmux panes.
- `TaskLLM` sends session text only to loopback. Online voices and `ambient task skill-bootstrap`, on the
  other hand, can send text to cloud providers.

## Key decisions

1. **Never forward `ambient.sock`.** This reverses the first idea, `ssh -R` / `RemoteForward` of the socket.
   Remote input reaches the app only through a separate path that carries events and nothing else.
2. **Pull, not push.** The hub dials out and runs
   `<transport> ~/.ambient/bin/ambient-remote follow --since <cursor>`. Hooks on the remote machine only
   append to a local spool file, and `follow` streams the spool back as JSON lines on stdout. This gives:
   - no inbound port on the Mac or the remote;
   - no sshd changes (`StreamLocalBindUnlink` isn't needed);
   - durability while the hub sleeps;
   - a one-way channel by construction, since the hub sends nothing but the command line.
3. **The transport is a command the user or admin configures, with `ssh` as the default.** The user's own
   `ssh` and `~/.ssh/config` cover ProxyJump and bastions, Teleport, AWS SSM, GCP IAP, Tailscale SSH and
   short-lived certificates. Presets cover `gh codespace ssh`, `coder ssh` and `kubectl exec`. Ambient has
   no listener, crypto or authentication of its own: it inherits the organization's.
4. **Remote events are quarantined data.** They go through their own decoder with a strict schema and size
   limits. Remote `HostInfo` is dropped, and sessions are keyed by (machine, session id).
5. **Redaction happens on the remote machine, before spooling.** Text a policy removes never leaves it.

```
remote machine                                   hub Mac
agent hook                                       RemoteLink (one per machine)
  └─ ambient-remote emit                           spawns: ssh host ambient-remote follow --since N
       redact → append                             RemoteEventDecoder (strict, versioned)
  ~/.ambient/spool/events.jsonl  (0600, bounded)   dedupe (machine, eventId) → SessionStore
  ambient-remote follow ── JSON lines on stdout ─▶ audit log · policy · health
                    (over the org's SSH / SSM / IAP / Teleport)
```

## Enterprise requirements

Phase tags: **P0** foundations, **P1** v1, **P2** managed deployment, **P3** assurance and scale.

### A. Identity and access

- **ER-1 (P1)** The transport handles authentication (SSH keys and certificates, SSO-backed access tools).
  Ambient stores no remote credentials.
- **ER-2 (P1)** Ambient runs the user's own `ssh` with the user's config: ProxyJump, ProxyCommand,
  short-lived certificates, hardware keys, `ssh-agent` and ControlMaster all work. Ambient never ships its
  own SSH client.
- **ER-3 (P1)** A machine's identity is its SSH host key fingerprint, or an id the transport provides
  (workspace or pod), pinned when the machine is paired. The label is cosmetic. If the fingerprint changes,
  the link stops and has to be approved again.
- **ER-4 (P1, P2)** The hub keeps an allowlist and only follows paired machines; everything else is denied by
  default. In P2, admins can restrict machines by name pattern through MDM.
- **ER-5 (P1, P2)** Unpairing a machine removes its cursor and sessions, and optionally its remote hooks. A
  machine that MDM removes stops at the next reconnect.

### B. Least privilege and isolation

- **ER-6 (P0)** Remote input never reaches `ambient.sock` or `WireMessage`. The channel is one-way.
- **ER-7 (P0)** Remote events follow a strict schema:
  - fields come from an allowlist and states from an enum;
  - every field has a length cap, and a line is capped at 64 KB;
  - unknown events are rejected and counted;
  - remote content is rendered as plain text only.
- **ER-8 (P0)** The hub drops remote `HostInfo`. Focus routes, pid liveness checks, tmux, tty and AppleScript
  never run for a remote session. Liveness comes from `follow` (it reports when the agent exits) and from
  heartbeats.
- **ER-9 (P1)** Shared multi-user hosts are safe: the spool lives in the user's home (directory `0700`, file
  `0600`), with no TCP ports and no world-readable temp files. One user's events can't reach another
  user's hub.
- **ER-10 (P1)** The remote side runs unprivileged: no root, no sudo, no daemons and no sshd changes.

### C. Data protection and privacy

- **ER-11 (P1)** A published data inventory lists exactly which fields leave the remote machine at each
  redaction level.
- **ER-12 (P1, P2)** Redaction levels, applied on the remote machine:
  - `metadata`: state, agent, project, machine and times.
  - `standard`: adds tool names and short titles.
  - `full`: adds message text: up to 160 characters of the agent's final message, a permission prompt or an error.
    Prompts stay on the machine at every level (a P1 decision: nothing on the hub shows them, and local sessions
    don't send them either).

  The default is `standard` (decided 2026-10-28). Admins can lock a minimum level. P2 adds regex secret
  scrubbing (tokens, keys) for `full`.
- **ER-13 (P1)** Remote text has its own egress rules on the hub. It is never sent to online voices,
  `skill-bootstrap` or any non-loopback destination. Whether the local LLM may summarize remote sessions is a
  separate policy key.
- **ER-14 (P1)** Retention limits:
  - The remote spool has a size cap and a time limit (default 5 MB and 24 h).
  - Remote sessions on the hub follow the day log's retention.
  - "Purge machine" deletes everything from that machine on the hub. This also serves data-deletion
    requests.
- **ER-15 (P2)** Data at rest relies on FileVault on the Mac and disk encryption on the remote. This is
  documented, and `doctor` warns when remote sessions are on but FileVault is off.
- **ER-16 (P1)** No third party is in the path: no relay, no telemetry, and no network calls beyond the
  transport.

### D. Reliability

- **ER-17 (P1)** Hooks never block or fail the agent. They only append locally, within about 10 ms, and exit
  0 on any error.
- **ER-18 (P1)** Delivery is at least once, with deduplication. Each event has a random 128-bit `eventId`
  and a per-machine `seq`. The hub stores a cursor for each machine and resumes with `--since`.
- **ER-19 (P1)** Ambient tolerates being offline. When the hub sleeps or loses the network, events wait in
  the spool and replay on reconnect. A replayed "needs you" older than N minutes shows as *missed*, without
  a burst of chimes.
- **ER-20 (P1)** Link health is visible for each machine: connected, reconnecting, sign-in needed or
  revoked. Reconnects use exponential backoff with jitter and `ServerAliveInterval`. Sessions on a machine
  that can't be reached show as *unknown*, not "working" forever.
- **ER-21 (P1)** Events are ordered by `seq`, not by remote clock. Times are shown from when the hub
  received the event if the clocks drift past a threshold.

### E. Policy and managed deployment

- **ER-22 (P2)** macOS managed preferences (a configuration profile) control:
  - whether the feature is on;
  - allowed machines and patterns, and allowed transports;
  - the minimum redaction level and the LLM policy;
  - the ban on online voices for remote text;
  - spool limits.

  Settings shows forced keys as read-only, marked "Managed by your organization".
- **ER-23 (P2)** A system policy file on the remote machine, `/etc/ambient/remote.json`, overrides user
  settings (for example, it can force `metadata`). It is meant for golden images.
- **ER-24 (P2)** A non-interactive install for fleet tools:
  `ambient-remote install --agents claude,codex --redaction metadata`. It is idempotent, never prompts and
  returns clear exit codes. Examples ship for a devcontainer feature, cloud-init and Ansible.
- **ER-25 (P2)** The installer coexists with org-managed agent settings. If Claude Code's managed settings
  restrict hooks (for example `allowManagedHooksOnly`), it prints the snippet for an admin to add rather
  than editing user settings. The same goes for Codex.
- **ER-26 (P2)** A kill switch: one managed key stops every link immediately.

### F. Audit and observability

- **ER-27 (P1)** The hub keeps a local, append-only audit log in JSON lines. It records pairing and
  unpairing, fingerprint changes, policy changes, links going up and down, and rejected events with the
  reason. It records no event content.
- **ER-28 (P2)** The same audit records go to unified logging (an `os_log` subsystem for remote), so MDM,
  EDR and SIEM tools can collect them.
- **ER-29 (P1, P2)** `ambient doctor --remote <machine>` checks the transport, the shim's version and
  checksum, the spool, the hooks and how far the cursor lags. P2 adds a redacted support bundle.
- **ER-30 (P2)** Counters for each machine: events received, dropped and rejected; lag; and spool depth.

### G. Supply chain and integrity

- **ER-31 (P1)** The remote shim ships inside the signed, notarized app and is copied from there over the
  transport. It is never downloaded from the internet. Its SHA-256 is checked on the remote after copying
  and on every `doctor`.
- **ER-32 (P1)** The shim is plain POSIX `sh` that needs only coreutils, so it can be audited and there's no
  compiled binary on Linux. A static binary comes later, only if measurements call for it.
- **ER-33 (P3)** Releases publish an SBOM and checksums, and `THIRD_PARTY_NOTICES.md` is kept current.

### H. Compatibility and versioning

- **ER-34 (P0)** The remote protocol has its own version field (`v`), separate from `WireMessage`. The hub
  accepts the current and the previous version. The `follow` handshake reports the shim's version and
  capabilities, and a mismatch shows a clear upgrade prompt instead of silently dropping events.
- **ER-35 (P1, P2)** Remote platforms:
  - P1: Linux on x86_64 and arm64 (glibc), and macOS.
  - P2: musl (Alpine) and WSL2.
  - Shells: dash, bash and busybox ash.
- **ER-36 (P2)** A published JSON Schema for remote events lets tools without hooks emit them.

### I. Scale and environment types

- **ER-37 (P1, P3)** Targets for one hub: 25 machines, 300 live sessions and bursts of 50 events/s, with no
  UI lag. The UI groups sessions by machine. P1 adds a per-machine rate limit; P3 load-tests the targets.
- **ER-38 (P2)** Ephemeral environments (Codespaces, Coder, devcontainers, Kubernetes pods) are identified by
  the workspace id from the transport. A machine unseen for N days expires automatically.
- **ER-39 (P2)** Each hub keeps its own cursor, so two Macs can follow the same machine. Ambient warns about
  the duplicate alerts this causes, and choosing a hub is just a matter of which Mac holds the link.

### J. Compliance and assurance

- **ER-40 (P0)** A STRIDE threat model of the remote path is written and reviewed before P1 ships.
- **ER-41 (P3)** A security and data-flow whitepaper for security questionnaires covers the data inventory,
  data flows, retention, the absence of telemetry, and how the design maps to common SOC 2 and
  ISO 27001 controls.
- **ER-42 (P3)** An external security review of the remote path happens before it is offered to
  enterprises.

## Remote protocol v1 (decided in P0)

### Spool line

`ambient-remote emit` appends one JSON object per line. The hub's `RemoteEventDecoder`
(`Sources/AmbientCore/Remote/RemoteEvent.swift`) accepts only these fields; any other key, a duplicate key, a
nested value or a wrong type rejects the whole line.

| Field | Type and cap | Required | Notes |
|---|---|---|---|
| `v` | integer | yes | Protocol version. The hub accepts the current (1) and the previous one. |
| `seq` | integer, 1…2^53 | yes | Per-machine order, assigned under a lock on the remote. |
| `id` | 32 lowercase hex | yes | Random 128-bit event id, for deduplication. |
| `ts` | integer, Unix seconds | yes | The remote clock; display only (ER-21). |
| `agent` | `AgentKind` raw value | yes | `claude`, `codex`, … |
| `session` | string ≤ 128 | yes | The agent's session id. |
| `kind` | enum, see below | yes | |
| `project` | string ≤ 64 | no | The working folder's name, never the path. |
| `tool` | string ≤ 64 | no | `standard` and `full` only. |
| `title` | string ≤ 80 | no | `standard` and `full` only. |
| `reason` | `permission` or `question` | no | For `needsInput`. |
| `message` | string ≤ 160 | no | `full` only. |

`kind` is one of `sessionStarted`, `promptSubmitted`, `toolStarted`, `toolFinished`, `toolFailed`,
`needsInput`, `compactStarted`, `compactFinished`, `subagentStarted`, `subagentFinished`, `turnCompleted`,
`turnFailed`, `sessionEnded`, `notice`, `titleChanged` and `agentExited`. The last two are written by
`follow`, not by hooks.

Limits: a line is capped at 64 KB, and nesting deeper than a flat object is refused by a byte scan, both before
parsing (a deeply nested line would otherwise exhaust the parser's stack). The shim cuts text to its cap, in characters, so
what the hub would throw away never leaves the machine, and the hub cuts it again. Control and bidirectional formatting
characters are removed, no character keeps more than 16 Unicode scalars, since caps count characters and combining marks
pile onto one without limit, and the result is plain text on every surface. The hub also drops `tool`, `title` and
`message` when they're above the level `hello` reports, which covers lines spooled before a level was tightened. Lines
that fail any check are dropped and counted, and the audit log records the reason without the content.

### Session keys and the quarantine

- A remote session's id is `remote/<machine>/<agent>:<session>`. Local ids always start with an agent name, so
  the two can't collide, and a local hook can't address a remote session or the reverse.
- `Session.origin` (a `RemoteOrigin`) is set only for remote sessions. The field name `host` stays with
  `HostInfo`, which a remote session never has: the decoder has no field to carry it, and the store's remote
  path ignores it.
- For a session with an origin, `FocusPlanner` returns no routes, `Focuser` and `AppModel.open` return before
  any AppleScript, tmux, tty or deep link, `SessionStore.sweep` never calls the pid check, host-app
  acknowledgement skips it, and `SessionTitles` never reads local transcripts for it.
- Remote events reach the app only through `SessionStore.apply(_:from:)`, never through `WireMessage` or the
  Unix socket.

### Machine identity

`Machine` (`Sources/AmbientCore/Remote/Machine.swift`) has:
- an id: the name used on the command line, lowercase letters, digits, `.`, `_` and `-`, at most 32;
- a cosmetic label;
- the transport command;
- the pinned fingerprint.

The fingerprint is the SHA-256 fingerprint of the remote's SSH host key as `follow` reports it in its
handshake, or, where the shim can't read a host key (containers), the random install id it generated. See the
threat model for what that pin does and does not prove.

Before `ambient remote add` or `remove --uninstall` changes anything on a pinned machine, the hub sends this app's shim on
stdin with `sh -s identity`. That needs nothing installed and writes nothing there, not even an install id, so a machine
that turns out not to be the pinned one is left exactly as it was. One that can't be asked isn't changed either.

## How P1 is built

### The shim

`Resources/ambient-remote` ships at `Contents/Resources/ambient-remote` and is sealed by the app's signature.

- `emit` forks only `awk`, `ln` and `rm`, and reads hook payloads through one `awk` tokenizer that needs nothing
  beyond POSIX. Measured on an arm64 MacBook under dash: 7 ms at p50 for a small payload, 10 ms for 200 KB of tool
  output, 25 ms for 200 KB of nothing but escaped quotes. Those numbers include about 3.5 ms per process that Linux
  doesn't pay. Claude Code and Codex run these hooks in the background (`async`), except `SessionEnd`.
- `seq` is assigned under a lock, so file order and `seq` always agree. The lock is a symlink to the holder's pid,
  because creating one is atomic and names the holder in the same step: a `mkdir` lock with a pid file inside has a
  moment with no owner, and waiters took a live lock for a stale one and let two writers in. Only a holder that died
  holding the lock loses it, after about 250 ms, and one waiter at a time clears it. A holder killed but not yet reaped
  still counts as alive, which only matters to a parent that doesn't reap its children.
- An event that can't get the lock in about 3 s is dropped. That takes hundreds of simultaneous hooks: 400 at once all
  arrive, and the shim's test keeps 200 at once in every run. It stays under the hooks' own 5 s timeout, and only
  `SessionEnd` makes an agent wait.
- `follow` polls the `seq` file once a second, so a "needs you" arrives within about a second plus the transport's
  latency. It sends a heartbeat every 15 s.
- Agent exit: `emit` records the agent's pid (first ancestor that isn't a shell) once per session in
  `spool/live/`, and `follow` reports `agentExited` when it's gone. The pid never leaves the machine.
- Titles: `follow` reads the agent's own title (Claude's `custom-title` transcript entry, Codex's
  `session_index.jsonl`) every 30 s and spools `titleChanged`, so `emit` never scans a file. Off at `metadata`.
- Malformed spool lines are forwarded once, after a later event seals them, so the hub can reject and record them. A
  line still being appended is never mistaken for one.
- Retention runs whenever the shim runs: on every 64th event, when `follow` starts and every 10 minutes while it
  runs. There's no daemon (ER-10), so an idle machine with no hub keeps its spool until the next event or connection.
  `follow` never sends a line past the age limit.
- `identity` prints who the machine is and writes nothing. The hub runs it from stdin, before anything is installed.
- `install` edits agent configs with `python3`, the one place the shim needs more than coreutils (a refinement of
  ER-32): rewriting a user's JSON from `awk` isn't safe enough. It keeps a backup, leaves the user's own entries alone,
  and without `python3` writes a fresh file or prints the snippet and exits 3.
- `uninstall` without `python3` still removes the spool, settings and shim, then exits 3 and says which hooks to remove
  by hand. They do nothing once the shim is gone, and a spool must never outlive the request to clear it.

### The transport contract

The transport is an argv. Ambient appends one argument, a shell string for the machine's login shell, the way `ssh`
takes it. Stdin is `/dev/null` while following, so the hub can't send anything. `ambient remote add NAME` builds
`ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ForwardAgent=no
-o ForwardX11=no -o ClearAllForwardings=yes NAME`. It stays up with nobody watching and only ever reads, so it forwards
nothing, whatever the user's config says for that host. A machine keeps the transport it was paired with: one paired
before the forwarding options were added has none of them until it's paired again, and a command given after `--` is the
user's own. `--host` can't start with `-`, which ssh would take as an option.

### Delivery

- `RemoteLink` owns one thread per machine, and `RemoteIngest` makes every decision about the stream, with no I/O
  beyond the audit log.
- `follow`'s handshake and heartbeats are `RemoteLine` control lines with their own allowlist. `hello` carries the
  shim's version, protocol, capabilities, level, head `seq`, spool `epoch`, identity and clock.
- A new `epoch`, or a `seq` lower than the cursor, means the spool was replaced: the cursor resets and the link starts
  over. Without this a rebuilt machine would look silent forever.
- Events at or below the handshake's `seq` are a replay. A replayed `needsInput`, `turnCompleted` or `turnFailed` older
  than 10 minutes is *missed*: shown, never chimed, and kept past the usual waiting timeout until it's seen.
- **No lost or duplicated alerts:** the cursor lives in `state.json` with the sessions, so they can't disagree. A batch
  that would alert saves both *before* anyone is told. A hub killed earlier replays the batch and alerts then; killed
  later, it restarts past it. Everything else saves on the usual debounce, and replays harmlessly. The one window left
  is between the save and the notification itself, microseconds wide, where an alert can be lost but not repeated.
- **Rate limit:** a token bucket per machine (50 events/s, burst 500) holds events back rather than dropping them, so a
  flood delays only its own machine. Replays have their own bucket, at the same rate with a burst of 40,000, more than a
  full 5 MB spool of the shortest real lines (about 165 bytes). `hello.seq` is whatever the machine says, so replays can't
  run free: the bucket lives on `RemoteIngest`, across reconnects, and a machine that calls everything a replay spends it
  and is paced like any other.
- **Backpressure:** the link hands the app one batch at a time and reads no more until it's applied, so a fast machine
  fills its own pipe rather than the main queue. `stop()` releases that wait, so nothing depends on the main thread
  answering, which matters when the main thread is what's waiting for the link to stop.
- **Limits:** 1,000 sessions per machine at once and 5,000 tasks per machine. ER-37 plans for 300 sessions across a whole
  hub, and sessions leave when they end or sit quiet for two hours, so only a flood gets near the first. Events for new
  sessions past it are dropped and counted in the audit log as `sessionLimit`. Tasks never expire by themselves, so past the
  second a machine's oldest go, which also holds a session start/end loop to it. The largest real board measured had
  1,626 tasks from every source. Tasks the user wrote are never dropped, and local tasks have no limit.
- Clocks further apart than 2 minutes at the handshake are corrected for (ER-21).
- A link that hears nothing for 45 s is dead. Backoff doubles from 1 s to 60 s with 20% jitter, and resets after 30 s
  up. A refused sign-in retries once a minute. A replaced spool restarts at once; a second restart in a row backs off too.
- Sessions show as *unknown* after 30 s of failed reconnects, or at once for sign-in, identity and upgrade failures.

### What the hub keeps

- `~/.ambient/remote/machines.json`: the allowlist (ER-4). The CLI writes it and the app polls it every 5 s, so pairing
  needs no new `WireMessage`.
- `~/.ambient/remote/audit.jsonl`: rejections, spool gaps and resets, held-back events and refused sessions are written
  at most once a minute per reason, with a count, so a machine can't fill it or push older records out. It rotates at 5 MB.
- Remote sessions in `state.json` and tasks in `tasks.json`. Tasks never merge across machines.
- The day log counts remote turns, but keeps only "Claude on Devbox" as the place: no titles or projects.
- `ambient remote remove` drops the sessions and cursor. `purge` also deletes the board tasks and today's moments,
  edits the files directly, and leaves a marker for a running app to clear what it holds in memory.

### Egress

`RemoteEgress` is the rule, and `AppModel` applies it where session text can leave: the board's summarizer, behind
`remoteSummaries` (off by default) and a loopback check. `skill-bootstrap` sends a fixed prompt and no session text,
and online voices read only what the user selects in another app; Ambient's own session text can't be selected. Both
are allowed for no remote session.

### Tests

`RemoteEndToEndTests` run the real shim through a `sh -c` transport: pairing, redaction, a hub killed at five points
mid-stream, the hook's latency, a malformed spool line, replays, identity changes, reconnects, a rebuilt spool, agent
exit, `doctor` and purge. `AMBIENT_TEST_SSHD=1` adds the same path over a throwaway `sshd` on loopback.

`scripts/test-remote-shim.sh` runs the shim itself under every shell and `awk` it finds, and checks its output with a
strict JSON parser. CI runs it on Linux with dash, bash, busybox ash, mawk and gawk (ER-35). The 25-machine targets
(ER-37) wait for P3.

## Threat model (STRIDE, ER-40)

Assets: the hub Mac (code execution, the user's files, the Ambient socket), the remote machine, and session
text in transit and at rest. Trust boundaries: the remote machine and the hub; the transport between them; and,
on the hub, `RemoteLink` and the rest of the app.

| Threat | Example | Mitigation | Residual risk |
|---|---|---|---|
| **S**poofing a machine | An ssh alias is re-pointed, or a reinstalled machine takes over a name. | The transport authenticates the host (ssh `known_hosts`, certificates, SSM, IAP). Ambient pins the reported fingerprint at pairing; a change stops the link until the user approves it again (ER-3). Pairing again and `remove --uninstall` ask who the machine is first, in a way that writes nothing there. | The fingerprint is reported by the remote, and a host key's fingerprint is public, so a malicious remote that already passed the transport's own check can claim the old one. The pin stops honest mistakes, not a liar. It can then only send quarantined display data. |
| **S**poofing a session | A remote event names a local session id, or a local hook names a remote one. | Remote ids are namespaced `remote/<machine>/…`; local ids can't take that form. Permission prompts are local, and a remote session with the same id can't withdraw one. | None known. |
| **T**ampering with events | Another user on a shared host writes to the spool. | The spool directory is `0700` and its files `0600`, in the user's own home (ER-9). | Root on the remote can write anything; root is trusted on its own machine. |
| **T**ampering with the shim | The copied `ambient-remote` is altered on the remote. | It comes from the signed app bundle, and its SHA-256 is checked after copying and on every `doctor` (ER-31). | The machine reports that hash itself, so the check catches accidents, not a liar. A local attacker with the user's rights on the remote can alter the shim, and so can an agent there that's been talked into it. They can already alter that user's agents, and against the hub they get what a malicious machine gets: the rows below, not more. |
| **R**epudiation | "I never paired that machine." | Append-only local audit log of pairing, unpairing, fingerprint changes, link changes and rejections (ER-27). Whatever a machine can repeat at will is written at most once a minute per reason, so it can't rotate older records out. | The log is local and the user can edit it, and it keeps two files of 5 MB; P2 adds `os_log` for MDM collection. |
| **I**nformation disclosure in transit | Session text crosses the network. | Only over the user's own transport; no relay or third party (ER-16). | Whatever the transport allows. |
| **I**nformation disclosure at rest | Prompts sit in the spool or on the hub. | Redaction on the remote before spooling, default `standard` (no prompt or message text), and again on the hub against the level the machine reports; spool capped at 5 MB and 24 h; sessions leave the hub after two quiet hours and moments at midnight; purge per machine (ER-12, ER-14). | `full` keeps text on disk on both sides until it ages out. A tightened level doesn't clear the spool: those lines still cross the transport, and only the hub drops them. Titles and project names on the board don't age out: a machine's tasks stay until it's purged or its oldest make way past 5,000. |
| **I**nformation disclosure to third parties | Remote text reaches an online voice or a cloud model. | Remote text never goes to online voices, `skill-bootstrap` or any non-loopback URL; the local LLM needs a separate opt-in (ER-13). | None known. |
| **D**enial of service | A remote floods events, writes huge lines, or calls everything a replay. | 64 KB line cap; field caps, with 16 scalars per character; 50 events/s per machine, plus a replay bucket that reconnecting doesn't refill; 1,000 sessions and 5,000 tasks per machine; the link reads no more until the app has applied what it has; restarts back off (ER-7, ER-37). | A flood delays that machine's own events and costs the app main-thread time: with `AppModel` under test but no UI, the worst stall was about a second as the limits filled, then about 0.3 s on a full board, at about 70 MB. The same machine can raise notifications and chimes at up to that rate until it's unpaired. Not yet load-tested with the UI on screen (P3). |
| **D**enial of service to the agent | A slow hook blocks the agent. | `emit` only appends locally, takes about 10 ms and always exits 0 (ER-17). | A full disk drops events silently. |
| **E**levation of privilege on the hub | A remote sends `setTaskModel`, `open` or any `WireMessage`, or a payload aimed at AppleScript, tmux or a pid. | The socket is never forwarded and the Mac opens no port (decision 1). Remote lines go through their own decoder, which has no `WireMessage` cases, and the quarantine drops `HostInfo` so no focus route, pid check, tty or AppleScript ever runs for a remote session (ER-6, ER-8). Whatever the CLI prints from a machine is plain text, so it can't carry terminal escapes. Tests in `AmbientCore` prove these; the guards in `AppModel` and `Focuser` are in the app target, which has no tests. | Bugs in the decoder; P3 adds an external review. |
| **E**levation through the transport | The link stays up unattended, carrying the user's ssh agent or forwarded ports. | The `ssh` command Ambient builds turns off agent, X11 and port forwarding, over whatever the config says (decision 1). | Only that command: one given after `--`, or one stored before these options, stays as it was, and a shared ControlMaster connection keeps its own forwards. |
| **E**levation of privilege on the remote | Ambient needs root or opens a port. | The shim runs as the user with no daemon, no port and no sshd change (ER-10). | None known. |

### Review, 2026-11-01

An independent agent, with no part in writing this model or the code, checked each row above against the code on
2026-11-01, including a run of the shim against hostile payloads. It found no code execution, exfiltration or quarantine
escape, and one blocker: a machine that claimed a huge `hello.seq` escaped the rate limit, nothing capped its sessions or
tasks, and the link queued to the main thread without limit. On the code as it stood, a machine doing that left the main
queue falling behind by a second every second, and 1.5 GB resident after 30 s. Its findings were fixed in one branch,
which changed this document too:

- the replay bucket, the session and task limits, and backpressure;
- restarts that back off, and audit records a machine can repeat throttled to one a minute per reason;
- plain text in what the CLI prints from a machine, and a cap on scalars per character;
- text cut to its cap on the machine, and redaction applied again on the hub against the machine's level;
- an identity check that writes nothing, before pairing again or `remove --uninstall` changes a machine;
- no forwarding on the `ssh` command Ambient builds, `--host` refused when it starts with `-`, `umask 077` in `uninstall`, and
  no way for a remote session to withdraw a local permission prompt.

This records what was reviewed and changed. It doesn't settle ER-40: see the open questions.

## Phases

### P0: Foundations (before any remote code ships)

1. Threat model (ER-40).
2. A `RemoteEvent` type with a strict, versioned decoder and limits, kept separate from `WireMessage`
   (ER-6, ER-7, ER-34).
3. A `Machine` identity. Sessions are keyed by (machine, session id), and `HostInfo` is quarantined for
   remote sessions in `SessionStore`, `AppModel.open` and the liveness checks (ER-8).

Done when: the decoder has fuzz and limit tests, and tests prove that remote events can't trigger focus
routes, pid checks or any `WireMessage` handling.

### P1: v1 for personal use, with enterprise-safe defaults

1. `ambient-remote` in POSIX `sh`, with these commands:
   - `emit`: the hook entry point; it redacts and appends to the spool.
   - `follow --since`
   - `install` and `uninstall`
   - `version`
2. `RemoteLink` on the hub: it spawns the transport, reconnects with backoff, stores cursors, deduplicates
   and reports health.
3. `ambient remote add|remove|list|purge <machine>` and a Settings › Remote pane. Pairing pins the
   fingerprint.
4. Policy: redaction levels, egress rules for remote text and spool limits.
5. The audit log and `ambient doctor --remote`.
6. UI: the machine's label everywhere a session appears, link status, and *unknown* and *missed* states.
7. Docs: a README section and the data inventory. Reword "Everything stays on your Mac" to cover the
   user's own machines over their own transport.

Done when an end-to-end test against a `sh -c` transport stub and a local `sshd` shows all of the
following:
- killing the hub mid-stream and restarting it loses and duplicates no alerts;
- the hook stays within its latency budget;
- a malformed spool line is rejected and recorded in the audit log.

### P2: Managed deployment

MDM profile and forced keys, `/etc/ambient/remote.json`, the non-interactive install with devcontainer,
cloud-init and Ansible examples, detection of managed agent settings, `os_log`, the kill switch, ephemeral
environments, transport presets (SSM, IAP, Teleport, `gh codespace`, `coder`, `kubectl`), secret scrubbing,
the support bundle, counters, and the musl and WSL2 platforms.

### P3: Assurance and scale

The load test against the ER-37 targets, the SBOM, the whitepaper and the external security review.

## Out of scope

- Approving or answering agent prompts from the hub (remote control).
- A team-wide dashboard or a central server.
- A push listener on the Mac.
- A Windows hub.

## Decided in P1

- The board's local LLM doesn't summarize remote sessions unless the user turns that on.

## Open questions

- Does the agent review below meet ER-40? ER-40 asks for a review before P1 ships. An agent reviewed this threat model
  and the fixes it asked for are in, but whether an agent's review counts is the project owner's decision, and it hasn't
  been made. Until it is, treat ER-40 as open.
- Is native Windows needed on the remote side, beyond WSL2?
- Should the pin bind to the key the transport verified? Today the machine reports its own host key. Parsing it from
  `ssh -v` would hold against a malicious machine, but only for ssh, and only by reading debug output.
