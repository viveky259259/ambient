# Show HN and Product Hunt: for approval

Written as you, the developer. You post both; nothing here has been submitted. Facts checked against the code and the site on 2026-10-09 (version 0.5.1).

Post them on different days so you can answer every comment. Hacker News first: its readers find bugs, and you'll want them fixed before Product Hunt.

## Show HN

**Where:** https://news.ycombinator.com/submit (log in first). A weekday at about 9 AM US Eastern (6:30 PM IST). Stay for the first two hours: replying quickly and plainly matters more than the post itself.

**Title** (the limit is 80 characters; pick one):

1. `Show HN: Ambient – Mac notch status for Claude Code, Codex and Gemini CLI` (73)
2. `Show HN: A Mac notch light that tells you when your coding agent needs you` (74)

**URL:** `https://yaml.cafe/?ref=hn`

Leave the text box empty, since a submission with a URL shows no text. Post the comment below as the first comment as soon as the submission is up.

### First comment

> I run Claude Code and Codex in several terminals at once, and what kept costing me time was a session sitting on a permission prompt in a tab I wasn't looking at.
>
> Ambient is a free macOS app that listens to the hooks each agent already has and shows one state at the notch: working, needs you, done or error. It posts a notification only when you aren't already in the app running that agent. A click on the notification or the island opens the exact Terminal or iTerm2 tab, tmux pane, or Claude or Codex desktop chat.
>
> How it works:
>
> - Connect adds entries to ~/.claude/settings.json, ~/.codex/hooks.json and ~/.gemini/settings.json, after backing each file up. `ambient uninstall` removes only its own entries.
> - Each hook runs a small native binary that sends one line over a Unix socket and always exits 0. It takes about 15 ms and runs async for Claude Code and Codex, so it can't slow or fail a session. If the app isn't running, the event is dropped.
> - For permissions it uses Claude Code's PermissionRequest hook, which fires immediately. The built-in Notification event waits about 6 seconds. Details: https://yaml.cafe/guides/claude-code-permission-notification/
> - The app makes no network requests, and it has no account and no telemetry. It's Swift, SwiftUI and AppKit, for macOS 14+ on Apple silicon and Intel, and it's notarized.
>
> What it doesn't do: you can't approve a permission from the notch; it takes you to the session to answer. The agent also has to run on the same Mac, so it doesn't work over SSH.
>
> If you'd rather not install anything, the guides on the site show how to get part of this from hooks alone: a sound on Stop, the tmux bell, a PermissionRequest script.
>
> I'd like to hear what breaks, which terminal or agent to support next, and whether the notch is the right place for this at all.

### Replies to have ready

- **"Is it open source?"** Decide before you post; HN will ask within the hour.
  - If you make the repo public: "Yes: <repo link>. The hook binary and the installer are the parts worth reading."
  - If not: "Not right now. The hooks it installs are plain JSON in your settings files, and `ambient uninstall` removes them. Nothing leaves your Mac: the app makes no network requests."
- **"How is this different from Vibe Island / Claude Island / other notch apps?"** "There are several now. I keep a dated comparison that says where the others do better: https://yaml.cafe/guides/claude-code-notification-apps-mac/. In short, Vibe Island covers many more agents and lets you approve from the notch, but it's paid. Ambient is free, covers Claude Code, Codex and Gemini CLI, and focuses on getting you back to the exact tab or pane."
- **"Why not terminal-notifier or osascript in a hook?"** "That works, and the guide shows how. Ambient adds state while the agent works, many sessions at once sorted by urgency, and the click back to the exact pane."
- **"What does the hook send?"** "Agent, state, project name and a trimmed message, over a Unix socket on your Mac. Prompts and tool output aren't stored."
- **"No notch?"** "On other displays the island sits at the top center of the menu bar."
- **"Linux or Windows?"** "macOS only. It's built on the notch, the Dock and AppKit."

## Product Hunt

**Where:** https://www.producthunt.com/launch. The day starts at 12:01 AM Pacific, which is 12:31 PM IST until US clocks change on November 1 (1:31 PM IST after). Tuesday to Thursday has the most visitors and the most competition; a weekend is quieter but easier to place on.

Consider launching after the desktop pet ships. Product Hunt rewards things that look delightful in a gallery, and the pet is the most visual thing Ambient has.

| Field | Value |
| --- | --- |
| Name | Ambient |
| Tagline (60 max) | `Your Mac's notch shows what your coding agents are doing` (56) |
| Alternate taglines | `Know when Claude Code or Codex needs you, at the notch` (54) · `A notch status light for Claude Code, Codex and Gemini CLI` (58) |
| Website | `https://yaml.cafe/` (Product Hunt adds `?ref=producthunt` itself) |
| Pricing | Free |
| Topics | Mac, Developer Tools, Artificial Intelligence, Productivity |
| Thumbnail | `site/assets/icon-256.png`, resized to 240×240 |
| Video | `marketing/out/film/ambient-16x9.mp4`, uploaded to YouTube (unlisted is fine) and pasted as a link |

**Description** (the first 260 characters show in the preview; this is 257):

> Ambient shows what Claude Code, Codex and Gemini CLI are doing at your Mac's notch: working, needs you, done or error. It chimes only when it matters, and one click takes you back to the exact terminal tab or chat. Free, no account, nothing leaves your Mac.

### Gallery: still to make

3 to 5 images at 1270×760. The film stills in `marketing/out/film/stills/` catch the captions mid-fade, so they need fresh frames or real screenshots:

1. The island blooming amber: "api-server needs permission"
2. Green "done" with the click back to the terminal tab
3. The Dock glow
4. The living wallpaper with sessions as stars or planets
5. Welcome › Connect All

### Maker comment (post it right after launch)

> Hi Product Hunt! I built Ambient because my coding agents kept waiting on me in terminals I wasn't watching.
>
> It listens to the hooks Claude Code, Codex and Gemini CLI already have, and turns them into one color at the notch: the agent's own color while it works, amber when it needs you, green when it's done, red on an error. You get a notification and a soft chime only when you're not already looking, and a click takes you to the exact terminal tab, tmux pane or chat.
>
> Across the room, the Dock glows in the same color. And if you like, your desktop becomes a living wallpaper where each session is a star, a boat, a plant or a planet.
>
> It's free with every feature, needs no account, and makes no network requests. macOS 14+, Apple silicon and Intel.
>
> What should it do next? Tell me here, or vote on the board: https://yaml.cafe/requests/

Don't ask anyone to upvote, here or elsewhere; Product Hunt penalizes it. "We're live on Product Hunt, I'd love your feedback" is fine.
