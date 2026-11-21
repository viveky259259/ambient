# Events

Id prefix: `EVT-`. The event pipeline from an agent's hook to a session's state: `ambient hook <agent>` and
`ambient emit`, the per-agent adapters, trimming, the Unix socket and wire format, the session reducer and its
timeouts, session titles, the saved state file, and what is and isn't kept on disk.

Most cases read the result two ways: on the island (or menu bar) and in `ambient status`, whose rows print
`● <agent> <title> <status>  <clock>` with the same text as the island (`Describe.status`). Run commands as
`~/.ambient/bin/ambient`, or add `~/.ambient/bin` to `PATH`. Unless a case says otherwise, Ambient is running and
the agent named is connected (Settings › Agents or `ambient install <agent>`), and sessions were started after it was.

## Claude Code

### EVT-001 · A Claude Code turn shows as working, with the tool and its hint

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/Adapters/ToolDetail.swift`, `Sources/AmbientContracts/ToolNames.swift`, `Sources/AmbientContracts/Describe.swift`, `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `ClaudeAdapterTests.bashToolDetailIsTheCommand`, `ClaudeAdapterTests.fileToolDetailIsTheBasename`, `ClaudeAdapterTests.webFetchDetailIsTheHost`, `ClaudeAdapterTests.mcpToolHasNoDetail`, `ToolNameTests.displayNames`, `SessionStoreTests.aFullTurnEndsDone`
- **Needs:** Claude Code connected

**Steps**

1. In a project folder `api`, start `claude` and send a prompt that makes it run `sleep 15 && echo ok`.
2. While it runs, run `ambient status`.
3. Ask it to read `Sources/Session.swift`, then to fetch `https://example.com/docs`, then to call any MCP tool (e.g. `mcp__github__create_pr`).

**Expected**

- Within a second of sending the prompt the row reads *Thinking*; the island's orb breathes in Claude coral (`#D97757`).
- During the command, `ambient status` shows `claude  api  Bash · sleep 15 && echo ok  <n>s`, the clock counting from the prompt.
- The read shows *Read · Session.swift* (the file name only, never the path), the fetch *WebFetch · example.com* (the host only), the MCP tool *github · create_pr* with no hint after it.
- After each tool finishes the row returns to *Thinking* until the next one.

### EVT-002 · A Claude Code permission prompt for a command needs you, naming the command

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientContracts/Need.swift`, `Sources/AmbientContracts/Describe.swift`, `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `ClaudeAdapterTests.permissionRequestNeedsInput`, `WaitingReasonTests.claudesPermissionRequests`, `NeedTests.toolsDecideTheNeed`, `DescribeTests.everyWaitHasAOneLineReason`
- **Needs:** Claude Code connected, in default permission mode; Settings › Alerts › Permission prompts off

**Steps**

1. Ask Claude Code to run `rm -rf build` so it asks permission. Don't answer.
2. Look at the island and run `ambient status`.

**Expected**

- The island blooms amber (`#F5A524`) and reads *Approve a command · rm -rf build*; the collapsed island and menu bar say *Approve command*.
- `ambient status` prints `Ambient · 1 session · needs you` and the row `Approve a command · rm -rf build`, its clock counting from when the prompt appeared.
- Claude Code's own prompt is still on screen and waiting: Ambient answered nothing.

### EVT-003 · Each kind of Claude Code prompt says what it needs

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientContracts/Need.swift`, `Sources/AmbientContracts/ToolNames.swift`
- **Automated by:** `WaitingReasonTests.claudesPermissionRequests`, `WaitingReasonTests.notificationsNamingATool`, `NeedTests.toolsDecideTheNeed`
- **Needs:** Claude Code connected, in default permission mode

**Steps**

1. Make Claude Code ask, one at a time, to: edit `Session.swift`; fetch `https://example.com/x`; read a file outside the project; leave plan mode with a plan whose first line is `# Add caching`; use an MCP tool such as `mcp__github__create_pr`; and ask you a question with AskUserQuestion (two questions in one call).
2. Read the island each time before answering.

**Expected**

- *Review a change · Session.swift*
- *Allow web access · example.com*
- *Approve a tool · Read: <file name>* (Claude asks by tool, so a read outside the project is a tool approval; *Allow access outside the project* comes only from OpenCode)
- *Review a plan · Add caching* (the plan's first line, heading marks removed)
- *Approve a tool · github · create_pr*
- *Answer a question · <first question> (+1 more)*

### EVT-004 · Claude's follow-up notification doesn't replace a more precise prompt

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/SessionStore.swift`, `Sources/AmbientContracts/Need.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`
- **Automated by:** `WaitingStateTests.aPromptThatSaysLessDoesntReplaceOneThatSaysMore`, `WaitingStateTests.aPromptWithNewDetailReplacesTheOneOnShow`, `SessionStoreTests.theSecondEventForTheSamePromptDoesNotAskAgain`, `ClaudeAdapterTests.permissionNotificationNeedsInput`
- **Needs:** Claude Code connected; notifications and sounds on

**Steps**

1. Leave another app in front, ask Claude Code to run `rm -rf build`, and wait 10 seconds without answering (Claude sends its `permission_prompt` notification, *Claude needs your permission to use Bash*, a few seconds after the PermissionRequest hook).

**Expected**

- The island keeps reading *Approve a command · rm -rf build*; it never changes to the bare *Approve a command*.
- One banner and one chime only: the notification doesn't alert a second time.

### EVT-005 · A finished Claude Code turn is done, with a trimmed summary

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/SessionStore.swift`, `Sources/AmbientContracts/Describe.swift`, `Sources/AmbientContracts/Session.swift`
- **Automated by:** `ClaudeAdapterTests.stopCompletesTurnWithSummary`, `ClaudeAdapterTests.idlePromptChangesNothing`, `SessionStoreTests.aFullTurnEndsDone`, `DescribeTests.clockSaysWhatTheTimeMeansForEachState`
- **Needs:** Claude Code connected

**Steps**

1. Give Claude Code a task that takes about 30 seconds and ends with a long reply.
2. Run `ambient status` right after it stops, and again a minute later without looking at its terminal.
3. Leave it idle for over a minute (Claude sends an `idle_prompt` notification).

**Expected**

- The row turns green (`#3FB950`) and reads *Done · <the start of Claude's last message>*, at most 160 characters, ending in `…` when cut, with newlines turned into single spaces.
- The clock reads *just now* for the first 10 seconds, then *<n>s ago* / *<n>m ago*.
- The idle reminder changes nothing: still *Done*, no new alert.

### EVT-006 · A failed Claude Code turn is an error, with its message

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/SessionStore.swift`, `Sources/AmbientContracts/Describe.swift`
- **Automated by:** `ClaudeAdapterTests.stopFailureFailsTurn`
- **Needs:** Ambient running

**Steps**

1. Run `echo '{"session_id":"evt6","hook_event_name":"StopFailure","cwd":"/tmp/api","error_message":"API Error: 529 overloaded"}' | ambient hook claude`.
2. Run `ambient status`. Optionally reproduce for real by running Claude Code with networking cut mid-turn.

**Expected**

- The row reads *Failed · API Error: 529 overloaded* in red (`#F85149`), and the header says `failed`.
- With no `error_message`, the message falls back to `error`, then `error_type`; with none of them, just *Failed*.

### EVT-007 · Compaction shows, then returns to what it interrupted

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `SessionStoreTests.compactionReturnsToWhatWasBefore`, `ClaudeAdapterTests.sessionStartAfterCompactFinishesCompaction`, `ClaudeAdapterTests.compactionAndSubagents`
- **Needs:** Claude Code connected

**Steps**

1. After a turn has finished (row *Done*), run `/compact` in Claude Code.
2. Watch the row during and after compaction.
3. Repeat in a long turn that compacts automatically mid-work.

**Expected**

- During compaction the row reads *Compacting context* (*Compacting* when collapsed) and counts as working.
- After a manual compact of a finished session, it returns to *Done · …*, not to *Thinking*.
- After an automatic compact mid-turn (PostCompact, or SessionStart with `source: compact`), it returns to *Thinking*.

### EVT-008 · Subagents are counted and reset when the turn ends

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/SessionStore.swift`, `Sources/AmbientContracts/Session.swift`
- **Automated by:** `SessionStoreTests.subagentCountNeverGoesNegative`, `ClaudeAdapterTests.compactionAndSubagents`, `CursorAdapterTests`, `CopilotAdapterTests.lifecycle`
- **Needs:** Claude Code connected

**Steps**

1. Ask Claude Code to run two Task subagents in parallel.
2. While they run, run `ambient status --json` and read the session's `subagents`.
3. After the turn stops, read it again. Then send two `SubagentStop` payloads by hand for a session with none running.

**Expected**

- `subagents` is 2 while both run, then 1, then 0 as they finish.
- It is 0 once the turn is done, even if a stop was missed.
- Extra stops leave it at 0, never negative.

## Codex

### EVT-009 · Codex reports working, needs-you and done like Claude Code

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/Adapters/ToolDetail.swift`, `Sources/AmbientContracts/ToolNames.swift`
- **Automated by:** `CodexAdapterTests.codexUsesClaudeCompatibleNames`, `CodexAdapterTests.applyPatchDetailIsFirstFile`, `CodexAdapterTests.realTurnKeepsItsSummary`, `WaitingReasonTests.codexPatches`
- **Needs:** Codex connected and its hooks approved with `/hooks`

**Steps**

1. In Codex, ask for a change that edits three files with `apply_patch`, then runs `make test`, in a mode where it asks before writing.
2. Read the island while it works, while it asks and after it stops.

**Expected**

- The row shows *Thinking*, then *Shell · make test* (Codex's `exec_command`/`shell` show as *Shell*), in Codex green (`#10A37F`).
- The patch shows as *Patch · a.swift +2 more* (first file's name, then how many more); asking to apply it reads *Review a change · a.swift +2 more*.
- When the turn ends: *Done · <start of Codex's last message>*.

### EVT-010 · Codex app's hidden suggestion threads never show as sessions

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`
- **Automated by:** `CodexAdapterTests.suggestionThreadIsIgnored`, `CodexAdapterTests.suggestionThreadEndStillClearsItsRow`, `CodexAdapterTests.endOfAnUnseenSuggestionThreadLeavesNoRowOrTask`, `CodexAdapterTests.forksPeopleMakeAreKept`, `CodexAdapterTests.ephemeralExecRunsAreKept`, `CodexAdapterTests.suggestionTurnsAddNoRows`
- **Needs:** Codex desktop app connected; Codex CLI

**Steps**

1. In the Codex app, finish a turn so it generates next-prompt suggestions.
2. Run `ambient status`. Then fork a thread in the app, and run `codex exec --ephemeral "echo hi"` in a terminal.

**Expected**

- Only the thread you worked in is listed; no extra row appears for the suggestion run (null `transcript_path` under `codex app-server`), and no row lingers when Codex ends it later.
- The fork and the `codex exec --ephemeral` run each show as their own session.

## Gemini CLI and Antigravity

### EVT-011 · Gemini CLI reports its turn and says what its confirmation needs

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientContracts/ToolNames.swift`
- **Automated by:** `GeminiAdapterTests.agentLifecycle`, `GeminiAdapterTests.tools`, `GeminiAdapterTests.toolPermissionNotificationNeedsInput`, `GeminiAdapterTests.compressAndSession`, `WaitingReasonTests.geminiDescribesItsConfirmation`
- **Needs:** Gemini CLI connected, in default approval mode

**Steps**

1. Ask Gemini CLI to run `ls -la`, then to edit `README.md`, then to fetch `https://example.com`, then to call an MCP tool.
2. Read the island at each confirmation, and after the turn.

**Expected**

- Working rows use Ambient's short names in Gemini blue (`#4F8DF7`): `run_shell_command` reads *Shell · ls -la*, `read_file` *Read*, `replace` *Edit*, `google_web_search` *Search*.
- Confirmations read *Approve a command · ls -la*, *Review a change · README.md*, *Allow web access · example.com*, *Approve a tool · <server> · <tool>*.
- After the turn: *Done · <start of Gemini's response>* (from `prompt_response`, at most 160 characters).

**Known gap:** The README says Ambient sees "everything" from Gemini CLI, but the Gemini adapter maps no failure or subagent event: a turn that fails ends as *Done* (AfterAgent) or stays working until the 10-minute busy timeout; it never shows *Failed*.

### EVT-012 · Gemini CLI always gets valid JSON back from the hook

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`
- **Automated by:** `AntigravityAdapterTests.repliesWithADecisionWhereOneIsRequired`
- **Needs:** nothing special (Ambient may be running or not)

**Steps**

1. Run `echo '{"session_id":"g1","hook_event_name":"BeforeTool","tool_name":"run_shell_command"}' | ambient hook gemini; echo "exit $?"`.
2. Repeat with `echo 'not json' |`, with an empty stdin (`</dev/null`), and with Ambient quit.

**Expected**

- Every run prints exactly `{}` and a newline, then `exit 0`: Gemini parses the hook's stdout as JSON and never sees an error from Ambient.

### EVT-013 · Antigravity reports prompts, tools and finished or failed turns

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientContracts/ToolNames.swift`
- **Automated by:** `AntigravityAdapterTests.sessionIsTheConversationAndProjectTheFirstWorkspace`, `AntigravityAdapterTests.onlyTheFirstModelCallOfATurnIsAPrompt`, `AntigravityAdapterTests.tools`, `AntigravityAdapterTests.stop`, `AntigravityAdapterTests.realAgyPayloads`, `AntigravityAdapterTests.withoutAConversationThereIsNoEvent`
- **Needs:** Antigravity (`agy`) connected

**Steps**

1. In a workspace folder `web`, give `agy` a task that runs `npm test` and edits a file.
2. Watch the row during the turn and after it stops. Then run a task that hits the step limit.

**Expected**

- The session is named after the conversation and its project is the first workspace folder, `web`; color purple (`#A371F7`).
- *Thinking* once per turn (only the first model call, `invocationNum` 0, counts as a prompt), then *Shell · npm test*, *Edit · <file>* (`run_command`, `replace_file_content`).
- A normal stop reads *Done* with no summary; `terminationReason` `error` reads *Failed · <error>*; the step limit reads *Failed · Reached its step limit*.
- It never shows *needs you*: Antigravity has no permission event.

### EVT-014 · Antigravity's required decision defers to its own permission rules

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`
- **Automated by:** `AntigravityAdapterTests.repliesWithADecisionWhereOneIsRequired`
- **Needs:** Antigravity (`agy`) connected, with a rule that asks before running commands

**Steps**

1. Run `echo '{}' | ambient hook antigravity PreToolUse`, then the same with `Stop` and `PostToolUse`.
2. In `agy`, ask for a command its rules say to confirm.

**Expected**

- `PreToolUse` and `Stop` print `{"decision":"allow"}`; every other event prints `{}`. Exit code 0 each time.
- `agy` still shows its own confirmation for the command: Ambient's "allow" defers to Antigravity's rules and never approves anything they would ask about.

## Cursor, Copilot CLI, OpenCode

### EVT-015 · Cursor shows tools as they finish and how the turn ended

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientContracts/Session.swift`
- **Automated by:** `CursorAdapterTests.sessionIsTheConversationAndProjectTheFirstWorkspaceRoot`, `CursorAdapterTests.toolsShowAsWorkingWhenTheyFinish`, `CursorAdapterTests.stopAndSession`, `CursorAdapterTests.payloadAgentFieldDoesNotRelabelCursorAsCodex`, `SessionStoreTests.cursorLabelStaysCursorEvenIfEventCarriesCodexName`, `EventTests.hookedAgentLabelsNeverInheritAForeignAgentName`
- **Needs:** Cursor connected; Cursor's agent with a Codex or GPT model selected

**Steps**

1. In a Cursor window on folder `site`, ask the agent to edit `index.html` and run `npm run build`.
2. Watch the island during and after the turn.

**Expected**

- The session's project is the first workspace root, `site`, and the agent label is *Cursor* in cyan (`#39C5CF`), never *Codex*, whatever model is chosen.
- The edit shows only after it's made, as *Edit · index.html*; the shell command after it ran, named by its command (*npm run build*) or by Cursor's tool name.
- A stop with `status: error` reads *Failed* (no message); any other stop reads *Done*. Cursor's own permission prompts never reach Ambient.

### EVT-016 · Cursor's hooks never print a reply, so they can never approve anything

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`
- **Automated by:** `CursorAdapterTests.neverRepliesSoItNeverDecidesAnything`
- **Needs:** nothing special

**Steps**

1. Run `echo '{"conversation_id":"c1","hook_event_name":"postToolUse","tool_name":"Shell"}' | ambient hook cursor | wc -c`, with Ambient running and again with it quit.
2. Do the same for `claude`, `codex`, `copilot`, `opencode` and `custom` payloads.

**Expected**

- `0` bytes every time: only Gemini (`{}`) and Antigravity (`{}` or `{"decision":"allow"}`) ever get stdout, and only with the permission hook on do Claude Code and Codex get an answer the user chose (see the permissions area).

### EVT-017 · Copilot CLI reports prompts, tools, needs-you and errors

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/Adapters/HookPayload.swift`
- **Automated by:** `CopilotAdapterTests.toolArgsMayBeAJSONString`, `CopilotAdapterTests.lifecycle`, `CopilotAdapterTests.permissionPromptsNeedYouAndIdleRemindersDont`, `CopilotAdapterTests.onlyUnrecoverableErrorsFailTheTurn`
- **Needs:** GitHub Copilot CLI connected (beta)

**Steps**

1. Ask Copilot CLI to run `git status`, then to run a command it must ask about.
2. Feed a recoverable error: `echo '{"sessionId":"cp1","error":{"message":"Rate limited, retrying"},"recoverable":true}' | ambient hook copilot errorOccurred`, then the same with `"recoverable":false`.

**Expected**

- *Shell · git status* in pink (`#DB61A2`), even though Copilot sends `toolArgs` as a JSON string.
- The permission prompt reads *Approve a command* when Copilot's text names the shell tool ("…permission to use bash"), otherwise *Approve a tool · <Copilot's text>*; idle and shell-completed notifications change nothing.
- The recoverable error changes nothing; the unrecoverable one reads *Failed · Rate limited, retrying*.
- `agentStop` reads *Done* with no summary.

### EVT-018 · OpenCode's permission requests and questions say what they need, and an answer resumes work

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `OpenCodeAdapterTests.permissionsSayWhatTheyNeed`, `OpenCodeAdapterTests.questionsAndAnswers`, `OpenCodeAdapterTests.itsPluginSpeaksClaudesFormat`, `OpenCodeAdapterTests.itsToolsNameFilesInCamelCase`, `WaitingStateTests.anAnsweredPromptReturnsToWhatItInterrupted`, `OpenCodePluginTests`
- **Needs:** OpenCode 1.4 or 2 with the Ambient plugin installed

**Steps**

1. Ask OpenCode to run `bun test`, edit `a.ts` and `b.ts`, and read `~/elsewhere/notes.md`, approving each when asked.
2. Ask it something that makes it use its question tool; answer in OpenCode.

**Expected**

- *Approve a command · bun test*, *Review a change · a.ts +1 more*, *Allow access outside the project · ~/elsewhere* (home shown as `~`), in that order.
- The question reads *Answer a question · <first question>*.
- Each answer you give in OpenCode returns the row at once to the tool it interrupted (or *Thinking*), without waiting for the next tool event.

### EVT-019 · OpenCode events that arrive out of order still end in the right state

- **Priority:** P2
- **Type:** automated
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `OpenCodeAdapterTests.eventsCarryOpenCodesTime`, `WaitingStateTests.aToolThatArrivesAfterItsPromptDoesntHideIt`, `WaitingStateTests.aLiveOpenCodeRunReadsRightInTheOrderItArrived`, `SessionStoreTests.olderEventsAreIgnored`
- **Needs:** nothing special

**Steps**

1. Send an OpenCode `Permission` event with `"ts"` set to now in milliseconds, then a `PreToolUse` for the same call with a `ts` 1 ms earlier.
2. Send another event whose `ts` is 5 minutes off the Mac's clock.

**Expected**

- The row stays on *Approve a command · …*: an event older than the session's last one is dropped.
- A `ts` more than 60 seconds from the hook's clock is ignored and the event is stamped with the time it arrived.

## Any other agent

### EVT-020 · `ambient emit` drives a session through its whole life

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `CustomAdapterTests.everyEvent`, `SessionStoreTests.aCustomAgentKeepsItsName`
- **Needs:** nothing special

**Steps**

1. In folder `nightly-proj`, run in turn, checking `ambient status` and the island after each:
   `ambient emit start --session nightly --agent Build`,
   `ambient emit working --session nightly`,
   `ambient emit working --session nightly --tool make --detail "make release"`,
   `ambient emit done --session nightly --message "Release built"`,
   `ambient emit error --session nightly --message "make failed"`,
   `ambient emit end --session nightly`.

**Expected**

- `start` lists the session as *Idle* under project `nightly-proj` (the current folder); the island stays hidden for it.
- `working` without `--tool` reads *Thinking*; with it, *make · make release*, in grey-blue (`#B4BCC6`) with the agent named *Build*.
- `done` reads *Done · Release built*; `error` reads *Failed · make failed*.
- `end` removes the row at once (`idle` does the same). Each command exits 0 and prints nothing.

### EVT-021 · `ambient emit waiting --reason` picks the headline

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientContracts/Need.swift`
- **Automated by:** `WaitingReasonTests.customAgentsNameTheirNeed`, `NeedTests.oldReasonsStillRead`
- **Needs:** nothing special

**Steps**

1. Run `ambient emit waiting --session r1 --reason command --message "deploy prod"`; then `--reason EDIT`, `web`, `access`, `plan`, `permission`, `question`, `banana`, and no `--reason`.

**Expected**

- *Approve a command · deploy prod*, *Review a change · …*, *Allow web access · …*, *Allow access outside the project · …*, *Review a plan · …*, *Approve a tool · …*, *Answer a question · …*.
- `EDIT` is read case-insensitively; `banana` and no reason both read *Answer a question*.

### EVT-022 · `ambient hook custom` takes one JSON object, the way agent hooks do

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/Adapters/HookPayload.swift`, `Sources/AmbientContracts/Event.swift`
- **Automated by:** `CustomAdapterTests.everyEvent`, `CustomAdapterTests.theAgentNamesItselfBriefly`, `CustomAdapterTests.theEventCanComeFromTheCommandInstead`, `HookArgumentsTests`
- **Needs:** nothing special

**Steps**

1. Run `echo '{"session_id":"nightly","event":"done","agent":"Build","message":"Release built","cwd":"/tmp/rel"}' | ambient hook custom`.
2. Run `echo '{"session_id":"n2","agent":"A very long agent name that goes on"}' | ambient hook custom working`.

**Expected**

- A row *Done · Release built* for agent *Build*, project `rel`.
- The second takes its event from the command (`working`, so *Thinking*), and its agent reads *A very long agent name…* (24 characters with the ellipsis).
- Both exit 0 and print nothing. With no `agent`, the label is *Agent*.

### EVT-023 · `ambient emit` reports misuse and an app that isn't running

- **Priority:** P2
- **Type:** manual
- **Covers:** `Sources/ambient/Commands.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. Run `ambient emit bogus --session x; echo $?`, then `ambient emit done --session ""; echo $?`, then `ambient emit; echo $?`.
2. Quit Ambient and run `ambient emit done --session x; echo $?`.

**Expected**

- `bogus`: *Usage: ambient emit <start|working|waiting|done|error|end|idle> --session ID [--agent NAME] [--cwd PATH] [--tool NAME] [--detail TEXT] [--message TEXT]*, exit 64.
- Empty session: *That event has no effect.*, exit 64.
- No arguments: *Usage: ambient emit <working|waiting|done|error|idle> [--agent A] [--project P] [--message M]*, exit 64.
- App quit: *Ambient isn't running. Open Ambient.app, then try again.*, exit 1, within half a second.

## Many sessions, and sessions that go quiet

### EVT-024 · Several sessions at once: the most urgent leads

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/SessionStore.swift`, `Sources/AmbientContracts/Session.swift`, `Sources/AmbientCore/Policy.swift`
- **Automated by:** `SessionStoreTests.waitingOutranksDoneAndErrorAcrossSessions`, `SessionStoreTests.sameSessionIdFromDifferentAgentsAreDistinct`, `SessionStoreTests.unknownSessionIsCreatedOnFirstEvent`, `IslandPolicyTests.primaryIsTheMostUrgentNonIdleSession`
- **Needs:** nothing special

**Steps**

1. Run `ambient emit working --session a --tool make`, `ambient emit done --session b --message ok`, `ambient emit error --session c --message bad`, `ambient emit waiting --session d --reason command --message "rm x"`.
2. Run `ambient status`; then end `d`, then `c`, checking after each.
3. Send a Claude hook payload and a custom one that share the session id `same`.

**Expected**

- Rows are ordered needs you › failed › done › working, newest first within each; the header reads `needs you`, and the island shows session `d`.
- After ending `d` the header and island move to `failed`, then to `done`.
- Two rows exist for `same` (`claude:same` and `custom:same`); neither overwrites the other.

### EVT-025 · Looking at a result or prompt settles it

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/SessionStore.swift`, `Sources/AmbientContracts/Session.swift`
- **Automated by:** `SessionStoreTests.acknowledgingDoneQuietsIt`, `SessionStoreTests.acknowledgingByHostAppOnlyTouchesItsSessions`, `SessionStoreTests.seeingAPromptSettlesItToWorking`, `SessionStoreTests.aNewPromptAsksAgain`, `SessionStoreTests.newPromptResetsAcknowledgement`
- **Needs:** Claude Code connected in Terminal

**Steps**

1. Let a Claude Code turn finish while another app is in front; then switch to its Terminal tab.
2. Make it ask a permission, and click its row on the island without answering.
3. Run `ambient emit done --session k --message hi`, then `ambient ack`.

**Expected**

- The done row stops being green a few seconds after you switch to its tab (it still reads *Done · …*, with a grey dot).
- The seen prompt stops being amber and counts as working, assuming you answered; a new prompt asks again in amber.
- `ambient ack` greys every finished row and exits 0.

### EVT-026 · A session that stops reporting doesn't stay busy or urgent forever

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `SessionStoreTests.sweepIdlesStaleBusySessions`, `SessionStoreTests.sweepGivesUpOnLongWaits`, `SessionStoreTests.sweepAutoAcknowledgesOldResults`, `SessionStoreTests.sweepDropsLongIdleSessions`, `StateFileTests.restoredSessionsKeepAging`
- **Needs:** a few hours, or a Mac whose clock you can move forward

**Steps**

1. From a process that stays alive, send three events and nothing more: `python3 -c 'import subprocess as p,time; b="'$HOME'/.ambient/bin/ambient"; p.run([b,"emit","working","--session","q1","--tool","make"]); p.run([b,"emit","waiting","--session","q2"]); p.run([b,"emit","done","--session","q3"]); time.sleep(9000)'`.
2. Check `ambient status` after 11 minutes, 31 minutes, 61 minutes and 2 hours 1 minute of quiet.

**Expected**

- After 10 minutes with no event, `q1` reads *Idle*.
- After 30 minutes, the unanswered `q2` reads *Idle*.
- After 60 minutes, `q3` still reads *Done* but no longer counts as needing attention (grey dot, header no longer `done`).
- Idle sessions quiet for 2 hours leave the list. The check runs every 5 seconds, so each change lands within about 5 seconds of its limit.

### EVT-027 · A session disappears when its agent process exits

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `SessionStoreTests.sweepDropsSessionsWhoseAgentExited`, `HostTests.agentIsTheFirstNonShellAncestor`
- **Needs:** Claude Code connected

**Steps**

1. Run `python3 -c 'import subprocess,time; subprocess.run(["'$HOME'/.ambient/bin/ambient","emit","working","--session","p1"]); time.sleep(20)'`.
2. Watch `ambient status` during and after the 20 seconds.
3. Start `claude`, send a prompt, then close its Terminal window mid-turn (or `kill -9` it).

**Expected**

- `p1` is listed while Python runs and gone within about 5 seconds of it exiting.
- The killed Claude Code session leaves the island and `ambient status` within about 5 seconds, though no SessionEnd hook fired.

### EVT-028 · A session that ends is removed at once

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `SessionStoreTests.sessionEndRemovesIt`, `ClaudeAdapterTests.sessionEnd`
- **Needs:** Claude Code connected

**Steps**

1. Finish a turn in Claude Code, then type `/exit`.

**Expected**

- The row leaves the island and `ambient status` within a second, green or not, with no alert.

## The hook process

### EVT-029 · A hook never blocks the agent when Ambient isn't running

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientBase/UnixSocket.swift`
- **Automated by:** `SocketTests.sendingToNobodyFailsFast`
- **Needs:** Claude Code and Codex connected

**Steps**

1. Quit Ambient from the menu bar.
2. Run `time (echo '{"session_id":"x","hook_event_name":"UserPromptSubmit"}' | ~/.ambient/bin/ambient hook claude); echo "exit $?"`.
3. Use Claude Code and Codex for a full turn with tools; then open Ambient again.

**Expected**

- The hook prints nothing, exits 0, and takes well under a second (it fails at once on connect).
- Both agents run normally, with no hook error and no visible delay.
- When Ambient opens, nothing from the quit period appears: events sent while it was down are dropped, not queued. The next hook from a live session brings its row back.

### EVT-030 · A hook whose stdin never closes still exits in 3 seconds

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Hook.swift`
- **Automated by:** none
- **Needs:** nothing special

**Steps**

1. In zsh, run `time (~/.ambient/bin/ambient hook gemini < <(sleep 30)); echo "exit $?"` (stdin stays open for 30 seconds).
2. Repeat with `claude` instead of `gemini`.

**Expected**

- Both return after about 3 seconds, not 30, with exit 0.
- Gemini's run prints `{}` once before exiting; Claude's prints nothing.

### EVT-031 · Malformed or unknown hook input is ignored quietly

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientCore/Adapters/HookPayload.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`
- **Automated by:** `ClaudeAdapterTests.unknownEventIsIgnored`, `ClaudeAdapterTests.missingSessionIdIsIgnored`, `ClaudeAdapterTests.eventNameFallsBackToHint`, `HookArgumentsTests`
- **Needs:** nothing special

**Steps**

1. With `export AMBIENT_DEBUG=1`, pipe each of these to `ambient hook claude`, checking `echo $?`: `not json`; `[1,2]`; `{}`; `{"session_id":"","hook_event_name":"Stop"}`; `{"session_id":"m1","hook_event_name":"SomethingNew"}`; `{"session_id":42,"hook_event_name":"UserPromptSubmit"}`.
2. Run `echo '{}' | ambient hook notanagent; echo $?`.
3. Read `~/.ambient/logs/hook.log` and `ambient status`.

**Expected**

- Every run exits 0 and prints nothing; the agent would carry on unaffected.
- The first five add no session; the log has one line each, like `ignored claude payload (9 bytes)`.
- The numeric session id is read as text: a session `42` appears, *Thinking*.
- The unknown agent writes nothing to the log and sends nothing.

### EVT-032 · An oversized hook payload is reduced to a few short fields

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Hook.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientBase/Trim.swift`
- **Automated by:** none
- **Needs:** `python3`

**Steps**

1. Build a 20 MB PostToolUse payload: `python3 -c 'import json;print(json.dumps({"session_id":"big","hook_event_name":"PostToolUse","tool_name":"Bash","tool_response":{"stdout":"x"*20_000_000}}))' > /tmp/big.json`.
2. Run `time ambient hook claude < /tmp/big.json; echo $?` and then `ambient status --json`.
3. Repeat with a `Stop` payload whose `last_assistant_message` is 20 MB.

**Expected**

- Each exits 0 within 3 seconds (the watchdog), typically well under one.
- The session shows *Thinking* after the tool, with nothing of the output; the Stop shows *Done · xxx…*, 160 characters.
- Ambient stays responsive and its memory doesn't jump: only the trimmed line crossed the socket.

### EVT-033 · Text that leaves the hook is trimmed to fixed limits

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientBase/Trim.swift`, `Sources/AmbientBase/TextLimits.swift`, `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/Adapters/ToolDetail.swift`
- **Automated by:** `TrimTests`, `ClaudeAdapterTests.longCommandsAreTruncatedTo80`, `CustomAdapterTests.longSessionIdsAreCut`, `CustomAdapterTests.theAgentNamesItselfBriefly`
- **Needs:** nothing special

**Steps**

1. Send `ambient emit working --session t --tool make --detail "<200 characters>"`, then `ambient emit done --session t --message "<line 1>\n\n<line 2 …400 characters, with emoji>"`.
2. Send a custom event whose `session_id` is 300 characters, and one whose `agent` is 40.
3. Read `ambient status --json`.

**Expected**

- The detail is 80 characters, the last being `…`; the message 160, ending in `…`, with runs of spaces and newlines collapsed to one space and no emoji split in half.
- The session id is 128 characters (127 + `…`); the agent name 24 (23 + `…`).
- A blank `--message "   "` counts as no message: *Done* alone.

## Privacy and what's stored

### EVT-034 · Prompts never leave the hook or reach the disk

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/ambient/Hook.swift`, `Sources/AmbientContracts/Event.swift`
- **Automated by:** `ClaudeAdapterTests.promptSubmitNeverCarriesThePrompt`
- **Needs:** Claude Code, Codex and Gemini CLI connected; Summarize tasks with local LLM off

**Steps**

1. With `AMBIENT_DEBUG=1` exported, send each agent a prompt containing `zebra-canary-4471` and asking it to reply only "finished".
2. Quit Ambient (so everything is saved), then run `grep -rl zebra-canary-4471 ~/.ambient`.

**Expected**

- No file under `~/.ambient` contains the canary: not `state.json`, `tasks.json`, `day.json`, nor `logs/hook.log`.
- `ambient status --json` showed only *Thinking*/*Done* for those turns, never the prompt.

### EVT-035 · Tool output never leaves the hook or reaches the disk

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/Adapters/Adapters.swift`, `Sources/AmbientCore/Adapters/ToolDetail.swift`, `Sources/ambient/Hook.swift`
- **Automated by:** `ClaudeAdapterTests.postToolUseAndFailure`
- **Needs:** Claude Code and Codex connected; Summarize tasks with local LLM off

**Steps**

1. With `AMBIENT_DEBUG=1` exported, ask each agent to run `printf 'canary-%s\n' 9931` and reply only "finished" (the output, `canary-9931`, isn't in the command).
2. Quit Ambient, then run `grep -rl canary-9931 ~/.ambient`.

**Expected**

- Nothing matches. The command hint (`printf 'canary-%s\n' 9931`) may appear; its output never does.

### EVT-036 · The saved state holds only the short fields, readable only by you

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientCore/StateFile.swift`, `Sources/AmbientContracts/Session.swift`, `Sources/AmbientContracts/Event.swift`
- **Automated by:** `StateFileTests.stateIsPrivate`, `StateFileTests.sessionsSurviveARoundTrip`, `FormatFixtureTests.stateFile`
- **Needs:** Claude Code connected

**Steps**

1. Finish a Claude Code turn, wait 2 seconds, and run `ls -l ~/.ambient/state.json` and `python3 -m json.tool ~/.ambient/state.json`.

**Expected**

- Mode `-rw-------`.
- `{"version":1,"sessions":[…]}`, each session holding only: id, agent, session id, `cwd`, the return address (`host`: bundle id, terminal, process ids, tty, tmux/cmux ids), activity with its ≤80-character hint or ≤160-character message, times, tool and subagent counts, `acknowledged`, and the title.
- No prompt, transcript, tool input beyond the hint, or tool output.

**Known gap:** The README lists `~/.ambient/` as holding "saved session state" and says prompts and tool output are never stored, but doesn't say that state keeps the agent's last message (up to 160 characters), permission text, the 80-character command hint and the chat title on disk; an agent's final message can quote tool output.

### EVT-037 · Sessions survive an app restart, demo sessions don't

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/StateFile.swift`, `Sources/AmbientCore/SessionStore.swift`
- **Automated by:** `StateFileTests.sessionsSurviveARoundTrip`, `StateFileTests.titlesSurviveAndOlderFilesStillLoad`, `StateFileTests.missingOrCorruptFilesLoadEmpty`, `StateFileTests.restoredSessionsKeepAging`
- **Needs:** Claude Code connected

**Steps**

1. Start a long Claude Code turn, run `ambient emit waiting` (a demo session), and wait 2 seconds.
2. Quit and reopen Ambient while the turn runs.
3. Quit, replace `~/.ambient/state.json` with `garbage`, and reopen.

**Expected**

- After reopening, the Claude Code session is back mid-turn with its activity and clock; the demo session isn't.
- Sessions whose agent exited while Ambient was closed are gone right after launch.
- With the corrupt file Ambient opens with no sessions and no error, and writes a valid file about a second after the next event.

### EVT-038 · The hook log exists only when asked for

- **Priority:** P1
- **Type:** manual
- **Covers:** `Sources/ambient/Hook.swift`
- **Automated by:** none
- **Needs:** Claude Code connected

**Steps**

1. Delete `~/.ambient/logs/hook.log`. Run a Claude Code turn normally and check the file.
2. Restart Claude Code with `AMBIENT_DEBUG=1` in its environment, run a turn, and read the log. Then quit Ambient and run one more turn.

**Expected**

- Without the variable, no `hook.log` is created.
- With it, one ISO 8601-stamped line per hook: `sent claude promptSubmitted`, `sent claude toolStarted(name: "Bash", detail: …)`, and, with Ambient quit, `app not reachable: …`. Lines carry only the trimmed fields the event carries, never the prompt or tool output.

## Socket, wire and app server

### EVT-039 · The socket is private to the user and replaced when stale

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientBase/UnixSocket.swift`, `Sources/AmbientApp/EventServer.swift`
- **Automated by:** `SocketTests.socketIsPrivateToTheUser`, `SocketTests.staleSocketFileIsReplaced`, `SocketTests.secondServerOnALiveSocketRefuses`, `SocketTests.tooLongPathIsRejected`, `PathsTests.ambientHomeOverrides`
- **Needs:** a second user account on the Mac

**Steps**

1. Run `ls -l ~/.ambient/ambient.sock`.
2. As the other user, try `echo '{}' | nc -U /Users/<you>/.ambient/ambient.sock`.
3. Force-quit Ambient (`kill -9`), check the socket file is still there, reopen Ambient, and send `ambient emit done --session s1`.
4. Launch a second copy of Ambient (e.g. a dev build) while the first runs.

**Expected**

- `srw-------`, owned by you; the other user's connect is refused.
- After the force-quit, the reopened app replaces the stale file and the event shows.
- The second copy logs `Socket server failed: alreadyRunning` (Console, subsystem `com.viveky259259.Ambient`, category `server`) and the first keeps receiving events.

### EVT-040 · Garbage, oversized or stalled messages don't disturb the app

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientApp/EventServer.swift`, `Sources/AmbientBase/UnixSocket.swift`, `Sources/AmbientCore/Wire.swift`
- **Automated by:** `SocketTests.oversizedMessagesAreDropped`, `SocketTests.aClientThatGaveUpDoesntTakeTheServerDown`, `SocketTests.aClientThatLeftBeforeItWasServedDoesntTakeTheServerDown`, `SocketTests.repliesLargerThanTheSocketBufferArriveWhole`
- **Needs:** `python3`; Console

**Steps**

1. Run `printf 'hello\n' | nc -U ~/.ambient/ambient.sock`.
2. Send a 300 KB line: `python3 -c 'print("x"*300_000)' | nc -U ~/.ambient/ambient.sock`.
3. Open `nc -U ~/.ambient/ambient.sock` and type nothing; meanwhile run `ambient emit done --session s2`.
4. Send an event whose custom `cwd` is 300 KB long.

**Expected**

- The garbage line logs `Dropped an undecodable message (5 bytes)`; the app keeps running.
- The 300 KB line is dropped without a log line or reply (the limit is 256 KB).
- The idle connection is closed after about 1 second; `s2` shows at once, unaffected.
- The event with the huge `cwd` is dropped silently, since `cwd` isn't trimmed.

### EVT-041 · CLI and app speak one JSON line per connection, in a stable format

- **Priority:** P1
- **Type:** automated
- **Covers:** `Sources/AmbientCore/Wire.swift`, `Sources/AmbientContracts/Event.swift`, `Sources/AmbientContracts/Session.swift`
- **Automated by:** `SocketTests.wireMessagesAreSingleJSONLines`, `SocketTests.eventsReachTheServer`, `SocketTests.requestsGetReplies`, `FormatFixtureTests.wireMessages`, `ContractFixtureTests.eventKind`, `ContractFixtureTests.agentEvent`, `ContractFixtureTests.hostInfo`, `ContractFixtureTests.session`, `EventTests`, `HostCaptureDetailTests.olderHostInfoStillDecodes`, `NeedTests.answeredRoundTripsOverTheWire`
- **Needs:** nothing special

**Steps**

1. Run the listed tests.

**Expected**

- Each message is one JSON object ending in a single newline; every event kind, session and host round-trips against the `v1` fixtures, so a hook link from an older Ambient still reaches a newer app.

### EVT-042 · `ambient status` reads the sessions the app holds

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/Commands.swift`, `Sources/AmbientApp/EventServer.swift`, `Sources/AmbientContracts/Describe.swift`
- **Automated by:** `DescribeTests.activities`, `DescribeTests.durations`, `DescribeTests.titlePrefersTheChatOrThreadTitle`, `DescribeTests.sessionTitleFallsBackToAgent`
- **Needs:** nothing special

**Steps**

1. With no sessions, run `ambient status`. Add one with `ambient emit working --session st --tool make` and run it again, then `ambient status --json`.
2. Quit Ambient and run `ambient status; echo $?`.

**Expected**

- `Ambient · 0 sessions · idle`, then `Ambient · 1 session · working` and a row `● custom      <project, padded to 28> make  <n>s`.
- `--json` prints the sessions as pretty, key-sorted JSON with ISO 8601 dates.
- With Ambient quit: *Ambient isn't running. Open Ambient.app, then try again.*, exit 1, after at most 3 seconds.

## Titles and alerts

### EVT-043 · Sessions take the title they have in Claude or Codex

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/SessionTitles.swift`, `Sources/AmbientCore/SessionStore.swift`, `Sources/AmbientContracts/Describe.swift`
- **Automated by:** `SessionTitlesTests.claudeDesktopChatTitle`, `SessionTitlesTests.claudeTranscriptLatestCustomTitle`, `SessionTitlesTests.desktopFallsBackToTheTranscript`, `SessionTitlesTests.codexThreadNameLatestWins`, `SessionTitlesTests.noSourceNoTitle`, `SessionTitlesTests.longTitlesAreTrimmed`, `SessionStoreTests.titlesAreSetWithoutTouchingState`
- **Needs:** Claude desktop app with a Code session; Codex app; Claude Code CLI

**Steps**

1. Start a Code session in Claude's desktop app and let it name the chat; start a thread in Codex and rename it.
2. In the Claude Code CLI, give a session a custom title (it appends a `custom-title` line to `~/.claude/projects/<project>/<session id>.jsonl`).
3. Rename one of them to a 90-character title. Watch the island and `ambient status` for up to a minute after each.

**Expected**

- Each row's title becomes the chat title, the custom title or the Codex thread name within about a minute, in place of the project name; the project shows beside it where it adds information.
- A rename shows within a minute; the activity, clock and alerts don't change.
- The 90-character title is cut to 60 (59 + `…`). Gemini, Antigravity, Cursor, Copilot, OpenCode and custom sessions keep their project name.

### EVT-044 · Session ids from hooks never become file paths

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/SessionTitles.swift`
- **Automated by:** `SessionTitlesTests.idsFromHooksNeverBecomePaths`
- **Needs:** nothing special

**Steps**

1. Run `echo '{"session_id":"../../../etc/passwd","hook_event_name":"UserPromptSubmit"}' | ambient hook claude`, and the same for `codex`.
2. Wait a minute, then run `sudo fs_usage -w -f filesys Ambient | grep passwd` while sending another such event.

**Expected**

- The sessions appear with no title (ids must match `^[A-Za-z0-9-]{1,64}$`, desktop ids `^local_[A-Za-z0-9-]{1,64}$`), and no file outside `~/.claude/projects`, `~/.codex/session_index.jsonl` and Claude's `claude-code-sessions` folder is opened.

### EVT-045 · Alerts fire only on a change that needs you, and quick turns stay quiet

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientCore/Policy.swift`, `Sources/AmbientContracts/Session.swift`
- **Automated by:** `AlertPolicyTests`, `IslandPolicyTests.bloomsOnAttentionTransitions`, `IslandPolicyTests.workingIsShownOnlyWhenWanted`, `GlowStyleTests.stylesPerMood`
- **Needs:** notifications and sounds on; done threshold at its default, 20 seconds

**Steps**

1. With another app in front, run `ambient emit working --session al --tool x`, wait 5 seconds, `ambient emit done --session al`.
2. Repeat but wait 25 seconds before `done`.
3. Run `ambient emit waiting --session al2` twice in a row; then `ambient emit error --session al3 --message x`.
4. Repeat step 2 with the agent's terminal in front, and with *Quiet alerts* on.

**Expected**

- The 5-second turn turns green and blooms for 5 seconds but sends no banner or chime; the 25-second one sends one banner and the done chime.
- The first `waiting` blooms amber for 8 seconds with a banner; the second sends nothing more. The error blooms red for 5 seconds with a banner.
- With the terminal in front or Quiet alerts on: no banner, no chime.

## Build compatibility

### EVT-046 · Code importing AmbientCore still sees the split-out modules and old names

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientCore/Exports.swift`, `Sources/AmbientCore/Deprecated.swift`
- **Automated by:** `SessionStoreTests`, `ClaudeAdapterTests`
- **Needs:** a quiet Mac to build on

**Steps**

1. Build the package (`swift build`).
2. In a scratch target importing only `AmbientCore`, use `EventKind`, `Trim.truncate` and `SessionStore.processExists(1)`.

**Expected**

- The build succeeds; `EventKind` and `Trim` resolve through `AmbientCore`'s re-exports.
- `SessionStore.processExists` compiles with a warning *renamed to 'ProcessProbe.isAlive'*; `AlertPolicy.attentionMoods` with *Use Mood.wantsAttention*.

### EVT-047 · Config edits keep key order, number spelling and escapes

- **Priority:** P2
- **Type:** automated
- **Covers:** `Sources/AmbientBase/JSON/**`
- **Automated by:** `JSONTests.roundTripPreservesOrderAndBytes`, `JSONTests.keysKeepTheirOrder`, `JSONTests.numbersKeepTheirLexeme`, `JSONTests.escapesDecodeAndReencode`, `JSONTests.detectsIndentation`, `InstallerTests`
- **Needs:** nothing special

**Steps**

1. Run the listed tests.

**Expected**

- A document parsed and written again comes back byte for byte; key order and number spelling (`1.0` stays `1.0`) are kept, and escapes decode and re-encode; indentation is detected; truncated or trailing input (`{`, `[1,]`, `{"a":1} x`, `tru`) is refused with an error naming the byte offset, and nesting deeper than 512 levels is refused. This is what keeps each agent's settings file intact when its hook entries are written.
