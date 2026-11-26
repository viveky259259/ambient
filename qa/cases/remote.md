# Remote machines

Id prefix: `RMT-`. Agents on other machines, followed over the user's own ssh: pairing, the `ambient-remote` shim,
the link and its health, how remote sessions show, the quarantine of what a machine sends, unpairing and purging, and
the promise that nothing but the user's transport touches the network.

Common setup for these cases, unless a case says otherwise:

- **Mac**: Ambient.app installed from a release build (so `ambient-remote` is inside the bundle), running.
- **Devbox**: a Linux or macOS machine you can `ssh devbox` into with a key, with Claude Code (and Codex if a case
  says so) installed, `python3`, and its host key already in the Mac's `~/.ssh/known_hosts`.
- Paths on the Mac are under `~/.ambient/remote/`; paths on the machine are under `~/.ambient/` there.

### RMT-001 · Pairing copies the shim, verifies it and pins the machine

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Remote/RemotePairing.swift`, `Sources/AmbientCore/Remote/RemoteTransport.swift`, `Sources/AmbientCore/Remote/RemoteFiles.swift`, `Sources/AmbientCore/Remote/Machine.swift`, `Resources/ambient-remote`
- **Automated by:** `RemoteEndToEndTests.pairingCopiesVerifiesInstallsAndPins`, `RemoteEndToEndTests.overARealSSHServer`
- **Needs:** a devbox reachable as `ssh devbox`, with Claude Code and Codex installed and `python3`

**Steps**

1. On the Mac, run `ambient remote add devbox`.
2. On the devbox, run `ls -l ~/.ambient/bin/ambient-remote`, `cat ~/.ambient/remote.conf` and `grep -c ambient-remote ~/.claude/settings.json ~/.codex/hooks.json`.
3. On the Mac, run `ls -l ~/.ambient/remote/` and `ambient remote list`.

**Expected**

- The CLI prints, in order: *• Pairing devbox over ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o ForwardAgent=no -o ForwardX11=no -o ClearAllForwardings=yes devbox…*, *Copied ambient-remote 1.0.7; checksum verified*, the shim's own install lines (e.g. *ok claude: hooks added to /home/…/.claude/settings.json*), *Paired devbox · level standard* and *Identity SHA256:…* (or *id:* and 32 hex digits on a machine without readable ssh host keys). Exit status 0.
- With Codex hooks installed it also notes *Codex asks you to trust new hooks: run /hooks in Codex on that machine once.*
- On the devbox: `ambient-remote` is `-rwx------`; `remote.conf` holds `redaction=standard`, `spool_max_bytes=5242880`, `spool_max_age=86400`; Claude Code's settings hold 14 hook commands mentioning `.ambient/bin/ambient-remote` and Codex's 11.
- On the Mac: `machines.json` is `-rw-------` inside a `drwx------` folder; `ambient remote list` shows `devbox`, its transport, *no events yet* (or *seq N*) and the fingerprint on the next line.
- Within 5 seconds of pairing (the app rereads `machines.json` every 5 s), Settings › Agents › Other Machines lists devbox as *Connected*.

### RMT-002 · A shim whose checksum doesn't match pairs nothing

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemotePairing.swift`, `Sources/AmbientCore/Remote/RemoteTransport.swift`
- **Automated by:** `RemoteEndToEndTests.aChecksumMismatchPairsNothing`
- **Needs:** a devbox where you can put a fake `sha256sum` first on the non-interactive ssh `PATH` (or a local fake transport script, as the tests use)

**Steps**

1. On the devbox, make `sha256sum` (or `shasum` on macOS) print `0000000000000000000000000000000000000000000000000000000000000000  file` and put it first on the `PATH` an `ssh devbox 'command -v sha256sum'` sees.
2. On the Mac, run `ambient remote add devbox2 --host devbox`.
3. Run `ambient remote list` and `grep devbox2 ~/.ambient/remote/audit.jsonl`.

**Expected**

- The CLI ends with *The shim on the machine doesn't match the app's: expected <64 hex>, got 0000…. Nothing was paired.* and exits 1.
- `devbox2` is not in `ambient remote list`, and the audit log has no `paired` record for it.
- The devbox's agent config files are unchanged: install never ran.

### RMT-003 · A host that looks like an ssh option is refused

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Remote/Machine.swift`
- **Automated by:** `RemoteQuarantineTests.aHostIsNeverAnOption`
- **Needs:** nothing special

**Steps**

1. Run `ambient remote add evil --host '-oProxyCommand=touch /tmp/pwned'`.
2. Run `ls /tmp/pwned`.

**Expected**

- The CLI prints *'-oProxyCommand=touch /tmp/pwned' isn't a host name. For ssh options, use `-- ssh ... HOST`.* and exits 64.
- No ssh process ran: `/tmp/pwned` doesn't exist, and nothing is added to `~/.ambient/remote/machines.json`.

### RMT-004 · A machine name outside the allowed form is refused

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Remote/Machine.swift`, `Sources/AmbientCore/Remote/RemoteFiles.swift`
- **Automated by:** `RemoteQuarantineTests.machineIdsAndFingerprintsAreStrict`, `RemoteStateTests.machinesAndCursorsSurviveTheirFiles`
- **Needs:** nothing special

**Steps**

1. Run `ambient remote add Dev_Box`, then `ambient remote add a-name-that-is-longer-than-thirty-two-chars`.
2. Quit Ambient, hand-edit `~/.ambient/remote/machines.json` to add a machine with id `Bad Name` and a valid fingerprint, and reopen Ambient.

**Expected**

- Each add prints *'<name>' isn't a valid machine name. Use lowercase letters, digits, '.', '_' and '-', at most 32 characters.* and exits 64, before any ssh runs.
- The hand-added machine is ignored: it isn't listed by `ambient remote list` or in Settings, and no ssh process is started for it. Other machines in the file still connect.

### RMT-005 · The ssh command Ambient builds forwards nothing

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/Machine.swift`, `Sources/AmbientCore/Remote/RemoteTransport.swift`
- **Automated by:** `RemoteQuarantineTests.theDefaultTransportForwardsNothing`
- **Needs:** a devbox; an ssh agent with a key loaded on the Mac

**Steps**

1. In `~/.ssh/config` on the Mac, give `Host devbox` the lines `ForwardAgent yes` and `LocalForward 9999 localhost:22`.
2. Pair it with `ambient remote add devbox` and wait for *Connected*.
3. On the devbox, find the `ambient-remote follow` process and read its environment (`tr '\0' '\n' < /proc/<pid>/environ | grep SSH_AUTH_SOCK` on Linux).
4. On the Mac, run `lsof -nP -iTCP:9999 -sTCP:LISTEN`.

**Expected**

- `ps` on the Mac shows the link's ssh with `-o ForwardAgent=no -o ForwardX11=no -o ClearAllForwardings=yes` before the host.
- The follow process has no `SSH_AUTH_SOCK`, and nothing on the Mac listens on 9999 for the link, whatever the config says.

### RMT-006 · Any transport after `--`, with a display label

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Remote/Machine.swift`, `Sources/AmbientCore/Remote/RemoteTransport.swift`
- **Automated by:** none
- **Needs:** a machine reached through a jump host (or any command that runs a shell command on it)

**Steps**

1. Run `ambient remote add build --label "Build box" -- ssh -J bastion build.internal`.
2. Start a Claude Code session on `build.internal`.

**Expected**

- The CLI prints *• Pairing build over ssh -J bastion build.internal…* and then *Paired Build box · level standard*.
- `ambient remote list` shows `build`, then *Build box*, then exactly `ssh -J bastion build.internal` (no options added).
- The session's rows in the island, menu bar and Settings say *Build box*, not `build`.

### RMT-007 · An unknown host key fails pairing instead of asking

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Remote/Machine.swift`, `Sources/AmbientCore/Remote/RemotePairing.swift`, `Sources/AmbientApp/Settings/Panes/RemotePane.swift`
- **Automated by:** none
- **Needs:** a machine whose host key is not yet in the Mac's `~/.ssh/known_hosts`; a key with a passphrase not loaded in the agent

**Steps**

1. Remove the devbox from `~/.ssh/known_hosts` (`ssh-keygen -R devbox`).
2. Run `ambient remote add devbox` in Terminal.
3. Accept the host key with a plain `ssh devbox exit`, unload the key from the agent (`ssh-add -D`), and run `ambient remote add devbox` again.

**Expected**

- Step 2: no host-key question appears; the CLI prints *Couldn't reach the machine: Host key verification failed.* and exits 1, with nothing paired.
- Step 3: no passphrase prompt appears; it fails with *Couldn't reach the machine:* and ssh's last line (e.g. *…Permission denied (publickey).*).
- After `ssh devbox exit` with the key loaded in the agent, pairing succeeds.

**Known gap:** Settings says to run the command in Terminal because "It uses your own ssh, with your config and keys", and `RemotePane` is written so "the user's ssh can ask them anything it needs to", but the default transport sets `BatchMode=yes`, so ssh never asks: a new host key or a key passphrase makes pairing fail. Nothing tells the user to `ssh devbox` once first.

### RMT-008 · A refused sign-in while following shows "Sign-in needed"

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteLink.swift`, `Sources/AmbientApp/RemoteCoordinator.swift`, `Sources/AmbientCore/Remote/RemoteAudit.swift`
- **Automated by:** `RemoteEndToEndTests.aRefusedSignInAsksForIt`, `RemoteIngestTests.signInFailuresAreToldApartFromOutages`
- **Needs:** a paired, connected devbox with a Claude Code session showing

**Steps**

1. On the devbox, remove the Mac's key from `~/.ssh/authorized_keys`, then restart its sshd or kill the link's ssh on the Mac so it reconnects.
2. Watch Settings › Agents › Other Machines and the island for a minute.
3. Separately, after restoring the key: replace the devbox's line in the Mac's `~/.ssh/known_hosts` with another host's key and kill the link's ssh again.
4. Restore everything.

**Expected**

- The row reads *Sign-in needed*, with ssh's last stderr line under it in the warning colour (e.g. *…Permission denied (publickey).*; step 3: *Host key verification failed.*), cut to 160 characters. The dot turns grey.
- The machine's sessions show *Unknown · …* at once, not after the usual 30 seconds.
- It retries about once a minute (not on the fast backoff), and `audit.jsonl` gets one `signInNeeded` record per failed connection.
- Once the key is back, the next retry shows *Connected* and the sessions lose *Unknown*.

### RMT-009 · A machine that reports a different identity stops the link

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteIngest.swift`, `Sources/AmbientCore/Remote/RemoteLink.swift`, `Sources/AmbientCore/Remote/RemoteLine.swift`, `Sources/AmbientApp/Settings/Panes/RemotePane.swift`
- **Automated by:** `RemoteEndToEndTests.aChangedMachineStopsTheLinkUntilApproved`, `RemoteIngestTests.aChangedIdentityStopsTheLink`
- **Needs:** two machines, devbox and devbox-b, both reachable and with Ambient paired once on devbox only

**Steps**

1. Pair devbox and wait for *Connected*.
2. Also pair devbox-b once under another name (`ambient remote add other --host devbox-b`) so it has a shim, then change `HostName` for `Host devbox` in `~/.ssh/config` to devbox-b and accept its host key.
3. Kill the link's ssh so it reconnects.

**Expected**

- The devbox row reads *Stopped: identity changed* with *Expected SHA256:<pinned>, but the machine reports SHA256:<other>. If that's expected, pair it again.* in the warning colour.
- The link does not retry: no new ssh to devbox-b is started after the refusal. devbox's sessions show *Unknown*.
- `audit.jsonl` has a `fingerprintChanged` record for `devbox` whose detail is the new fingerprint and nothing else.

### RMT-010 · Pairing again over a changed identity needs `--accept-new-identity`

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemotePairing.swift`, `Sources/ambient/Commands.swift`, `Resources/ambient-remote`
- **Automated by:** `RemoteEndToEndTests.aDifferentMachineIsLeftAsItWas`, `RemoteEndToEndTests.aDifferentMachineWithNoShimIsLeftAsItWasToo`, `RemoteEndToEndTests.aMachineThatsNeverSeenAmbientIsLeftAsItWas`
- **Needs:** the state RMT-009 leaves: `devbox` now reaching another machine; that machine has never run Ambient

**Steps**

1. Run `ambient remote add devbox`.
2. On the other machine, check `ls -la ~/.ambient` and its agents' config files.
3. Run `ambient remote add devbox --accept-new-identity`.

**Expected**

- Step 1 prints *This machine's identity changed from SHA256:<old> to SHA256:<new>. If that's expected, add it again with --accept-new-identity.* and exits 1.
- Step 2: nothing was copied, installed or created there (the identity is asked by running the shim from stdin, which leaves nothing behind).
- Step 3 pairs it: *Paired devbox…* with the new identity; `audit.jsonl` has `fingerprintChanged` with detail *approved SHA256:<new>* then `paired`. The app restarts the link and it shows *Connected*.

### RMT-011 · Remote sessions show beside local ones with their machine's name

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/RemoteCoordinator.swift`, `Sources/AmbientContracts/RemoteOrigin.swift`, `Sources/AmbientContracts/RemoteEvent.swift`, `Sources/AmbientCore/Remote/RemoteLink.swift`
- **Automated by:** `RemoteEndToEndTests.aLiveStreamReachesTheStoreWithLabelsAndRedaction`
- **Needs:** a paired devbox labelled "Devbox" (`--label Devbox`); a local Claude Code session too

**Steps**

1. On the devbox, in `~/code/api`, start Claude Code and give it a prompt that runs a tool.
2. Look at the island's list, the menu bar menu, and run `ambient status` on the Mac.

**Expected**

- Within about 2 seconds of the agent starting a tool, a row appears with a small network glyph and *Devbox* (VoiceOver: *on Devbox*), next to the local session.
- The menu bar row's detail reads *Claude Code · Devbox · api · …*: the project is the folder's name only, never `~/code/api`.
- `ambient status` shows the session with *on Devbox* before its status.
- At the default level the row shows the tool's name and the session's title, never the prompt's text.

### RMT-012 · A remote agent that needs you blooms and notifies

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientContracts/RemoteEvent.swift`, `Sources/AmbientContracts/RemoteDelivery.swift`, `Sources/AmbientCore/Remote/RemoteIngest.swift`, `Resources/ambient-remote`
- **Automated by:** `RemoteEndToEndTests.aPermissionRequestSaysWhatItNeedsAtTheDefaultLevel`, `RemoteStateTests.alertsWaitForTheSaveAndOnlyWhenThereAreAlerts`
- **Needs:** a paired, connected devbox at the default level; notifications allowed for Ambient

**Steps**

1. On the devbox, ask Claude Code to run `rm -rf build` so it asks permission.
2. In another session there, have the agent ask you a question (an elicitation).

**Expected**

- Within about 2 seconds the island blooms amber and reads *Approve a command*; it chimes like a local prompt.
- The notification's subtitle includes the machine's label (e.g. *Claude Code · Devbox · api*).
- Neither the island, the notification nor `~/.ambient/state.json` contains `rm -rf`: at the standard level the shim sends the tool name (`Bash`) and the reason only.
- The question shows as a question need, not a permission.

### RMT-013 · Ambient never answers a remote prompt

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientContracts/RemoteOrigin.swift`, `Sources/AmbientCore/Permissions.swift`, `Sources/AmbientContracts/RemoteEvent.swift`
- **Automated by:** `PermissionTests.aRemoteSessionCantTouchALocalPrompt`, `RemoteEventDecoderTests.noWireMessageDecodesAsARemoteEvent`
- **Needs:** a paired devbox; answering from the island turned on in Settings

**Steps**

1. With answering from the island on, make the devbox's Claude Code ask permission.
2. Make a local Claude Code session with the same session id ask permission too, if you can (or any local one).

**Expected**

- The remote prompt shows no *Allow once* or *Deny* buttons; it can only be answered on the devbox.
- The local prompt still shows its buttons, and nothing the remote session does (ending, finishing) withdraws the local one.
- The devbox's agent waits until answered on the devbox; Ambient sends nothing to the machine.

### RMT-014 · Clicking a remote session marks it seen and focuses nothing here

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientContracts/RemoteOrigin.swift`, `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `RemoteQuarantineTests.remoteSessionsHaveNoFocusRoutes`, `RemoteQuarantineTests.remoteSessionsAreKeyedByMachineAndNeverHaveAHost`, `RemoteQuarantineTests.sweepNeverChecksARemotePid`
- **Needs:** a paired devbox with a finished (green) session; a local terminal in front

**Steps**

1. Click the remote session's row in the island, then in the menu bar menu.

**Expected**

- The row's done/needs-you state clears as seen; no window, terminal tab, tmux pane or app on the Mac comes forward, and no AppleScript or Accessibility prompt appears.
- No `ssh` command is run for it (check with `ps` during the click): clicking in the island or menu never sends the machine anything.

### RMT-015 · A remote card on the board opens its chat on that machine

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteOpen.swift`, `Sources/AmbientCore/Remote/RemoteTransport.swift`, `Sources/ambient/Commands.swift`
- **Automated by:** `RemoteOpenTests.openSaysWhoAskedAndStillReadsWithoutIt`, `RemoteOpenTests.theAskingMacsNameTravelsEncodedAndArrivesWhole`, `RemoteOpenTests.aRemoteTaskRemembersWhereItsChatOpens`
- **Needs:** a second Mac, "laptop", with Ambient.app running and Remote Login on, paired from this Mac with `ambient remote add laptop`; this Mac's name contains an apostrophe and spaces (e.g. *Advait's Mac Studio*)

**Steps**

1. On the laptop, start a Claude Code session so its card appears on this Mac's board.
2. On this Mac's board, click the card.

**Expected**

- The card's note reads *Opening on laptop…*, then *Opened on laptop* for 5 seconds.
- On the laptop, the chat's terminal or app comes forward and a notification names the asking Mac in full: *Advait's Mac Studio*.
- On this Mac, the remote session is also marked seen. Nothing the laptop printed is shown anywhere.

### RMT-016 · A board open that fails says why, from the exit status only

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteOpen.swift`
- **Automated by:** `RemoteOpenTests.outcomesComeFromTheStatusAndTheCLIsOwnWords`
- **Needs:** a paired devbox with only the shim (no Ambient app); the paired laptop from RMT-015

**Steps**

1. Click a devbox card on the board.
2. Quit Ambient on the laptop and click a laptop card.
3. Disconnect the laptop from the network and click its card.

**Expected**

- Step 1: *devbox has no Ambient app to open it*.
- Step 2: *Ambient isn't running on laptop*.
- Step 3: after up to 20 seconds, *Can't reach laptop*.
- Each note shows for 5 seconds. A card whose chat the machine no longer has reads *laptop no longer has this chat*; any other failure *Couldn't open it on laptop*.

### RMT-017 · A session id from the machine is checked before it reaches a shell

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteOpen.swift`, `Sources/AmbientCore/Remote/RemoteEventDecoder.swift`
- **Automated by:** `RemoteOpenTests.onlyPlainSessionIDsBecomeACommand`, `RemoteOpenTests.theShellPassesItsArgumentsIntact`, `RemoteEventDecoderTests.rejectsMissingAndInvalidRequiredFields`
- **Needs:** a paired devbox where you can append to `~/.ambient/spool/events.jsonl`

**Steps**

1. On the devbox, append a well-formed `sessionStarted` line (next `seq`, a fresh 32-hex `id`, current `ts`) whose `session` is `x;touch$IFS/tmp/pwned`.
2. Append another with `session` `a@b:c` (allowed by the decoder, not by open).
3. On the Mac, click the `a@b:c` card on the board. On the devbox, run `ls /tmp/pwned`.

**Expected**

- The first line never becomes a session: it's rejected as *invalid session* and counted in `audit.jsonl` as `rejected` with detail `invalid`.
- The second shows as a session, but clicking its card says *No chat to open on devbox*, and no ssh runs.
- `/tmp/pwned` doesn't exist.

### RMT-018 · At `metadata`, only states leave the machine

- **Priority:** P0
- **Type:** both
- **Covers:** `Resources/ambient-remote`, `Sources/AmbientCore/Remote/RemoteLine.swift`, `Sources/AmbientCore/Remote/RemoteLink.swift`
- **Automated by:** `RemoteEndToEndTests.redactionLevelsApplyOnTheRemote`
- **Needs:** a devbox

**Steps**

1. Run `ambient remote add devbox --redaction metadata`.
2. On the devbox, run a Claude Code session that uses tools, gets a title, asks permission and finishes.
3. On the devbox, `cat ~/.ambient/spool/events.jsonl`.

**Expected**

- Settings and the menu bar summarise the link as *Connected · shares states only*.
- The spool lines carry only `v`, `seq`, `id`, `ts`, `agent`, `session`, `kind`, `project` (a folder name) and, for prompts, `reason`: no `tool`, `title` or `message` keys.
- On the Mac the rows show states and the project only; the permission prompt shows as a generic permission need with no tool named.

### RMT-019 · At `full`, a message is cut to 160 characters on the machine

- **Priority:** P1
- **Type:** both
- **Covers:** `Resources/ambient-remote`, `Sources/AmbientCore/Remote/RemoteEventDecoder.swift`
- **Automated by:** `RemoteEndToEndTests.textStopsAtItsCapOnTheMachine`, `RemoteEventDecoderTests.cutsFreeTextToItsCap`
- **Needs:** a devbox

**Steps**

1. Pair with `--redaction full`.
2. Ask the devbox's agent for a 500-character final answer that contains `é` near character 160.
3. Read the last `turnCompleted` line of the devbox's spool, and the session's summary on the Mac.

**Expected**

- The link summary reads *Connected · shares short messages*.
- The spool's `message` is at most 160 characters, ends with *…*, and isn't cut inside a character.
- The prompt you typed never appears in the spool, at any level.

### RMT-020 · Tightening the level also covers what was already spooled

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteEventDecoder.swift`, `Sources/AmbientCore/Remote/RemoteIngest.swift`
- **Automated by:** `RemoteEndToEndTests.aTightenedLevelCoversWhatWasAlreadySpooled`, `RemoteIngestTests.nothingAboveTheMachinesLevelGetsThrough`
- **Needs:** a devbox paired at `full`

**Steps**

1. Quit Ambient on the Mac.
2. On the devbox, run a session that finishes with a distinctive final message (e.g. *PINEAPPLE-42*).
3. On the Mac, run `ambient remote add devbox --redaction metadata`, then open Ambient.
4. Run `grep -c PINEAPPLE-42 ~/.ambient/state.json ~/.ambient/tasks.json`.

**Expected**

- The replayed session appears, but with no message, tool name or title.
- `grep` finds nothing on the Mac: lines spooled before the change still cross the transport, and the Mac drops what the new level doesn't allow.

### RMT-021 · Lines that break the format are quarantined and audited without content

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteEventDecoder.swift`, `Sources/AmbientCore/Remote/RemoteLine.swift`, `Sources/AmbientCore/Remote/RemoteIngest.swift`, `Sources/AmbientCore/Remote/RemoteAudit.swift`, `Sources/AmbientCore/Remote/RemoteTransport.swift`
- **Automated by:** `RemoteEndToEndTests.aMalformedSpoolLineIsRejectedAndAudited`, `RemoteEventDecoderTests.rejectsUnknownDuplicateAndNestedFields`, `RemoteEventDecoderTests.rejectsLinesOverSixtyFourKilobytes`, `RemoteEventDecoderTests.randomBytesNeverCrashAndAlmostAlwaysReject`, `RemoteIngestTests.controlLinesHaveTheirOwnAllowlist`
- **Needs:** a paired, connected devbox

**Steps**

1. On the devbox, append to `~/.ambient/spool/events.jsonl`, one at a time: `this line is not json`; a valid-looking event with an extra field `"cmd":"open -a Calculator"`; one with a nested object `"title":{"a":1}`; one with `"type":"focus"`; a 70 KB line.
2. Then make the devbox's agent do something normal.
3. On the Mac, `tail ~/.ambient/remote/audit.jsonl`.

**Expected**

- None of the bad lines shows anything, opens anything or crashes the app; the link stays *Connected*.
- The normal event arrives as usual.
- The audit log has `rejected` records for `devbox` with detail codes only (`notJSON`, `unknownField`, `wrongType`, `invalid`, `tooLong`) and a `count`; never `Calculator` or any other text from the lines. Each kind is written at most once a minute.

### RMT-022 · What a machine sends is shown as plain text

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteEventDecoder.swift`, `Sources/AmbientCore/Remote/RemotePairing.swift`
- **Automated by:** `RemoteEventDecoderTests.rendersRemoteTextAsPlainText`, `RemoteEventDecoderTests.aPileOfCombiningMarksIsCutToo`, `RemoteEndToEndTests.whatAMachineReportsIsPrintedOnlyAsPlainText`
- **Needs:** a paired devbox at `standard` where you can append spool lines

**Steps**

1. Append a `titleChanged` event for an existing session whose `title` is `**bold** [link](https://example.com) \u001b[31mred` followed by 300 combining marks.
2. Look at the row in the island, menu bar and board.

**Expected**

- The title shows literally, no bold, no link, no colour, and is cut to 80 characters; the combining marks don't overflow the row.
- Nothing in it is clickable.

### RMT-023 · The same session id on two machines and locally stays three sessions

- **Priority:** P1
- **Type:** automated
- **Covers:** `Sources/AmbientCore/SessionStore.swift`, `Sources/AmbientContracts/RemoteOrigin.swift`
- **Automated by:** `RemoteQuarantineTests.theSameSessionIdOnTwoMachinesAndLocallyStaysThree`, `RemoteQuarantineTests.remoteEventsAreOrderedBySeqNotByClock`, `RemoteStateTests.tasksNeverMixMachines`
- **Needs:** nothing special

**Steps**

1. Run `swift test --filter RemoteQuarantineTests` on a build machine.

**Expected**

- The tests pass: a remote session is keyed by machine, agent and session id, ordered by `seq` and never merged with a local one or another machine's.

### RMT-024 · A flood only slows its own machine, and sessions are capped

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteIngest.swift`, `Sources/AmbientApp/RemoteCoordinator.swift`, `Sources/AmbientCore/Remote/RemoteAudit.swift`
- **Automated by:** `RemoteEndToEndTests.aFloodIsHeldBackOnlyAsLongAsTheLimitSays`, `RemoteIngestTests.aReplayRunsFreeAndALiveFloodIsHeldBack`, `RemoteIngestTests.aForgedHandshakeDoesntBuyFreePacing`, `RemoteStateTests.aMachineCanOnlyHoldSoManySessions`
- **Needs:** two paired machines; a script on one that appends events quickly

**Steps**

1. On devbox, append 5,000 `toolStarted` events for one session as fast as possible.
2. Meanwhile, make the other machine's agent ask permission.
3. On devbox, append `sessionStarted` events for 1,100 different session ids.

**Expected**

- The other machine's prompt blooms within its usual 2 seconds; the Mac's UI stays responsive.
- devbox's events arrive: the first 500 at once, then about 50 a second; none are dropped (the session ends on the last one).
- At most 1,000 of devbox's sessions exist; `audit.jsonl` gets `rateLimited` and `sessionLimit` records for devbox, each at most once a minute, with counts.

### RMT-025 · A dropped connection reconnects, and its sessions show "Unknown" meanwhile

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteLink.swift`, `Sources/AmbientApp/RemoteCoordinator.swift`, `Sources/AmbientContracts/RemoteOrigin.swift`
- **Automated by:** `RemoteEndToEndTests.anUnreachableMachineRetriesWithoutAFuss`, `RemoteStateTests.anUnreachableMachinesSessionsAreUnknownNotWorking`, `RemoteStateTests.aNewEventMeansTheMachineIsBack`, `RemoteIngestTests.backoffGrowsToItsLimitWithJitter`
- **Needs:** a paired devbox with a working Claude Code session

**Steps**

1. Block the devbox (stop its sshd, or pull its network) so the link drops.
2. Watch the menu bar's machine row and the session row for two minutes.
3. Bring the devbox back.

**Expected**

- The machine row reads *devbox · Reconnecting · shares tool names and titles* with a grey dot. Retries come after about 1, 2, 4, 8… seconds (±20%), never more than 60 seconds apart.
- For the first 30 seconds the session keeps its last state; after that it reads *Unknown · <its last state>*, not *working* forever, and stays that way however long the outage lasts.
- Within one retry of the devbox returning, the row reads *Connected* and the session drops *Unknown*.
- `audit.jsonl` has `linkDown` and then `linkUp` (with the shim version as detail).

### RMT-026 · A silent dead connection is noticed within 45 seconds

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Remote/RemoteLink.swift`, `Sources/AmbientCore/Remote/Machine.swift`, `Resources/ambient-remote`
- **Automated by:** none
- **Needs:** a devbox in a VM you can pause (so TCP doesn't close)

**Steps**

1. With the link *Connected*, pause the VM.
2. Time how long until the machine row changes.

**Expected**

- Heartbeats normally arrive every 15 seconds. Within 45 seconds of the pause (or ssh's own 15 s × 3 keep-alive, whichever first) the row reads *Reconnecting*.

### RMT-027 · Events from while the Mac was away arrive once, none lost

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteIngest.swift`, `Sources/AmbientContracts/RemoteDelivery.swift`, `Sources/AmbientCore/SessionStore.swift`, `Resources/ambient-remote`
- **Automated by:** `RemoteEndToEndTests.killingTheHubLosesAndDuplicatesNoAlerts`, `RemoteEndToEndTests.aLinkWaitsForEachBatchToBeApplied`, `RemoteIngestTests.deduplicatesBySeqAndByEventID`, `RemoteIngestTests.aFullSpoolReplaysWithoutWaiting`
- **Needs:** a paired devbox

**Steps**

1. Quit Ambient on the Mac (or `kill -9` it right after a remote prompt arrives).
2. On the devbox, run a session that finishes and then asks permission, within 5 minutes.
3. Reopen Ambient.

**Expected**

- The session shows its latest state as soon as the link connects; a backlog of a full 5 MB spool arrives at once rather than 50 a second.
- The permission prompt blooms and chimes exactly once: not lost, not repeated, even after the `kill -9`.
- `ambient remote list` shows the cursor at the spool's newest `seq`.

### RMT-028 · A prompt replayed more than 10 minutes late shows "Missed" without a chime

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteIngest.swift`, `Sources/AmbientContracts/RemoteDelivery.swift`, `Sources/AmbientContracts/RemoteOrigin.swift`
- **Automated by:** `RemoteEndToEndTests.aReplayedPromptFromLongAgoIsMissedWithoutAChime`, `RemoteStateTests.aMissedPromptShowsButNeverAlerts`, `RemoteStateTests.aMissedPromptStaysUntilSeenThenSettles`, `RemoteIngestTests.oldReplayedAlertsAreMissedAndFreshOnesAreNot`
- **Needs:** a paired devbox

**Steps**

1. Quit Ambient on the Mac.
2. On the devbox, make the agent ask permission and leave it waiting 11 minutes.
3. Reopen Ambient.

**Expected**

- The session reads *Missed · Approve a command*; the island doesn't bloom, there's no chime and no notification.
- Clicking it marks it seen and it settles to idle. A fresh event from that session clears *Missed*.

### RMT-029 · An agent killed on the machine ends its session

- **Priority:** P1
- **Type:** both
- **Covers:** `Resources/ambient-remote`, `Sources/AmbientContracts/RemoteEvent.swift`
- **Automated by:** `RemoteEndToEndTests.followReportsWhenTheAgentExits`, `RemoteQuarantineTests.agentExitEndsTheSession`
- **Needs:** a paired devbox

**Steps**

1. On the devbox, start Claude Code and let it run a tool.
2. `kill -9` the Claude Code process there.

**Expected**

- Within about 5 seconds (follow checks live agents every 5 s), the session ends on the Mac as if it had said `SessionEnd`.
- The agent's pid never appears in anything on the Mac (`grep` `state.json` for it).

### RMT-030 · A shim speaking another protocol asks for an update

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteIngest.swift`, `Sources/AmbientCore/Remote/RemoteLink.swift`, `Sources/AmbientContracts/RemoteEvent.swift`
- **Automated by:** `RemoteEndToEndTests.aShimThatCantBeUnderstoodAsksForAnUpdate`, `RemoteIngestTests.aDifferentProtocolAsksForAnUpgrade`, `RemoteEventDecoderTests.acceptsOnlyTheCurrentAndPreviousVersion`
- **Needs:** a paired devbox where you can edit `~/.ambient/bin/ambient-remote`

**Steps**

1. On the devbox, change `AR_PROTO=1` to `AR_PROTO=3` in the installed shim, and kill the link's ssh so it reconnects.
2. Run `ambient remote add devbox` on the Mac.

**Expected**

- The row reads *Update needed* with *This machine's ambient-remote speaks protocol 3. Run `ambient remote add devbox` to update it.*; it doesn't retry; its sessions show *Unknown*; `audit.jsonl` has `upgradeNeeded` with detail *proto 3*.
- Re-pairing replaces the shim and the link comes back *Connected*.

### RMT-031 · A newer shim in the app shows "update available"

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Remote/RemoteLink.swift`, `Sources/AmbientApp/RemoteCoordinator.swift`, `Sources/AmbientApp/Settings/Panes/RemotePane.swift`
- **Automated by:** none
- **Needs:** a devbox paired by an older Ambient release (shim version below the app's 1.0.7)

**Steps**

1. Update Ambient.app on the Mac, open it, and open Settings › Agents › Other Machines.

**Expected**

- The summary reads *Connected · shares tool names and titles · update available*, and under it, selectable: *This version of Ambient has a newer link. Run `ambient remote add devbox` to update it.*
- After running that, the hint goes away.

### RMT-032 · Settings › Other Machines shows each link and how to add one

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/RemotePane.swift`, `Sources/AmbientCore/Remote/RemoteLink.swift`
- **Automated by:** none
- **Needs:** one paired machine, then none

**Steps**

1. With no machines paired, open Settings › Agents › Other Machines.
2. Click **Copy** beside `ambient remote add NAME`, and open *What it does*.
3. Pair a machine and look again; open the row's disclosure; open the menu bar menu.

**Expected**

- With none: *No machines paired yet.*
- **Copy** puts `ambient remote add NAME` on the clipboard and reads *Copied* for 1.5 seconds. The footer reads *Run it in Terminal. It uses your own ssh, with your config and keys.*
- A paired machine shows its label, a green dot when *Connected* (grey otherwise), and *Connected · shares tool names and titles*; the disclosure shows the transport and the fingerprint in monospace, selectable. Its **…** menu offers *Unpair* and *Unpair and Delete Everything…*.
- The menu bar menu has a row *devbox · Connected · shares tool names and titles* that opens Settings.

### RMT-033 · Unpairing from Settings stops the link and drops its sessions

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/RemoteCoordinator.swift`, `Sources/AmbientApp/Settings/Panes/RemotePane.swift`, `Sources/AmbientCore/Remote/RemoteFiles.swift`
- **Automated by:** `RemoteStateTests.unpairingForgetsOnlyThatMachine`
- **Needs:** two paired machines with sessions showing

**Steps**

1. In Settings › Other Machines, choose **…** › *Unpair* on devbox.
2. Run `ps ax | grep 'ambient-remote.*follow'` on the Mac and `ambient remote list`.

**Expected**

- devbox's row and all its sessions disappear at once; the other machine's stay.
- Its ssh process is gone within about 2 seconds; `machines.json` no longer lists it; `audit.jsonl` has `unpaired`.
- Its hooks and spool are still on devbox (unpairing doesn't touch the machine).

### RMT-034 · `remove --uninstall` clears the machine, but only if it's still that machine

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Remote/RemotePairing.swift`, `Resources/ambient-remote`
- **Automated by:** `RemoteEndToEndTests.uninstallingChecksItsMachineFirst`
- **Needs:** a paired devbox; a second machine for the second half

**Steps**

1. Run `ambient remote remove devbox --uninstall`.
2. On the devbox: `ls -la ~/.ambient`, `grep -c ambient-remote ~/.claude/settings.json`.
3. Pair it again, re-point `devbox` in `~/.ssh/config` at another paired machine, and run `ambient remote remove devbox --uninstall`.

**Expected**

- Step 1 prints *Removed the hooks, spool and shim from devbox* and *Removed devbox. Its sessions and cursor are gone from this Mac.*, exit 0. Within 5 seconds the app drops its row and sessions.
- Step 2: `spool/`, `remote.conf`, `remote.id` and `bin/ambient-remote` are gone, no hooks mention `ambient-remote`, and the previous config is kept in `~/.ambient/backups/`.
- Step 3 prints *devbox's transport reaches another machine (SHA256:…), so that one was left alone. Unpairing it anyway.*, exits 1, and the other machine's shim, spool and hooks are untouched.
- Without `python3` on the machine: *Removed the spool and shim from devbox. It has no python3, so its hooks stay in the agent's config for you to remove by hand. They do nothing now.*

### RMT-035 · `ambient remote purge` deletes everything from a machine on this Mac

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Remote/RemotePairing.swift`, `Sources/AmbientApp/RemoteCoordinator.swift`
- **Automated by:** `RemoteEndToEndTests.removingAndPurgingLeaveNothingBehind`
- **Needs:** a paired devbox whose sessions are on the board and in today's moments, with a distinctive project name

**Steps**

1. With Ambient running, run `ambient remote purge devbox`.
2. Within 10 seconds, `grep -c <project> ~/.ambient/state.json ~/.ambient/tasks.json ~/.ambient/day*.json`.

**Expected**

- It prints *Deleted everything from devbox on this Mac: sessions, cursor, board tasks and today's moments.* and *The audit log keeps that it happened, and holds no event content.*
- Within 5 seconds the running app drops devbox's sessions, board cards and moments too (it picks up the marker in `~/.ambient/remote/purged/` and clears it).
- `grep` finds nothing; `audit.jsonl` has `purged` for devbox and no project text.

### RMT-036 · "Unpair and Delete Everything…" asks first, then purges

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/AmbientApp/Settings/Panes/RemotePane.swift`, `Sources/AmbientApp/RemoteCoordinator.swift`
- **Automated by:** none
- **Needs:** a paired machine labelled "Build box" with sessions and board cards

**Steps**

1. In Settings › Other Machines, choose **…** › *Unpair and Delete Everything…*.
2. Dismiss the dialog once; then do it again and choose **Unpair and Delete**.

**Expected**

- The dialog is titled *Delete everything from Build box?* with *Its sessions, cursor, board tasks and today's moments go from this Mac. Its hooks stay on the machine until you run `ambient remote remove --uninstall` first.*
- Dismissing changes nothing. Confirming removes the row, its sessions, cards and moments; `audit.jsonl` has `unpaired` then `purged`.

### RMT-037 · No server, no listening port, and nothing sent to the machine

- **Priority:** P0
- **Type:** manual
- **Covers:** `Sources/AmbientCore/Remote/RemoteLink.swift`, `Sources/AmbientCore/Remote/RemoteTransport.swift`, `Sources/AmbientApp/RemoteCoordinator.swift`, `Resources/ambient-remote`
- **Automated by:** none
- **Needs:** a paired, connected devbox; a network monitor on the Mac (e.g. Little Snitch or `nettop`)

**Steps**

1. With the link connected and sessions streaming for five minutes, run `lsof -nP -iTCP -sTCP:LISTEN` and `lsof -nP -iUDP` on the Mac, and `ss -ltnp` (or `lsof`) on the devbox.
2. Watch the Mac's outbound connections.
3. On the Mac, `lsof -p <the link's ssh pid>` and check its stdin.

**Expected**

- Ambient and `ambient-remote` listen on no TCP or UDP port on either side; there's no daemon on the devbox besides the `follow` process while connected.
- The only outbound connection for the link is the user's own `ssh` to the devbox; Ambient itself contacts no other host (no Ambient-run server, relay or account).
- The link's ssh has `/dev/null` as stdin: the Mac sends nothing but the command line.

### RMT-038 · Remote text stays on this Mac: the local LLM only by opt-in, only on loopback

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteEgress.swift`, `Sources/AmbientBase/Loopback.swift`, `Sources/AmbientApp/Settings/Panes/RemotePane.swift`
- **Automated by:** `RemoteStateTests.remoteTextNeverLeavesTheMac`, `RemoteStateTests.whatAModelSaysAboutARemoteSessionIsPlainTextToo`, `TaskLLMConfigTests.acceptsOnlyLoopbackMCPHosts`
- **Needs:** a paired devbox at `full`; board summaries with a local LLM turned on

**Steps**

1. In Settings › Other Machines, check *Summarize remote sessions with the local LLM* is off (the default), and let a remote session finish.
2. Turn it on and let another finish.
3. Point the board's LLM endpoint at a non-loopback address (e.g. `http://192.168.1.10:5051/mcp`), keep the toggle on, and let a third finish.

**Expected**

- Step 1: the remote card gets no model summary, while local cards do. The section's footer reads *Text from other machines stays on this Mac. It never reaches online voices or any address but this Mac's own.*
- Step 2: the remote card is summarised; `audit.jsonl` has `policyChanged` with detail `remoteSummaries=on` (machine `*`).
- Step 3: no remote session is sent to the non-loopback endpoint (watch with a network monitor); only `127.0.0.1`, `localhost` or `::1` over http(s) ever receives remote text.

### RMT-039 · The audit log records what happened, never what was said

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemoteAudit.swift`, `Sources/AmbientCore/Remote/RemoteFiles.swift`
- **Automated by:** `RemoteEventDecoderTests.rejectionCodesCarryNoContent`, `RemoteEventDecoderTests.aMachinesOwnKeysAreNeverPrintedAsTheyCame`, `RemoteIngestTests.rejectionsAreCountedWithoutContentAndCannotFillTheLog`, `RemoteIngestTests.gapsAndResetsCantFillTheLog`
- **Needs:** a devbox paired at `full`

**Steps**

1. Run a remote session whose title, project and final message all contain `PINEAPPLE-42`, plus one malformed spool line containing it.
2. Pair, drop and restore the link once.
3. `grep -c PINEAPPLE ~/.ambient/remote/audit.jsonl`; `ls -l ~/.ambient/remote/`.

**Expected**

- `grep` prints 0. Records hold only `ts`, `action`, `machine`, and a short code, fingerprint or shim version as `detail`, with a `count` where throttled.
- `audit.jsonl` is `-rw-------`. Past 5 MB it moves to `audit.1.jsonl`, replacing the one before.

### RMT-040 · The spool on the machine is private and capped

- **Priority:** P1
- **Type:** manual
- **Covers:** `Resources/ambient-remote`, `scripts/test-remote-shim.py`
- **Automated by:** none
- **Needs:** a paired devbox; on Linux, `dash`, `bash`, `busybox`, `mawk` and `gawk` for the script

**Steps**

1. On the devbox, `ls -ld ~/.ambient ~/.ambient/spool` and `ls -l ~/.ambient/spool`.
2. Set `spool_max_bytes=20000` in `~/.ambient/remote.conf` and drive 500 hook events with the Mac disconnected; `wc -c ~/.ambient/spool/events*.jsonl`.
3. Set `spool_max_age=60`, wait two minutes, emit one event, then reconnect the Mac.
4. In a checkout on Linux, run `REQUIRE_ALL=1 scripts/test-remote-shim.sh`.

**Expected**

- Folders are `drwx------`, spool files `-rw-------`.
- The two spool files together stay at about 20,000 bytes or under: `events.jsonl` moves to `events.1.jsonl` once it passes half the cap.
- Events older than the age limit are not streamed after reconnecting, and the cursor gap is recorded as `spoolGap` in the Mac's audit log.
- The script passes under every shell and awk, checking with a strict JSON parser that every spool line, the `status` and the `follow` stream are valid.

### RMT-041 · A remote hook never fails or slows the agent

- **Priority:** P1
- **Type:** both
- **Covers:** `Resources/ambient-remote`
- **Automated by:** `RemoteEndToEndTests.theHookStaysWithinItsLatencyBudget`, `RemoteEndToEndTests.aFailingSpoolNeverFailsTheHook`
- **Needs:** a paired devbox

**Steps**

1. On the devbox, `chmod 000 ~/.ambient/spool` and use Claude Code normally for a few turns.
2. Restore `chmod 700` and use it again.

**Expected**

- With the spool unwritable, Claude Code shows no hook errors and isn't slowed; nothing reaches the Mac.
- After restoring, events flow again with no restart.

### RMT-042 · `ambient doctor --remote` checks each part of the link

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Remote/RemotePairing.swift`, `Sources/ambient/Commands.swift`
- **Automated by:** `RemoteEndToEndTests.doctorSeesEachPartOfTheLink`
- **Needs:** a paired devbox with Claude Code but not Codex

**Steps**

1. Run `ambient doctor --remote devbox`.
2. On the devbox, `chmod 755 ~/.ambient/spool`, and run it again.
3. Run `ambient doctor --remote nosuch`.

**Expected**

- Step 1 lists, with ✓: *Transport reaches devbox*, *Shim version 1.0.7*, *Shim checksum matches the app's*, *Identity matches the pinned SHA256:…*, *Spool is private: <size>, level standard*, *Claude Code: hooks installed*, *Codex: not on this machine*, and *Cursor is up to date at N* (or a warning *Cursor is N events behind*). It ends *Nothing is stopping this machine.* and exits 0.
- Step 2 fails *Spool permissions are too open. They should be 0700 for folders and 0600 for files.*, ends *1 problem found.* and exits 1.
- Step 3 prints *No paired machine is called 'nosuch'. Try `ambient remote list`.*

### RMT-043 · Without python3 on the machine, pairing prints the hooks to add by hand

- **Priority:** P2
- **Type:** manual
- **Covers:** `Resources/ambient-remote`, `Sources/AmbientCore/Remote/RemotePairing.swift`
- **Automated by:** none
- **Needs:** a devbox without `python3`, with an existing `~/.claude/settings.json`

**Steps**

1. Run `ambient remote add devbox`.

**Expected**

- The install lines include *manual claude: python3 isn't available, so …/.claude/settings.json can't be edited safely.*, *Add these hooks to it by hand:* and a JSON snippet with 14 hook events.
- The CLI still pairs (*Paired devbox…*) and warns *One agent's hooks need adding by hand; see above.*
- `settings.json` is unchanged. With no `settings.json` at all, the shim writes the hooks itself.
