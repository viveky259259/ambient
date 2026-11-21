# Agent history

Id prefix: `HIS-`

Agent history: keeping a team's finished agent chats in one store and answering from them. `ambient history setup`,
`capture`, `sync`, `why`, `ask`, `show`, `open` and `eval`; what is stored and what never is; how a chat is tied to
git; the cards a model writes; the `history_why`, `history_search` and `history_read` tools of `ambient mcp`; the
comment left on pull requests; and the app storing a chat when its session ends.

Unless a case says otherwise: `ambient` means `~/.ambient/bin/ambient`; `qa-his` is a scratch git repository with an
`origin` remote on GitHub (`git init qa-his && cd qa-his && git remote add origin git@github.com:OWNER/qa-his.git`)
and at least one commit; `qa-store` is an empty folder (`mkdir ~/qa-store`), used as the store so no cloud account is
needed; and "a Claude chat in `qa-his`" means a Claude Code session started in that folder, whose transcript is
`~/.claude/projects/<folder>/<session id>.jsonl`. History's settings are `~/.ambient/history.json`; this Mac's index
and copies are under `~/.ambient/history/`. A stored chat is three files under
`OWNER/qa-his/sessions/<yyyy>/<mm>/<dd>/claude-<session id>/` in the store: `chat.json`, `cards.json` and `page.html`.
Cases that use a model need a working Claude API key in `ANTHROPIC_API_KEY` or in Ambient's Keychain item; the rest
pass `--no-model`.

## Setting up, and what is never stored

### HIS-001 · Setup turns history on for one repository and proves the store works

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/ambient/HistoryCommand.swift`, `Sources/AmbientHistory/HistoryConfig.swift`, `Sources/AmbientHistory/HistoryStore.swift`
- **Automated by:** `HistoryCommandTests.setsUpCapturesAndAnswers`, `ConfigTests.savesAndLoadsWithDefaultsForWhatIsMissing`, `ConfigTests.picksTheStoreARepositoryIsSetUpWith`, `StoreTests.aFolderStoresListsAndNoticesChanges`
- **Needs:** nothing special

**Steps**

1. With no `~/.ambient/history.json`, run `ambient history status`.
2. In `qa-his`, run `ambient history setup --store ~/qa-store`.
3. Run `ambient history status`, then `cat ~/.ambient/history.json`.
4. Run the setup command a second time and read the file again.

**Expected**

- Step 1 says history isn't set up for any repository.
- Step 2 prints *OWNER/qa-his: finished chats will be kept in* the folder's absolute path, then that a chat is stored when its session ends or after 24 quiet hours, that chats finished before now stay on this Mac, and that no links are left on pull requests (a folder has no address to link). No Keychain dialog appears.
- `~/qa-store/OWNER/qa-his/sessions/.ambient-setup` exists: setup wrote to the store before saving anything.
- Step 3's status lists `OWNER/qa-his → <folder>` with *0 chats, 0 cards indexed here*. The file has one entry under `repos`, keyed `OWNER/qa-his`, with `store`, `postLinks` false and a `since` timestamp, and is readable only by the user (mode 600).
- Step 4 leaves `since` exactly as it was.

### HIS-002 · A chat in a repository that isn't set up is never read or stored

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientHistory/HistoryPipeline.swift`, `Sources/AmbientHistory/Capture.swift`, `Sources/AmbientHistory/GitFacts.swift`, `Sources/ambient/HistoryCommand.swift`
- **Automated by:** `PipelineTests.leavesAloneWhatIsNotSetUp`, `PipelineTests.aRepositoryOnAnotherHostGetsNoPullRequestComment`, `HistoryCommandTests.nothingWorksUntilARepositoryIsSetUp`, `GitFactsTests.readsTheRepositoryNameFromItsRemote`
- **Needs:** `qa-his` set up as in HIS-001; a second repository `qa-other` with a different `origin`, and a Claude chat in it

**Steps**

1. Note the session id of the chat in `qa-other` and run `ambient history capture --session <id> --no-model`.
2. List `~/qa-store` recursively.
3. In a folder that is a git repository with no `origin` remote, run `ambient history setup --store ~/qa-store`.
4. Run `ambient history setup --store ~/qa-store --repo justaname`.

**Expected**

- Step 1 prints a skipped line saying `OTHER/qa-other isn't set up for history`, and exits 0.
- Step 2 shows nothing but the `.ambient-setup` marker: no file from that chat exists anywhere in the store.
- Steps 3 and 4 fail with *This repository has no `origin` remote to name it by*: a repository is known by its remote's `owner/name`, never by a folder's name, so two unrelated folders that share a name can't share a store.

### HIS-003 · Credentials in a chat are blanked before anything is written

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientHistory/Redactor.swift`, `Sources/AmbientBase/SecretPatterns.swift`, `Sources/AmbientHistory/Capture.swift`
- **Automated by:** `RedactorTests.blanksSecrets`, `RedactorTests.blanksAWholePrivateKey`, `RedactorTests.leavesOrdinaryCodeAlone`, `RedactorTests.writesTheHomeFolderAsATilde`, `RedactorTests.everyPatternCompiles`, `CaptureTests.buildsTheRecordAChatIsStoredAs`
- **Needs:** `qa-his` set up; Claude Code

**Steps**

1. In a Claude chat in `qa-his`, ask it to run `echo 'export DEMO_API_TOKEN=abcdef0123456789' > /tmp/qa-his-env && cat /tmp/qa-his-env`, then `curl -s -H 'Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123' https://example.com -o /dev/null`. End the session.
2. Run `ambient history capture --session <id> --no-model`.
3. Search the three stored files for `abcdef0123456789`, for `abcdefghijklmnopqrstuvwxyz0123`, and for your home folder's path.

**Expected**

- None of the three searches finds anything in `chat.json`, `cards.json` or `page.html`.
- `chat.json` shows the commands with `DEMO_API_TOKEN=[redacted: credential]` and `Bearer [redacted: authorization header]`, and paths under your home folder written with `~`.
- Ordinary code in the chat is unchanged: a line such as `let token = makeToken()` is not blanked.

### HIS-004 · Chats that finished before setup stay on the Mac unless asked for

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientHistory/HistoryPipeline.swift`, `Sources/AmbientHistory/HistoryConfig.swift`
- **Automated by:** `PipelineTests.findsChatsThatWentQuietAfterSetup`, `ConfigTests.aTranscriptIsCapturedAgainOnlyWhenItGrew`, `PipelineTests.readsAChatsFolderFromItsFirstLines`
- **Needs:** a repository with Claude chats more than a day old, set up for history only now

**Steps**

1. Right after `ambient history setup`, run `ambient history capture --due --dry-run`.
2. Run `ambient history capture --due --since 30 --dry-run --no-model`.

**Expected**

- Step 1 says *Nothing is waiting to be captured*: setting up doesn't upload the repository's past.
- Step 2 lists a *Would store* line for each chat of the last 30 days that has been quiet for 24 hours, with its event, request and commit counts, and writes nothing to the store.
- A chat whose transcript changed less than 24 hours ago is in neither list.

## Storing a chat

### HIS-005 · A finished chat is stored as a record, cards and a page

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientHistory/HistoryPipeline.swift`, `Sources/AmbientHistory/ClaudeTranscript.swift`, `Sources/AmbientHistory/HistoryFormat.swift`, `Sources/AmbientHistory/Episodes.swift`, `Sources/AmbientHistory/HistoryPage.swift`
- **Automated by:** `PipelineTests.storesAChatAndIndexesIt`, `PipelineTests.aDryRunWritesNothing`, `ClaudeTranscriptTests.readsEveryKindOfLine`, `ClaudeTranscriptTests.turnsToolCallsIntoPathsAndDiffs`, `EpisodeTests.splitsWhereThePersonSpoke`, `EpisodeTests.aCardFromTheChatsOwnWords`, `FormatTests.chatRecord`, `PageAndEvalTests.rendersAChatAsAPageThatTrustsNothingInIt`
- **Needs:** `qa-his` set up; Claude Code

**Steps**

1. In a Claude chat in `qa-his`, ask it to add a line to `README.md` with its edit tool. When it's done, ask a second question that changes nothing (*why that wording?*). End the session.
2. Run `ambient history capture --session <id> --no-model`.
3. Open the stored `page.html` in a browser, and read `cards.json`.

**Expected**

- Step 2 prints *Stored "<the chat's title>": N events, 2 requests (1 changed code), 0 commits* and the page's `file://` address.
- The store has `chat.json`, `cards.json` and `page.html` under `OWNER/qa-his/sessions/<date the chat started>/claude-<id>/`.
- `cards.json` has two cards. The first has the first request word for word, `files` `["README.md"]` (relative to the repository), and `landed` `uncommitted`. The second has `files` empty and `landed` `none`. Both have `source` `extract` and a summary taken from what the agent said last.
- The page shows the chat's title, repository, branch and times, a *Requests* list linking to each request, and the edit as a diff with the removed line in red and the added line in green. A `<script>` tag typed into the chat appears as text, not as markup.

### HIS-006 · A commit is tied to the chat that made it, and to no other

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientHistory/Capture.swift`, `Sources/AmbientHistory/GitFacts.swift`, `Sources/AmbientHistory/PathFinder.swift`
- **Automated by:** `CaptureTests.aCommitSomeoneElseMadeMeanwhileIsNotThisChats`, `CaptureTests.aMergeTheChatRanIsItsOwnWhateverItBroughtIn`, `CaptureTests.buildsTheRecordAChatIsStoredAs`, `GitFactsTests.listsCommitsInAWindowWithTheirFiles`, `GitFactsTests.aMergeListsWhatItBroughtIn`, `PathFinderTests.tellsCommandsThatMayCommit`, `PathFinderTests.tellsCommandsThatMerge`, `EpisodeTests.aLaterCommitCarriesAnEarlierRequestsFiles`
- **Needs:** `qa-his` set up; Claude Code; a second terminal

**Steps**

1. In a Claude chat in `qa-his`, ask it to change `README.md` and then run `sleep 30 && git commit -am 'docs: qa change'`.
2. While that command sleeps, in the second terminal commit an unrelated new file: `echo x > other.txt && git add other.txt && git commit -m 'chore: someone else'`.
3. End the session and run `ambient history capture --session <id> --no-model`. Read `commits` in `cards.json`.

**Expected**

- The capture reports 1 commit.
- `commits` holds only *docs: qa change*, with `files` `["README.md"]` and the number of the event whose command made it. *chore: someone else* is not there, although it was made while the chat's commit command was running: its message isn't in the command and it holds no file the chat changed.
- The first card's `landed` is `committed` and its `commits` lists that commit.

### HIS-007 · A file counts as changed only when the chat changed it

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientHistory/Capture.swift`, `Sources/AmbientHistory/PathFinder.swift`
- **Automated by:** `CaptureTests.anEditThatFailedChangedNothing`, `CaptureTests.aCommandThatOnlyReadsAFileNeverChangedIt`, `CaptureTests.aShellEditCountsOnlyIfCommittedSoonAfterTheChat`, `PathFinderTests.tellsWhatACommandWritesTo`, `PathFinderTests.tellsWritingCommandsFromReadingOnes`, `PathFinderTests.namesEachFileOneWay`, `PathFinderTests.aFileInAnotherProjectIsNotNamedInTextEither`, `PathFinderTests.findsFilesNamedInACommand`
- **Needs:** `qa-his` set up, with tracked files `a.txt` and `b.txt`; another project elsewhere that also has a `README.md`; Claude Code

**Steps**

1. In a Claude chat in `qa-his`, ask it to run `grep -n x b.txt > /tmp/qa-his-out.txt`, then `sed -i '' 's/one/two/' a.txt`, then to edit `README.md` in the *other* project with its edit tool.
2. End the session and run `ambient history capture --session <id> --no-model`. Read `touches` in `cards.json`.

**Expected**

- `a.txt` is listed with `how` `shell`: the command edits in place and the file now differs from `HEAD`.
- `b.txt` is listed with `how` `read`: the command only read it, and its redirect went elsewhere.
- This repository's `README.md` is not listed as changed. The other project's file appears in `chat.json` under its own path (starting `~/`), never as this repository's `README.md`.
- The card's `files` is `["a.txt"]`.

### HIS-008 · Uncommitted work is stored for the chat's own files only

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientHistory/Capture.swift`, `Sources/AmbientHistory/GitFacts.swift`
- **Automated by:** `CaptureTests.uncommittedWorkComesFromTheCheckoutTheChatEditedIn`, `GitFactsTests.showsOnlyTheNamedFilesUncommittedChanges`, `CaptureTests.aChatFromARemovedWorktreeStillBelongsToItsRepository`
- **Needs:** `qa-his` set up, with tracked files `a.txt` and `b.txt`; Claude Code

**Steps**

1. By hand, add a line to `b.txt` and leave it uncommitted.
2. In a Claude chat in `qa-his`, ask it to add a line to `a.txt` with its edit tool, and not to commit. End the session.
3. Run `ambient history capture --session <id> --no-model` and read `uncommitted` in `chat.json`; open the page.

**Expected**

- `uncommitted` is a diff holding the chat's added line in `a.txt`.
- It holds nothing from `b.txt`: your own uncommitted line there isn't stored under the chat.
- The page ends with *Uncommitted changes when the chat was captured*, showing the same diff.

### HIS-009 · A model writes each card's reason, and a chat stored again keeps what was written

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientHistory/Cards.swift`, `Sources/AmbientHistory/Model.swift`, `Sources/AmbientHistory/HistoryPipeline.swift`
- **Automated by:** `CardWriterTests.aModelWritesTheReasonAndItsEvidenceIsChecked`, `CardWriterTests.asksWithTheEventsAndAFixedShape`, `CardWriterTests.aChatStoredAgainOnlyAsksAboutWhatIsNew`, `CardWriterTests.aFailedAnswerKeepsTheChatsOwnWords`, `CardWriterTests.asksForEveryRequestWorthAsking`, `ClaudeAPITests.buildsARequestTheAPIAccepts`, `ClaudeAPITests.readsTheAnswerOutOfAReply`, `ClaudeAPITests.triesAgainWhenTheAPIIsOverloaded`, `PipelineTests.aStoreThatIsDownCostsNoModelCalls`
- **Needs:** a working Claude API key; a finished Claude chat in `qa-his` in which the agent investigated before changing a file

**Steps**

1. Run `ambient history capture --session <id>` (no `--no-model`) and read `cards.json`.
2. Run the same command again and compare the cards.

**Expected**

- Cards for requests that used tools have `source` `claude-haiku-5-5`, a `summary` naming the files changed, and a `why` that states the cause the agent found, in the chat's own identifiers. `rejected` and `verified` are filled where the chat shows something rejected or checked, and empty where it doesn't.
- Every number in `evidence` is an event inside that request's range.
- A short request with no tool call keeps `source` `extract`.
- Step 2 takes a few seconds and the cards are identical: requests that haven't changed aren't sent to the model again.

### HIS-010 · A key the API turns down is reported once

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientHistory/Cards.swift`, `Sources/AmbientHistory/Model.swift`, `Sources/AmbientHistory/HistoryAnswer.swift`
- **Automated by:** `CardWriterTests.aRejectedKeyIsSaidOnceAndStopsTheAsking`, `ClaudeAPITests.turnsABadReplyIntoAnError`, `AnswerTests.aModelThatFailsCostsTheWordsNotTheAnswer`, `ClaudeAPITests.aKeyInTheEnvironmentIsUsedWithoutAskingTheKeychain`
- **Needs:** a finished Claude chat in `qa-his` with several requests

**Steps**

1. Run `ANTHROPIC_API_KEY=sk-ant-not-a-real-key ambient history capture --session <id>`.
2. Run `ANTHROPIC_API_KEY=sk-ant-not-a-real-key ambient history ask "what changed?"`.

**Expected**

- Step 1 still stores the chat, with one warning: *The Claude API turned the key down (401: …). Put a working key in ANTHROPIC_API_KEY or in Ambient's Keychain item. Cards come from the chat's own words until then.* It is printed once, however many requests the chat has.
- Step 2 lists the likeliest cards and ends with a note that the model couldn't answer. It exits 0.
- Neither command shows a Keychain dialog: a key in the environment is used without asking the Keychain.

## Asking

### HIS-011 · `why FILE` lists the requests and commits behind a file, with no model

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientHistory/HistoryQuery.swift`, `Sources/AmbientHistory/HistoryIndex.swift`, `Sources/AmbientHistory/GitFacts.swift`, `Sources/ambient/HistoryCommand.swift`
- **Automated by:** `QueryTests.explainsAFileFromGitAndTheIndex`, `QueryTests.aCommitWithNoVisibleEditStillPointsAtItsRequest`, `QueryTests.followsAFileAcrossARename`, `IndexTests.findsRequestsByFileNewestFirst`, `IndexTests.findsTheChatAndRequestThatMadeACommit`, `GitFactsTests.followsAFilesHistoryAndBlamesALine`, `HistoryCommandTests.setsUpCapturesAndAnswers`, `HistoryArgumentTests.readsAFileWithOrWithoutALine`
- **Needs:** the chat from HIS-006 stored; `README.md` also has an earlier commit made by hand

**Steps**

1. In `qa-his`, run `ambient history why README.md`.
2. Run `ambient history why README.md:1`, where line 1 is the line the chat changed.
3. Run `ambient history why README.md --json`.

**Expected**

- Step 1 prints the path, then a count line (*1 recorded change · 1 commit with no recorded chat*), then one entry headed by the date, `claude`, the developer's git name and the chat's title, with *Asked* (the request word for word), *Did*, *Commit* (the short hash and message of *docs: qa change*) and *Chat* (`ambient history show <id> <first>-<last>`).
- Under *Commits with no recorded chat* it lists the hand-made commit with its hash, date and author. It is not attributed to any chat.
- Step 2 adds *Line 1 was last changed by <hash> (docs: qa change), marked ◆ below*, and that entry's bullet is ◆.
- Step 3 prints valid JSON with `path`, `changes` (each with `session`, `request`, `summary`, `files`, `fileCommits`, `blamed`), `references` and `commitsWithoutChat`.
- None of the three asks a model, and each returns in about a second.

### HIS-012 · `ask` answers from the cards, and reads the chats only when the cards fall short

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientHistory/HistoryAnswer.swift`, `Sources/AmbientHistory/HistoryQuery.swift`, `Sources/AmbientHistory/HistoryIndex.swift`, `Sources/AmbientHistory/Model.swift`
- **Automated by:** `AnswerTests.aSmallModelAnswersFromTheCardsWhenTheySettleIt`, `AnswerTests.aStrongerModelReadsTheChatsWhenTheCardsFallShort`, `AnswerTests.askedToGoDeepItSkipsTheQuickPass`, `AnswerTests.aSourceKeepsTheNameTheAnswerGaveIt`, `AnswerTests.withoutAModelTheCardsAreTheAnswer`, `AnswerTests.withoutAModelOnlyTheLikeliestCardsAreListed`, `QueryTests.retrievesFileChangesFirstThenMatchingWords`, `IndexTests.searchesByWordsAndByPartsOfNames`, `ClaudeAPITests.letsTheAPIHandARefusalToAnotherModelWhereItCan`
- **Needs:** a working Claude API key; the chat from HIS-009 stored with model-written cards

**Steps**

1. Run `ambient history ask "why was <the file> changed?"`.
2. Run `ambient history ask --deep "what exactly did the agent check before changing <the file>?"`.
3. Run `ambient history ask "why was <the file> changed?" --no-model`.
4. Run `ambient history ask "zzzz qqqq"`.

**Expected**

- Step 1 answers in sentences within about ten seconds, citing cards as *(C1)*. Under *Sources*, each cited card is listed with the same label, its request and where to read it.
- Step 2 takes longer (tens of seconds), cites events as *(C1 e41)*, and states details the cards don't hold, such as the commands the agent ran. Where the chat and git disagree, it says so and goes with git.
- Step 3 asks no model: it prints up to five cards (date, request, summary, reason), then *… and N less likely* if there were more, and a note that the model is turned off.
- Step 4 prints *No recorded chat is about that.*

### HIS-013 · `show` and `open` read a stored chat, and `open` never trusts the store's page

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/HistoryCommand.swift`, `Sources/AmbientHistory/HistoryPage.swift`, `Sources/AmbientHistory/HistoryIndex.swift`
- **Automated by:** `HistoryCommandTests.opensAPageMadeHereNotTheOneInTheStore`, `HistoryCommandTests.setsUpCapturesAndAnswers`, `HistoryArgumentTests.aChatsLocalCopyNeverLeavesItsFolder`, `IndexTests.findsAChatByTheStartOfItsId`, `PageAndEvalTests.rendersAChatAsAPageThatTrustsNothingInIt`
- **Needs:** a chat stored in `~/qa-store`

**Steps**

1. Run `ambient history show <first 8 characters of the session id> 1-3`.
2. Replace the stored `page.html` with `<script>alert('from the store')</script>`.
3. Run `ambient history open <first 8 characters>`.

**Expected**

- Step 1 prints events 1 to 3, one per line, each starting `[n]` and its kind (`USER:`, `TOOL Bash:`, `RESULT of [n]:`).
- Step 3 opens a page in the browser showing the chat, and no alert appears. The file opened is under `~/.ambient/history/`, made on this Mac from `chat.json`; the store's own `page.html` is not what was opened.

### HIS-014 · A teammate's Mac syncs the cards, and still answers when the store is away

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/AmbientHistory/HistoryPipeline.swift`, `Sources/AmbientHistory/HistoryIndex.swift`, `Sources/AmbientHistory/HistoryStore.swift`, `Sources/ambient/HistoryCommand.swift`
- **Automated by:** `SyncTests.bringsTheIndexInLineWithTheStore`, `SyncTests.aStoreThatSuddenlyHasNothingRemovesNothing`, `SyncTests.aStoreThatCantBeListedRemovesNothing`, `HistoryCommandTests.answersFromTheLastSyncWhenTheStoreIsAway`, `IndexTests.aChatCapturedAgainReplacesItself`, `IndexTests.survivesBeingReopenedAndStartsOverAfterAFormatChange`
- **Needs:** two chats stored in `~/qa-store`

**Steps**

1. Delete `~/.ambient/history/` (as a Mac that has never synced), then run `ambient history sync` in `qa-his`.
2. Run `ambient history sync` again.
3. Rename `~/qa-store` to something else and run `ambient history why README.md`.
4. Make an empty `~/qa-store` and run `ambient history sync`.

**Expected**

- Step 1 prints *2 new or changed, 0 removed; 2 chats and N cards indexed*.
- Step 2 prints *0 new or changed, 0 removed*.
- Step 3 still lists the recorded changes. If the last sync was more than ten minutes ago, it also warns that it couldn't reach the history store and is answering from what was fetched before; within ten minutes it doesn't try the store at all.
- Step 4 reports 0 removed, and `ambient history status` still shows 2 chats: a store that suddenly lists nothing doesn't empty the index.

### HIS-015 · `eval` scores retrieval on questions with known answers

- **Priority:** P2
- **Type:** both
- **Covers:** `Sources/AmbientHistory/HistoryEval.swift`, `Sources/ambient/HistoryCommand.swift`, `Sources/AmbientHistory/HistoryQuery.swift`
- **Automated by:** `PageAndEvalTests.scoresRetrievalAndAnswers`, `HistoryCommandTests.scoresAQuestionsFile`
- **Needs:** a chat stored in `~/qa-store`

**Steps**

1. Write `q.json` with one question whose `expectSession` is the start of the stored chat's id, and one whose `expectSession` is `nonexistent`.
2. Run `ambient history eval q.json`.

**Expected**

- One line per question: ✓ for the first, ✗ with *[not retrieved]* for the second.
- A last line *Retrieval: 1/2 questions found their chat in the first five cards.*
- Exit status 1, because one question failed. With only the first question, it exits 0.
- `--answers` without a Claude API key fails with *--answers needs a Claude API key*.

## Agents, pull requests and the app

### HIS-016 · An agent looks up why a file changed through `ambient mcp`

- **Priority:** P1
- **Type:** both
- **Covers:** `Sources/ambient/MCPServer.swift`, `Sources/ambient/HistoryCommand.swift`, `Sources/AmbientHistory/HistoryQuery.swift`
- **Automated by:** `HistoryMCPTests.listsTheHistoryToolsAsReadOnly`, `HistoryMCPTests.answersAnAgentsQuestionsAboutAFile`
- **Needs:** Claude Code with `ambient mcp`; the chat from HIS-006 stored

**Steps**

1. In a new Claude chat in `qa-his`, ask it to call `history_why` for `README.md`.
2. Ask it to call `history_search` for a few words from the stored chat's request.
3. Ask it to call `history_read` with the session id and the event range the card gave.
4. In a repository that isn't set up, ask it to call `history_why` for any file.

**Expected**

- Step 1 returns the same text as `ambient history why README.md`, with no colour codes.
- Step 2 returns the matching cards as `<card id="C1">` blocks and, under *Where to read each*, the `ambient history show` command for each.
- Step 3 returns those events as numbered lines.
- Step 4 returns an error result saying history isn't set up for that repository.
- None of the three tools asks a model, and all three are listed as read-only.

### HIS-017 · The pull-request comment links a chat and says nothing the chat said

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientHistory/PullRequestLinks.swift`, `Sources/AmbientHistory/HistoryStore.swift`, `Sources/AmbientHistory/HistoryPipeline.swift`, `Sources/AmbientHistory/Shell.swift`
- **Automated by:** `PullRequestLinkTests.thePublicLineSaysNothingTheChatSaid`, `PullRequestLinkTests.writesOneLinePerChatAndReplacesItsOwn`, `PullRequestLinkTests.createsUpdatesOrLeavesTheComment`, `PullRequestLinkTests.findsThePullRequestsHoldingAChatsCommits`, `PipelineTests.leavesALinkOnThePullRequestsThatHoldItsWork`, `StoreTests.talksToS3ThroughTheAWSCommand`, `StoreTests.readsABucketAddress`, `StoreTests.anEmptyBucketListsNothingAndAMissingToolSaysSo`, `StoreTests.namesAChatsFolderByRepositoryDayAndSession`
- **Needs:** a private S3 bucket and `aws` signed in; `gh` signed in; a repository on GitHub set up with `--store s3://BUCKET/PREFIX`; a finished Claude chat whose commit is in an open pull request

**Steps**

1. Run `ambient history capture --session <id> --no-model`.
2. Read the comment it left on the pull request.
3. Run the capture again and look at the pull request's comments.
4. Open the comment's link while signed in to the AWS console with access to the bucket, then in a private window.

**Expected**

- Step 1 prints the stored line, an `https://s3.console.aws.amazon.com/s3/object/BUCKET?region=…&prefix=…/page.html` address, and *Linked on pull request #N*.
- The comment is headed **Agent history** and has one line: *[claude chat of <date>](link) — N requests changed code*. It holds no title, no developer's name and nothing from the chat.
- After step 3 there is still exactly one such comment, with its original time: storing a chat again neither repeats nor rewrites it.
- Signed in, the link opens the object's page in the S3 console. In the private window it shows the AWS sign-in page and nothing about the chat.
- With `--no-links` on the capture, or on a repository set up with `--no-links`, no comment is written.

### HIS-018 · The app stores a chat when its session ends, without a dialog

- **Priority:** P0
- **Type:** both
- **Covers:** `Sources/AmbientApp/HistoryLauncher.swift`, `Sources/AmbientApp/AppModel.swift`, `Sources/ambient/HistoryCommand.swift`, `Sources/AmbientBase/SecretStore.swift`
- **Automated by:** `HistoryLauncherTests.aChatIsFinishedWhenItSaysSoOrItsAgentHasExited`, `HistoryLauncherTests.theAppHandsOverAChatWhenItsSessionEnds`, `HistoryLauncherTests.storesAFinishedChatAndLooksForQuietOnesHourly`, `HistoryLauncherTests.runsTheCommandLineToolAndKeepsALog`, `HistoryLauncherTests.startsNothingUntilARepositoryIsSetUp`, `HistoryLauncherTests.aChatOnAnotherMachineIsThatMachinesToStore`, `HistoryLauncherTests.anAppModelInATestHasNoLauncherAtAll`, `HistoryCommandTests.aCaptureTheAppStartedNeverAsksTheKeychain`
- **Needs:** Ambient.app running; `qa-his` set up; Claude Code connected

**Steps**

1. Start a Claude chat in `qa-his` from a terminal, ask it to change `README.md`, and wait for it to finish its turn. List `~/qa-store`.
2. Exit Claude (`/exit`). Wait ten seconds, then list `~/qa-store` and read `~/.ambient/logs/history.log`.
3. Start and end a Claude chat in a repository that isn't set up, and read the log again.

**Expected**

- After step 1 nothing new is in the store: a finished turn isn't a finished chat.
- After step 2 the chat's three files are in the store. The log has a time-stamped line `ambient history capture --session claude:<id> --quiet` followed by the *Stored* line.
- No Keychain permission dialog appears at any point. If the API key can't be read without one, the log says cards come from the chat's own words, and how to give permission once.
- Step 3 adds a capture line to the log and nothing to the store.
