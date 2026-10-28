# Remote agents: one hub Mac for agents on any machine

Date: 2026-10-28
Status: P0 (foundations) is built on `feat/remote-agents-p0`. P1 follows on a stacked branch. P2 and P3 are not
started.

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
  - `full`: adds prompt and message text.

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
parsing (a deeply nested line would otherwise exhaust the parser's stack). Text is cut to its cap, control and bidirectional
formatting characters are removed, and the result is plain text on every surface. Lines that fail any check
are dropped and counted, and the audit log records the reason without the content.

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

## Threat model (STRIDE, ER-40)

Assets: the hub Mac (code execution, the user's files, the Ambient socket), the remote machine, and session
text in transit and at rest. Trust boundaries: the remote machine and the hub; the transport between them; and,
on the hub, `RemoteLink` and the rest of the app.

| Threat | Example | Mitigation | Residual risk |
|---|---|---|---|
| **S**poofing a machine | An ssh alias is re-pointed, or a reinstalled machine takes over a name. | The transport authenticates the host (ssh `known_hosts`, certificates, SSM, IAP). Ambient pins the reported fingerprint at pairing; a change stops the link until the user approves it again (ER-3). | The fingerprint is reported by the remote, so a malicious remote that already passed the transport's own check can claim the old one. It can then only send quarantined display data. |
| **S**poofing a session | A remote event names a local session id, or a local hook names a remote one. | Remote ids are namespaced `remote/<machine>/…`; local ids can't take that form. | None known. |
| **T**ampering with events | Another user on a shared host writes to the spool. | The spool directory is `0700` and its files `0600`, in the user's own home (ER-9). | Root on the remote can write anything; root is trusted on its own machine. |
| **T**ampering with the shim | The copied `ambient-remote` is altered on the remote. | It comes from the signed app bundle, and its SHA-256 is checked after copying and on every `doctor` (ER-31). | Between checks, a local attacker with the user's rights on the remote can alter it; they can already alter that user's agents. |
| **R**epudiation | "I never paired that machine." | Append-only local audit log of pairing, unpairing, fingerprint changes, link changes and rejections (ER-27). | The log is local and the user can edit it; P2 adds `os_log` for MDM collection. |
| **I**nformation disclosure in transit | Session text crosses the network. | Only over the user's own transport; no relay or third party (ER-16). | Whatever the transport allows. |
| **I**nformation disclosure at rest | Prompts sit in the spool or on the hub. | Redaction on the remote before spooling, default `standard` (no prompt or message text); spool capped at 5 MB and 24 h; hub data follows the day log; purge per machine (ER-12, ER-14). | `full` keeps text on disk on both sides until it ages out. |
| **I**nformation disclosure to third parties | Remote text reaches an online voice or a cloud model. | Remote text never goes to online voices, `skill-bootstrap` or any non-loopback URL; the local LLM needs a separate opt-in (ER-13). | None known. |
| **D**enial of service | A remote floods events or writes huge lines. | 64 KB line cap, field caps, per-machine rate limit, strict decoder that never allocates beyond the line (ER-7, ER-37). | A flood can still delay that machine's own events. |
| **D**enial of service to the agent | A slow hook blocks the agent. | `emit` only appends locally, takes about 10 ms and always exits 0 (ER-17). | A full disk drops events silently. |
| **E**levation of privilege on the hub | A remote sends `setTaskModel`, `open` or any `WireMessage`, or a payload aimed at AppleScript, tmux or a pid. | The socket is never forwarded and the Mac opens no port (decision 1). Remote lines go through their own decoder, which has no `WireMessage` cases, and the quarantine drops `HostInfo` so no focus route, pid check, tty or AppleScript ever runs for a remote session (ER-6, ER-8). Tests prove each of these. | Bugs in the decoder; P3 adds an external review. |
| **E**levation of privilege on the remote | Ambient needs root or opens a port. | The shim runs as the user with no daemon, no port and no sshd change (ER-10). | None known. |

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

## Open questions

- Should the board's local LLM summarize remote sessions by default?
- Is native Windows needed on the remote side, beyond WSL2?
