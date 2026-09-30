# Feature requests: a public board on yaml.cafe, reachable from the app

Date: 2026-09-30
Status: design approved in chat in three parts ("looks good" ×2 and the header change); spec awaiting review

## Problem

People who try Ambient have no way to say what they want next, and we have no way to see which ideas
matter to many people. The site has one form (update emails); the app links only to a private GitHub repo
that visitors can't open.

## Goal

A public board at `https://yaml.cafe/requests/` where anyone can suggest a feature and vote on others',
without an account, and a way to reach it from the app. We can see demand at a glance, merge duplicates,
remove junk and mark what's planned and shipped.

Non-goals: accounts or sign-in; comments or threads; email notifications to us for each request (we check
with a command); an admin web page; showing the board inside the app.

## Decisions (from the chat)

| Topic | Decision |
| --- | --- |
| Kind of board | Public, with votes |
| When a request appears | Immediately; we remove or merge afterward |
| Identity | None. One vote per request per browser, plus per-network daily limits |
| Build | Our own: a static page, one Netlify edge function, Netlify Blobs (approach A). No third-party service |
| Voice | Personal. Header "What should Ambient bring you next?" |
| App | Opens the board in the default browser; the app itself makes no network requests |
| Cost | About 5 credits a month at 2,000 board visits; about 30 credits to launch (2 production deploys) |

## Design

### What people see

**`/requests/`** (new page, own `requests.css` and `requests.js`, sharing `styles.css` tokens):

- Header: **What should Ambient bring you next?** Sub-line: "Tell us what would make working with your
  agents better. Anyone can suggest or vote; no account needed."
- Suggest box: title field (placeholder "What would you like Ambient to do for you?", 3–80 characters),
  optional details (placeholder "Why it matters to you (optional)", up to 500 characters), button
  **Suggest it**. While the title is typed, up to three existing requests with similar titles appear under
  it: "Is it one of these? Vote instead." After posting: "Thanks! It's on the board, with your vote."
- List: tabs **Top** (votes, then newest) and **New** (newest first); status chips **All**, **Open**,
  **Planned**, **In progress**, **Shipped**. Each row: vote button with count (click again to take the vote
  back), title, details, status label when not open. Shipped items stay listed.
- Works at 375 px, keyboard and screen-reader operable (buttons are `<button>`, `aria-pressed` on votes),
  Lighthouse accessibility 100.
- Indexed and in the sitemap. User text is rendered with `textContent` only and links are stripped, so
  the page can't carry spam links.

**Links to the board:** "Requests" in the homepage nav and in every page's footer; a homepage FAQ entry
"How do I ask for a feature?" (also in the FAQPage JSON-LD); the contact page's "Feedback and feature
ideas" section; `llms.txt` Site section; `sitemap.xml`.

**In the app** (committed with tests; reaches users in the next app release):

- Menu bar menu: **Suggest a Feature…** just above **Settings…**.
- Settings › General › About: a **Feature requests** row, and the broken GitHub link replaced by
  **yaml.cafe**.
- Both open `https://yaml.cafe/requests/?from=app&v=<version>` with `NSWorkspace.shared.open`.

### Data (Netlify Blobs store `requests`)

| Key | Value |
| --- | --- |
| `items/<id>` | JSON `{ id, title, details, status, created, source, version, removed?, mergedInto? }`. `id` is 8 random base-36 characters. `status` is `open`, `planned`, `in-progress` or `shipped`. `source` is `app` or `site`; `version` is the app version from `?v=`, else empty |
| `votes/<id>/<voter>` | `"1"`. One key per vote, so concurrent votes never overwrite each other and a repeat vote rewrites the same key |
| `limits/<day>/<network>/<post\|vote>/<uuid>` | `"1"`. Counted by listing the prefix |

`<voter>` is the first 32 hex characters of SHA-256(`REQUESTS_SECRET` + `:voter:` + the browser's voter ID).
The voter ID is a random UUID the page keeps in `localStorage` (`ambient-voter`); no cookie.

`<network>` is the first 32 hex characters of SHA-256(`REQUESTS_SECRET` + `:` + day + `:` + the client IP
from the edge context). The day is part of the input, so the hash changes daily and can't be linked across
days or reversed to an IP. No IP is stored.

`REQUESTS_SECRET` is a Netlify environment variable (random 32 bytes, hex), also saved to the private
`secrets` repo under `ambient-notification/.env`.

### API (edge function `netlify/edge-functions/requests.ts`, path `/api/requests*`)

| Request | Behavior |
| --- | --- |
| `GET /api/requests` | Visible items (not removed, not merged) with vote counts. A merged item's voters count toward its target, once per voter. Cached at the edge for 30 s (`Netlify-CDN-Cache-Control: public, s-maxage=30`) |
| `POST /api/requests` | Body `{ title, details, source, version, voter, website, elapsedMs }`. Returns 201 with the new item, already carrying the poster's vote. The page adds it to its own list at once, since `GET` may be up to 30 s stale |
| `POST /api/requests/<id>/vote` | Body `{ voter }`. Adds the vote; 200 with the new count |
| `DELETE /api/requests/<id>/vote` | Body `{ voter }`. Removes the vote; 200 with the new count. Doesn't refund the daily vote limit |

Rules applied by `POST`:

- `website` (a hidden trap field) not empty, or `elapsedMs` (time since the page loaded, sent by the page) under 3,000: answer 201 with a fake item and
  store nothing, so bots learn nothing.
- Text is trimmed, whitespace collapsed, and anything matching `https?://\S+` or `www\.\S+` removed. Title
  must then be 3–80 characters; details up to 500. Otherwise 400 with a plain message.
- More than 3 posts, or 50 votes, from one network today: 429 with "You've suggested 3 things today. Thank
  you! Try again tomorrow." (or the vote equivalent).
- Unknown `<id>` on a vote: 404.

The markdown edge function adds `/api/*` to its `excludedPath` so the two never chain.

The page tracks `Request posted` (with `from`) and `Vote` in Umami. It keeps the set of IDs it has voted
for in `localStorage` (`ambient-votes`) to show its own votes; the server is the source of truth for counts.
Clearing storage lets a browser vote again, within the network's daily limit; that's the accepted trade-off
of having no accounts.

### Moderation (`scripts/requests.sh`, uses `netlify blobs:*`; no deploys, so no credits)

| Command | Does |
| --- | --- |
| `requests.sh new` | Requests created since the last run (timestamp kept in `.netlify/requests-last-seen`, git-ignored), then prunes `limits/` older than yesterday |
| `requests.sh list` | All visible requests, by votes |
| `requests.sh remove <id>` | Sets `removed: true` (record and votes kept) |
| `requests.sh merge <id> <into>` | Sets `mergedInto`; the board adds its voters to the target, once each |
| `requests.sh status <id> <open\|planned\|in-progress\|shipped>` | Sets the status |

### Privacy notice

A new "Feature requests" section: what you write is public; a vote is tied only to a scrambled random ID
your browser keeps; daily limits use a network hash whose secret changes every day; no IP address, cookie
or email is stored; email us to have a request removed. "Last updated" moves to the ship date.

### Units

| Unit | Job | Tested by |
| --- | --- | --- |
| `netlify/edge-functions/lib/requests-core.ts` | Pure: clean and validate a submission, tally votes with merges, visible items and sort, limit checks | `requests-core.test.ts`, Node's test runner via `tsx` (dev dependency) |
| `netlify/edge-functions/requests.ts` | HTTP, hashing, Blobs reads and writes | End-to-end on a draft deploy |
| `site/requests/similar.js` | Pure ES module: similar titles (lowercase words of 3+ letters, overlap ≥ 0.5, top 3) | `similar.test.mjs`, Node's test runner |
| `site/requests/requests.js` | Board UI | Browser checks |
| `AmbientCore/FeatureRequests.swift` | `FeatureRequests.url(version:)` | `FeatureRequestsTests` |
| `MenuBarController`, `GeneralPane` | The two entry points | Build and a manual click |

## Testing and rollout

1. Unit tests for `requests-core`, `similar` and `FeatureRequests` pass (`npm test`, `swift test`).
2. Draft deploy; with `curl`: post, vote, un-vote, repeat vote (no double count), trap field, too-fast
   submit, 4th post (429), link stripping, merge and remove through the script. All test data uses titles
   starting `qa-` and is deleted afterward.
3. Browser: the board at desktop and 375 px, keyboard voting, Lighthouse (all 100), is-agentic unchanged.
4. Production: one deploy for the board and links, a second only if fixes are needed.

## Coordination

Another session is editing the homepage, `styles.css`, `scene.js` and the app's settings window
(`AppDelegate`, `SettingsPane`, `SettingsView`). The board keeps its own CSS and JS; homepage edits are
limited to the nav link, footer link and FAQ entry, made last against a fresh read. App edits touch only
`MenuBarController`, `GeneralPane` and new files. Commits stage named files only.
