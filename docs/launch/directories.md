# Directory and list entries: ready to paste

Each entry follows that site's current rules, checked on 2026-10-09. Nothing here has been submitted. Opening the awesome-mac pull request is the only one Claude can do for you, and only once you say yes; the others need your own account and must be filed by you.

| Where | Who submits | Odds | Notes |
| --- | --- | --- | --- |
| awesome-mac | Claude, with your OK | Good | Lists free closed-source apps; Agent Island, a notch app for Claude Code and Codex, is already in Menu Bar Tools |
| AlternativeTo | You (needs an account) | Good | Listed next to Vibe Island and Notch Pilot, it shows up when people look for alternatives to them |
| MacUpdate | You (developer account) | Fair | Current process unconfirmed; the sources found are old |
| awesome-claude-code | You, through its web form only | Low for now | Closed source is a review barrier; see the caveats below |

## awesome-mac (jaywcjlove/awesome-mac)

A pull request that adds one line under **Utilities › Menu Bar Tools** in all four READMEs, in alphabetical order. The repo asks for one PR per app, AP title case, and the same entry in each language.

**README.md**, after AirPoise and before Anvil:

```markdown
* [Ambient](https://yaml.cafe/) - Shows what Claude Code, Codex and Gemini CLI are doing at the MacBook notch, with alerts and one click back to the exact terminal tab or chat. ![Freeware][Freeware Icon] ![Native App][Native Icon]
```

**README-zh.md**, after AirPoise and before Anvil:

```markdown
* [Ambient](https://yaml.cafe/) - 在 MacBook 刘海处显示 Claude Code、Codex 与 Gemini CLI 的运行状态，配合通知，一键回到对应的终端标签页或对话。 ![Freeware][Freeware Icon] ![Native App][Native Icon]
```

**README-ja.md**, after AirPoise and before Anvil:

```markdown
* [Ambient](https://yaml.cafe/) - Claude Code、Codex、Gemini CLIの状態をMacBookのノッチに表示し、通知とワンクリックで該当するターミナルタブやチャットに戻れるアプリ。 ![Freeware][Freeware Icon] ![Native App][Native Icon]
```

**README-ko.md**, after AirStats and before Anvil:

```markdown
* [Ambient](https://yaml.cafe/) - MacBook 노치에 Claude Code, Codex, Gemini CLI의 상태를 보여주고, 알림과 한 번의 클릭으로 해당 터미널 탭이나 채팅으로 돌아가게 해 주는 앱. ![Freeware][Freeware Icon] ![Native App][Native Icon]
```

**PR title:** `Add Ambient to Menu Bar Tools`

**PR body:**

> Adds Ambient, a free native macOS app that shows the state of Claude Code, Codex and Gemini CLI sessions at the notch (on other displays, at the top center of the menu bar), with notifications and one click back to the session. Free with every feature, no account. Added to README.md, README-zh.md, README-ja.md and README-ko.md in alphabetical order. I'm the developer.

## AlternativeTo

Sign in, then choose **Suggest new application** from the user menu. To appear as an alternative, open each app's page, choose **Suggest Alternatives**, and pick Ambient.

| Field | Value |
| --- | --- |
| Name | Ambient |
| Website | `https://yaml.cafe/` |
| Platforms | Mac |
| License | Free (proprietary) |
| Category | Development |
| Tags | claude-code, ai-coding-agent, notifications, menu-bar, notch, codex, gemini-cli, developer-tools |
| Alternative to | Vibe Island, Notch Pilot (both listed there today); also Claude Island, Vibe Notch and AI Done Now if they're listed |
| Screenshots | The same gallery images as Product Hunt |

**Short description:**

> Shows what Claude Code, Codex and Gemini CLI are doing at your Mac's notch, and takes you back to the session that needs you.

**Long description:**

> Ambient is a free macOS app for people who work with AI coding agents. It listens to the hooks Claude Code, Codex and Gemini CLI already provide and shows each session's state at the notch: working, needs you, done or error. It posts a notification with a soft chime only when you're not already in the agent's app, and a click opens the exact Terminal or iTerm2 tab, tmux or cmux pane, editor window, or chat in the Claude or Codex desktop app. The Dock glows in the color of what your agents are doing, and an optional living wallpaper shows every session as a star, a boat, a plant or a planet.
>
> Hooks take about 15 ms and never slow an agent down. No account, no network requests, no telemetry. macOS 14 or later, Apple silicon and Intel.

## MacUpdate

The only sources found on how to submit are old. Look for the developer or "submit an app" link on macupdate.com, and if they offer it, let them track new versions.

| Field | Value |
| --- | --- |
| Name | Ambient |
| Version | 0.5.1 |
| Developer | yaml.cafe |
| Category | Developer Tools |
| Price | Free |
| Requirements | macOS 14 or later, Apple silicon and Intel |
| Size | 3.9 MB |
| Download | `https://yaml.cafe/downloads/Ambient-0.5.1.dmg` |
| Homepage | `https://yaml.cafe/` |

Use the AlternativeTo long description. **What's new in 0.5.1:**

> With the living wallpaper on the lock screen, the password field could be hidden; fixed. On Macs without a notch, the island now sits on the display with the menu bar, opens from the top center even with no agent running, and draws the black hole and the sun at full size.

## awesome-claude-code (hesreallyhim/awesome-claude-code)

Recommendations go only through the issue form in the web UI, filed by a person. A PR, a `gh` command or an agent-made issue can get you restricted from the repo. Form link: https://github.com/hesreallyhim/awesome-claude-code/issues/new?template=recommend-resource.yml

**Before you file, three caveats:**

1. The maintainer says closed source is a barrier to review, and recommends getting users first and submitting later.
2. The checklist asks you to confirm that the resource is specific to Claude Code. Ambient also supports Codex and Gemini CLI. Check that box only if you're comfortable saying so; the guidelines call Claude Code focus a preference, not a rule.
3. Eligibility is 14 days since the first commit plus active development, or 100 stars. The first commit was 2026-09-26, so it qualifies from 2026-10-10.

My suggestion: file it once the repo is public, or once Ambient has visible users.

| Field | Value |
| --- | --- |
| Display Name | Ambient |
| Category | Remote Control, Notifications & Voice I/O |
| Link | `https://yaml.cafe/` (or the GitHub repo, if public) |
| Author Name | Vivek Yadav |
| Author Link | `https://github.com/viveky259259` |

**Description** (descriptive, one line, no emoji, 10–500 characters; this is 393):

> A native macOS app that turns Claude Code hook events into session status at the MacBook notch, the menu bar and the Dock, with notifications for permission requests, finished turns and errors, and a click that opens the exact Terminal or iTerm2 tab, tmux pane or Claude desktop chat. Hooks run async in about 15 ms; the app makes no network requests. It also reads Codex and Gemini CLI hooks.
