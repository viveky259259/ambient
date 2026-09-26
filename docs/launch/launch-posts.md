# Ambient launch posts — for approval

Every post is written as you, the developer, and says so. Nothing is posted until you approve it, and each Reddit post gets a live rules check in Chrome right before it goes up. Posts that fail the check are skipped and reported.

Assets: `marketing/out/film/ambient-16x9.mp4` (X, Reddit), `ambient-1x1.mp4` (LinkedIn), `ambient-9x16.mp4` (spare), captions in `captions.srt`.

## X — launch thread (video on post 1)

**1/5**

> Your Mac, aware of your coding agents.
> 
> Ambient shows what Claude Code, Codex and Gemini CLI are doing, right at the notch. Coral while it works. Amber when it needs you. Green when it's done.
> 
> Free for macOS.

**2/5**

> The problem: an agent stops for permission in a terminal you're not watching, and you find out ten minutes later.
> 
> Ambient hooks every lifecycle event (about 15 ms, never slows the agent) and turns it into one signal you can read at a glance.

**3/5**

> It speaks up only when it matters: a banner and a soft chime for needs you, done or error, and never while you're already in the app running the agent.
> 
> Click, and you're back in the exact chat, terminal tab or tmux pane.

**4/5**

> Across the room? The Dock glows in the color of what your agents are doing.
> 
> And nothing leaves your Mac: no accounts, no network, no telemetry.

**5/5**

> Free for macOS 14+: https://yaml.cafe
> 
> Built with Claude Code. I'd love your feedback, especially if you run several agents at once.

## LinkedIn — one post (1:1 video)

> I just launched Ambient, a free Mac app for developers who work with AI coding agents.
> 
> The problem I kept running into: Claude Code, Codex or Gemini CLI would stop to ask for permission in a terminal I wasn't looking at. Ten minutes lost, every time.
> 
> Ambient makes agent state ambient:
> • A notch island: coral while an agent works, amber when it needs you, green when it's done, red on errors
> • Notifications and soft chimes, only when you're not already looking
> • One click back to the exact chat, terminal tab or tmux pane
> • A glow along the Dock you can see from across the room
> • Private by design: no accounts, no network, no telemetry
> 
> Under the hood: native hooks that take about 15 ms and never slow the agent, a local Unix socket, and a SwiftUI app that uses the new Liquid Glass design.
> 
> It's free for macOS 14+ at https://yaml.cafe. I'd love to hear what you think, especially if you run several agents at once.
> 
> #AI #DeveloperTools #macOS #ClaudeCode #Productivity

## Reddit — 20 posts, one per hour

The Reddit Post Advisor scored every draft *strong* (100/100) with no blockers. Its rule profiles date from 2026-09-13, so each community's current rules, flair and account requirements are checked live before posting.

### 1. r/ClaudeAI

- Route: Standalone post · flair: Built with Claude
- Advisor: quality strong 100/100; rules to verify live

**I built a Mac notch island that shows what Claude Code is doing and lights up when it needs permission**

I kept losing time to one thing: Claude Code would stop for a permission prompt in a terminal I wasn't looking at, and I'd find it ten minutes later.

So I built Ambient, a free macOS app. It registers Claude Code hooks (prompt submitted, tool started/finished, permission requested, turn finished or failed) and turns them into a small island that grows out of the notch: a coral orb while Claude works, amber when it needs you, green when it's done. It also posts a notification with a soft chime, but only when you're not already in the app running Claude.

How Claude fits in: the hooks run in the background and exit in ~15 ms, so they never slow a session down. Clicking the island opens the exact chat in the Claude desktop app (or the Terminal/iTerm2 tab, tmux pane, or editor window). Nothing leaves your Mac. Claude Code also helped me write much of the Swift.

I'm the developer. It's free: https://yaml.cafe

What would you want it to show for long-running sessions?

### 2. r/ClaudeCode

- Route: Standalone post · flair: Showcase
- Advisor: quality strong 100/100; rules to verify live

**Stop babysitting Claude Code: a notch indicator for permission prompts, finished turns and errors**

If you run Claude Code in a few terminals at once, you know the loop: switch tabs to check whether it's waiting on you.

I made Ambient to end that. It adds Claude Code hooks for each lifecycle event and shows the state at the Mac's notch: working, needs you (permission or a question), done, or error. When something changes the island blooms open for a few seconds with the project and the tool it's waiting on, e.g. "api-server: Needs permission, Bash: rm -rf build". Click it and you're back in the exact tab or pane.

Details people usually ask about:
- Hooks run async and exit in ~15 ms; if the app isn't running, events are dropped.
- The installer only adds its own entries to ~/.claude/settings.json and keeps a backup.
- `ambient doctor` checks the whole chain.

I built it; it's free for macOS 14+: https://yaml.cafe

Question for heavy users: do you want a sound for every finished turn, or only for permission prompts?

### 3. r/ChatGPTCoding

- Route: Standalone post · flair: Resources And Tips
- Advisor: quality strong 100/100; rules to verify live

**A small fix for the worst part of agentic coding: not noticing when the agent is waiting on you**

With Claude Code, Codex and Gemini CLI all running tasks in the background, my biggest time sink wasn't the agents. It was not noticing when one of them stopped to ask a question.

What worked for me was making agent state ambient instead of something I have to check:

1. Hook every lifecycle event (prompt, tool start/stop, permission request, turn end or failure).
2. Reduce each to a mood and pick the most urgent across sessions: needs you > error > done > working.
3. Show it where I'm always looking: the notch and the menu bar, plus a light along the Dock.
4. Only notify when I'm not already in the agent's app.

I packaged this as a free Mac app called Ambient (I'm the developer): https://yaml.cafe

How do you keep track of several agents at once? Terminal bells, tmux alerts, something else?

### 4. r/buildinpublic

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live

**Building an agent notifier taught me the best notification is the one you don't send**

I'm building Ambient, a Mac app that shows what coding agents (Claude Code, Codex, Gemini CLI) are doing at the notch.

The first version notified on everything and was unbearable within an hour. What I changed:

- No banner if you're already in the app running the agent. You can see it.
- Finished turns only notify if they ran longer than 20 seconds (configurable).
- A "done" state stays green until you actually look at that session, then settles on its own.
- A banner withdraws itself once you've answered the prompt.

The result feels quieter even though it knows more. This week I shipped 0.2.0 with a redesigned settings window and a waitlist-gated download to see who actually installs it.

Real numbers so far: it's free, launched today, zero users beyond me. I'll post what the waitlist shows.

Site: https://yaml.cafe

What's a notification rule you wish every app had?

### 5. r/devtools

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live

**Ambient: see whether your coding agents are working, waiting or done without switching windows (macOS)**

The problem: agent CLIs stop for permission prompts, and unless you're watching that terminal you won't know. With three sessions going, you end up tab-cycling.

Ambient fixes it with hooks plus a status surface:
- Hooks for Claude Code, Codex and Gemini CLI reduce each event to a few fields and send one line over a local Unix socket (~15 ms, always exits 0).
- The app folds events into per-session state and shows the most urgent one at the notch, in the menu bar and as a glow along the Dock.
- Clicking a session returns you to the exact place it runs: Claude desktop chat, Codex thread, Terminal/iTerm2 tab, tmux or cmux pane, or the editor window.

No accounts, no network, no telemetry. I'm the developer; it's free for macOS 14+: https://yaml.cafe

Feedback I'm after: which terminals or editors should click-to-return support next?

### 6. r/AI_Agents

- Route: Standalone post · flair: Discussion
- Advisor: quality strong 100/100; rules to verify live

**How should a coding agent ask for your attention without becoming noise?**

I've been working on this problem for agent CLIs (Claude Code, Codex, Gemini CLI) and landed on a policy I'd like critiqued.

Each session is reduced to one mood, and the UI shows only the most urgent across all sessions: needs you > error > done > working > idle.

- Needs you: persistent amber until the prompt is answered; one banner and chime, but only if you're not already in the host app.
- Error: red until you look at that session.
- Done: green until you look; short turns (<20 s) don't notify at all.
- Working: a quiet breathing indicator, no sound ever.

The agent never gets approval through this path. Consent stays in the terminal; the indicator only tells you where to go.

Open questions:
1. Should "error" outrank "needs you" when both happen?
2. Is "stays green until you look" right, or should done decay on a timer?

Disclosure: I implemented this as a free Mac app, Ambient (https://yaml.cafe), but I'm mostly interested in the policy.

### 7. r/LLMDevs

- Route: Standalone post · flair: Tools
- Advisor: quality strong 100/100; rules to verify live

**Hooking agent CLIs without slowing them down: 15 ms hooks, a Unix socket and per-session state**

Implementation notes from building a status indicator for Claude Code, Codex and Gemini CLI on macOS.

Constraint: a hook must never slow the agent or fail its run.

What worked:
- The hook is a small native binary. It reads the event JSON from stdin, reduces it to a handful of fields (agent, session id, event kind, tool name, a message trimmed to a UTF-8-safe length) and writes one line to ~/.ambient/ambient.sock.
- It always exits 0. For Claude Code and Codex it runs async. It takes about 15 ms; if the app isn't running, the event is dropped.
- The app folds events into per-session state with a priority order and ages out sessions whose agent process has exited.
- The installer edits settings.json/hooks.json while preserving key order, symlinks, permissions and other tools' hooks, with a backup.

Limitations: Codex asks you to trust new hooks via /hooks; there's no Windows or Linux version.

The app is Ambient, free (I'm the developer): https://yaml.cafe. What would you measure beyond hook latency?

### 8. r/AgentsOfAI

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live

**Human-in-the-loop fails when the human doesn't notice the loop**

Permission prompts are the main safety control in coding agents: the agent stops and asks before running a risky command. But that control has a failure mode nobody talks about. If you don't notice the prompt, the agent just waits, and people respond by switching on broad auto-approve to avoid babysitting.

My take: make the pause visible, not the approval easier.

What I built (Ambient, a free macOS app; I'm the developer): hooks report each agent's state, and the notch shows an amber pulse the moment Claude Code, Codex or Gemini CLI asks for permission. A real example: when Claude Code stops on "Bash: rm -rf build", the island turns amber within the hook's ~15 ms and shows that exact command. It never approves anything. Clicking only takes you to the terminal or chat where the prompt is, so the decision stays with you and stays in context.

https://yaml.cafe

Do you think better visibility would make you use auto-approve less?

### 9. r/OpenAI

- Route: Standalone post · flair: Project
- Advisor: quality strong 100/100; rules to verify live

**Codex CLI and Codex app: a notch indicator that shows when a Codex thread needs you**

I built a small Mac app, Ambient, that uses Codex's hooks to show session state at the notch: working, needs you, done or error.

Codex-specific details:
- It registers hooks in ~/.codex/hooks.json. Codex asks you to trust new hooks, so you run /hooks once and approve them.
- Clicking a Codex session opens the exact thread in the Codex app (codex://threads/…), or the terminal tab if you run the CLI.
- It recognizes sessions started from the Codex app even though that app doesn't pass its bundle id to hooks.

Measured on my Mac, the hook takes about 15 ms and always exits successfully, so a Codex run is never held up by it. It also works with Claude Code and Gemini CLI. I'm the developer, it isn't affiliated with OpenAI, and it's free: https://yaml.cafe

Codex users: what else would you want surfaced from a running thread?

### 10. r/IMadeThis

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live
- **Note:** r/IMadeThis asks for a human-written description; edit it in your voice before approving.

**I made a notch island for my Mac that tells me when my AI coding agents need me**

Ambient sits at the MacBook notch. A coral orb breathes while Claude Code is working, it turns amber and chimes when it needs permission, and green when the task is done. There's also a glow along the Dock you can see from across the room.

Click it and you're back in the exact terminal tab or chat.

Free for macOS 14+: https://yaml.cafe

One question: would you rather it show only the agent that needs you, or every running session?

### 11. r/indiehackers

- Route: Standalone post · flair: Self Promotion
- Advisor: quality strong 100/100; rules to verify live

**Launched Ambient today: a free Mac app for people who run AI coding agents**

Stage: launched today, 0 users besides me, free, no revenue plan yet.

What it is: a macOS app that shows what Claude Code, Codex and Gemini CLI are doing at the notch, in notifications and along the Dock, and takes you back to the exact session with one click.

Why free: I want to learn whether this is a daily-use tool before deciding anything about pricing. The download asks for a name and email (a waitlist), which is the one metric I'll trust: how many people bother to install it.

What I'd love feedback on:
1. Is gating a free download behind a waitlist form going to kill conversion?
2. Would you pay for a team version (shared agent status)?

https://yaml.cafe

### 12. r/launch

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live

**Ambient: your Mac, aware of your coding agents (free, macOS)**

Ambient turns what Claude Code, Codex and Gemini CLI are doing into calm signals:

- Notch island: coral while working, amber when it needs you, green when done, red on errors.
- Notifications and soft chimes, only when you're not already looking.
- Click to return to the exact chat, terminal tab, tmux pane or editor window.
- A Dock glow in the color of your agents' state.
- Private: no accounts, no network, no telemetry.

Free for macOS 14+. I'm the developer: https://yaml.cafe

Which agent should I support next?

### 13. r/automation

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live

**Automating the "is my agent done yet?" check with hooks and a Mac status light**

A small automation that saved me a lot of tab-switching: every time a coding agent (Claude Code, Codex, Gemini CLI) changes state, a hook sends one line to a local app, and the app updates a status light at the notch.

Each hook takes about 15 ms and sends one line over a local Unix socket, so it never slows the agent. The states map to colors: working (agent color), needs you (amber), done (green), error (red). Chimes play only for the three that need a human, and only when I'm not already in the agent's app. A finished session stays green until I look at it.

There's a CLI too: `ambient status` prints every session and `ambient open` jumps to the one that needs you most, so you can bind it to a hotkey.

It's a free Mac app I built, Ambient: https://yaml.cafe

What other long-running jobs would you want on the same light: CI runs, builds, deploys?

### 14. r/AI_Programming

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live

**My workflow for running several AI coding agents at once without watching terminals**

I usually have two or three agent sessions going: Claude Code on one repo, Codex on another. The workflow that stuck:

1. Give each agent a clear task and walk away to review or write code yourself.
2. Let a status indicator tell you when a session needs a decision (permission prompt or question), instead of polling tabs.
3. When it pings, click straight into that exact tab or tmux pane, answer, and leave again.
4. Review finished sessions in the order they went green.

For step 2 I built Ambient, a free Mac app that reads agent hooks and shows state at the notch and in the menu bar (disclosure: it's mine): https://yaml.cafe

How do you split attention across agents? Do you cap how many run in parallel?

### 15. r/appledevelopers

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live

**Feedback wanted: Ambient, a notch island for AI coding agents (SwiftUI + AppKit, macOS 14+)**

What it is: a free macOS app that shows what coding agents (Claude Code, Codex, Gemini CLI) are doing at the notch, in notifications and along the Dock.

Tools: the Swift 6 toolchain, SwiftUI for the island and settings, AppKit for the panels and status item, Core Animation for the orb so hours of breathing cost nothing per frame, UserNotifications, SMAppService for login items. Settings use Liquid Glass on macOS 26 with a material fallback.

Lessons:
- Finding the notch: NSScreen.auxiliaryTopLeftArea/RightArea give you its exact width; fall back to a virtual notch on other displays.
- Signing a helper while agent hooks are executing it fails with an I/O error, so the build signs in a staging folder and swaps.

Feedback I'd like: does the settings window feel native to you? Anything that looks off on your display?

https://yaml.cafe

### 16. r/macosprogramming

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live

**Drawing a Dynamic-Island-style panel around the MacBook notch: what worked**

Notes from building a notch island on macOS 14+, in case they're useful.

- Geometry: on notched displays, `safeAreaInsets.top` gives the notch height, and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` bound it horizontally. Normalize them to global coordinates on multi-display setups.
- Window: a borderless non-activating NSPanel above the menu bar, sized once for the largest state, so it never resizes. The SwiftUI view animates its shape inside it.
- Hit testing: the panel is click-through except for the visible pill; otherwise you block the menu bar.
- Animation: the orb's breathing runs as a CABasicAnimation on the render server, so it costs no CPU per frame for hours.
- Other displays: a virtual notch centered in the menu bar.

Open question: has anyone found a cleaner way than polling to detect the menu bar hiding in full-screen apps?

(This is from Ambient, a free app I made: https://yaml.cafe)

### 17. r/macapps

- Route: Comment in the current self-promotion megathread
- Advisor: quality strong 100/100; rules to verify live

**(comment in the current self-promotion megathread)**

**Ambient**: your Mac, aware of your coding agents. Free, macOS 14+.

Shows what Claude Code, Codex and Gemini CLI are doing: a notch island (working / needs you / done / error), notifications with soft chimes only when you're not already looking, a Dock glow, and click-to-return to the exact chat, terminal tab or tmux pane. No accounts, no network, no telemetry. Notarized DMG.

I'm the developer. https://yaml.cafe

Which agent or terminal should it support next?

### 18. r/SideProject

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live

**My side project: a Mac notch island that tells you when your AI coding agent needs you**

Ambient is a free macOS app for anyone who runs Claude Code, Codex or Gemini CLI. Instead of checking terminals, you glance at the notch: coral means working, amber means it needs your permission, green means done. It chimes only when you're not already in the agent's app, and one click takes you back to the exact session.

Where it stands: v0.2.0, a 2.6 MB notarized download, 148 passing tests, hooks that take about 15 ms, launched today with zero users besides me.

What I'd like feedback on: the landing page asks for a name and email before the download (a waitlist). Would that stop you from trying it?

https://yaml.cafe

### 19. r/IndianProgrammers

- Route: Standalone post
- Advisor: quality strong 100/100; rules to verify live

**Built a macOS app that shows when Claude Code or Codex needs you: what I learned about agent hooks**

I build developer tools, and this one came from my own frustration: running Claude Code and Codex in parallel and missing their permission prompts.

Ambient hooks into each agent's lifecycle events and shows the state at the MacBook notch. The learning that surprised me: the hook is the hard part. It has to be fast (~15 ms), never fail the agent's run, and survive agents being updated. So it's a tiny native binary that sends one line over a Unix socket and always exits successfully, and the app repairs its own hook entries if an update changes them.

Free for macOS 14+: https://yaml.cafe (I'm the developer.)

Anyone else building on top of agent CLIs? What broke for you?

### 20. r/developersIndia

- Route: Showcase Sunday only · flair: I Made This
- Advisor: quality strong 100/100; rules to verify live
- **Hold:** Your own words needed: r/developersIndia asks for human-written copy and no install/waitlist objective. Post only if you rewrite it yourself, on a Sunday (Showcase Sunday).

**I made a notch indicator for macOS that shows when your AI coding agent is waiting for you**

Ambient watches Claude Code, Codex and Gemini CLI through their hooks and shows each session's state at the notch: working, needs you, done or error. One click takes you back to the exact terminal tab or chat.

Tech: Swift, SwiftUI and AppKit, a native hook binary that talks to the app over a Unix socket (~15 ms per event), and no network access at all.

Free for macOS 14+: https://yaml.cafe

I'm happy to go into the code design in the comments.

For people running agents in tmux: would a status-line integration be more useful than the notch?

### Alternates if a community's live rules rule it out

r/commandline, r/tmux, r/vibecoding, r/GeminiCLI, r/IndianStartups
