# Launch: 0.2.0, yaml.cafe, marketing assets and posting

Date: 2026-09-26
Status: approved in chat

## Decisions

- Landing page on the root domain **yaml.cafe** (Hostinger registrar), hosted on Netlify.
- Ship **0.2.0** (the new settings window) before launch; the site serves its DMG.
- Narration: **Kokoro-82M-8bit via MLX** (`af_heart`), from
  `~/Documents/Projects/offline-whiteboard-video-studio/pocs/open-tts`, offline.
- Reddit: **20 posts, one per hour**, drafted with the Reddit Post Advisor
  (`~/Documents/Projects/reddit_model`), approved by the user post by post, posted by Claude from the
  user's signed-in Chrome.

## Part 1 — Release and site

### 0.2.0

Merge `feat/settings-redesign`, set `AmbientVersion.current = "0.2.0"`, date the CHANGELOG section,
`NOTARY_PROFILE=MomentumAI scripts/release.sh`, tag `v0.2.0`, GitHub release (repo is private; the site
is the public download).

### Site (`site/` in this repo, static, no build step)

| Page | Contents |
| --- | --- |
| `index.html` | Dark hero with an animated CSS notch island cycling working → needs you → done; headline "Your Mac, aware of your coding agents."; Download button. Sections: the island, click to return, notifications only when it matters, Dock glow, private by design, works with Claude Code / Codex / Gemini CLI, the demo video, requirements, FAQ. |
| `privacy.html` | What is collected (name, email), why (waitlist and product updates), where (Netlify Forms), removal on request. |
| `thanks.html` | No-JS fallback after the form posts: thank-you plus a direct download link. |
| `downloads/Ambient-0.2.0.dmg` | The notarized DMG. |

- Typography: the system font stack (SF Pro on Apple devices), Apple-style scale; light sections
  alternating with a dark hero; the island's palette from `Palette` (`#D97757`, `#F5A524`, `#3FB950`,
  `#F85149`, `#10A37F`, `#4F8DF7`).
- Download flow: **Download** opens a sheet with name and email (both required, email validated) and
  a honeypot. Submitting POSTs to Netlify Forms (`form-name=waitlist`) with `fetch`; on success the
  sheet shows "You're on the list" and starts the DMG download. Without JavaScript the form posts
  normally to `thanks.html`.
- Respects `prefers-reduced-motion` and `prefers-color-scheme` where it matters; responsive to phone
  width; Open Graph and Twitter card tags.
- `netlify.toml`: publish `site/`, cache headers, `Content-Disposition` for the DMG.

### Domain

Deploy to a `*.netlify.app` preview for review. Then in hPanel's DNS zone for yaml.cafe: `A @ →
75.2.60.5` (Netlify load balancer) and `CNAME www → <site>.netlify.app`, replacing the parking
records, after the user approves the exact change. Add the domain to the Netlify site and let it
issue the certificate.

## Part 2 — Assets

- Video scenes as HTML (menu bar and notch, island states, notification banners, Dock glow, the new
  settings window), recorded with Playwright's Chromium at 1920×1080, 30 fps.
- Script (60–75 s) approved before synthesis; Kokoro narration per scene; ffmpeg mux with burned-in
  captions. Cuts: 16:9 master, 1:1, 9:16.
- Stills rendered from the same scenes: OG 1200×630, X 1600×900, LinkedIn 1200×627, and 3–4
  product stills for Reddit.

## Part 3 — Posting

- X: launch thread (4–5 posts), video on the first, link in a reply. LinkedIn: one post with video.
- Reddit: 20 tailored drafts, each run through the advisor's preflight; skip communities marked red or
  whose current rules ban self-promotion or AI-assisted text, replacing them with the next best fit.
  Each post discloses the maker. The user approves the drafts post by post; Claude posts one per hour
  from Chrome and records each URL and status in `docs/launch/reddit-log.md`.
- Account eligibility (karma, age) is unknown until posting; CAPTCHAs are left to the user.
