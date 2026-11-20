# Homepage design test

The homepage runs a design test. Every visitor is shown one design (a theme), keeps it, and their download is
counted under it, so after enough downloads `scripts/ab-report.sh` shows which design turns visitors into
downloads best. Almanac is the default: it's what crawlers, people without JavaScript and anyone whose theme fails
to load see.

All themes share **one page** (`site/index.html`), **one behaviour** (`site/main.js`) and **one design system**
(`themes/system.css`). A theme is a folder that only sets tokens, adds decoration and draws its hero art:

```
site/themes/<id>/
  meta.json    name, set, inspiration, hero layout, fonts, optional hero words, optional "off"
  theme.css    tokens on :root, then decoration scoped to this theme's own classes
  motif.js     optional: draws the hero art into #motif
  fonts.css    written by scripts/build-themes.mjs; never edit by hand
```

| File | Who writes it |
|---|---|
| `themes/system.css`, `themes/loader.js` (outside its list), `index.html`, `main.js` | shared; change them only for every theme at once |
| `themes/loader.js` list, `themes/manifest.json`, `themes/fonts/` | `node scripts/build-themes.mjs` |
| `themes/<id>/*` | that theme |

## Adding, changing or dropping a theme

1. Make `site/themes/<id>/` with `meta.json` and `theme.css` (ids: lowercase letters, digits, hyphens).
2. `node scripts/build-themes.mjs <id>` fetches its fonts. Then `node scripts/build-themes.mjs --list` adds it to
   the test.
3. Preview at `/?theme=<id>` (not stored, not counted). `/themes/` lists every theme with links. Both work only
   locally and on a draft deploy (`scripts/deploy-site.sh` without `--prod`): on yaml.cafe the loader ignores
   `?theme=`, and `netlify/edge-functions/themes.ts` answers 404 for everything in `/themes/` but the files a
   visitor's browser needs, so the gallery, the manifest, these notes and each `meta.json` stay private.
4. `scripts/shoot-themes.sh OUT <id>` screenshots it at 1440 px and 390 px.

To take a theme out of the test without deleting it, add `"off": true` to its meta.json and rebuild the list.
New visitors stop drawing it; visitors who already have it keep it, so their downloads still count.

To start a new round (after cutting the test to the best few, say), raise `ROUND` in `loader.js` as well. Every
visitor then draws again from the designs that are on and is recorded again, so after deploying, read the new
round with `scripts/ab-report.sh --since <the day after the deploy>`.

What's counted: a visitor once, when their browser first draws a design (only if it can keep it), and their first
download from the homepage button in that round. Visits and downloads on this Mac's previews and on draft
deploys go to the `ab-views-preview` and `downloads-preview` stores, which the reports don't read.

## meta.json

```json
{
  "name": "Signal box",
  "set": "machines",
  "inspiration": "A railway signal box: track diagram, lever frame, lamp indicators",
  "order": 12,
  "hero": "split",
  "fonts": [
    { "family": "Big Shoulders Display", "axes": "wght@600;800" },
    { "family": "IBM Plex Mono", "axes": "wght@400;600" }
  ],
  "copy": { "kicker": "Box 0.10 · every line at a glance", "h1": "Every agent, on one diagram." }
}
```

- `hero`: `stack` (art above the words, centred), `split` (words left, art right; art goes first on a phone) or
  `under` (words above the art, centred).
- `fonts`: Google Fonts families and their css2 axes string, exactly as in a fonts.googleapis.com/css2 URL
  (`ital,wght@0,400;1,400`). Only the Latin subset is kept. Keep to the weights the theme uses.
- `copy`: optional hero words. Keys: `kicker`, `h1`, `lede`. Leave `lede` out unless the design needs it: the
  page's own lede says what Ambient is, and every claim in it is true. Hero words must be true of the app.

## Tokens (set them on `:root` in theme.css)

| Group | Tokens |
|---|---|
| Surfaces | `--bg`, `--bg-alt` (the `.alt` sections), `--surface` (cards), `--surface-2`, `--ink`, `--ink-2`, `--rule`, `--accent`, `--on-accent`, `--link` |
| Dark bands (`.dark` sections) | `--band`, `--band-ink`, `--band-ink-2`, `--band-surface`, `--band-rule` |
| Hero | `--hero-bg`, `--hero-ink`, `--hero-ink-2` |
| Ambient's colours | `--claude`, `--codex`, `--gemini`, `--waiting`, `--done`, `--error`: retune for contrast, never change what they mean (amber = needs you, green = done, red = error, the agent's colour = working) |
| Type | `--font-display`, `--font-body`, `--font-label`, `--font-mono`, `--display-weight`, `--display-style`, `--display-transform`, `--display-tracking`, `--display-leading`, `--h1-size`, `--h2-size`, `--h3-size`, `--body-size`, `--body-leading`, `--label-size`, `--label-tracking`, `--label-transform`, `--label-weight`, `--label-color` |
| Shape | `--radius`, `--radius-sm`, `--radius-btn`, `--border` (a full border shorthand), `--card-shadow`, `--btn-shadow` |
| Texture | `--texture`, `--band-texture` (background-image layers: grain, ruling, halftone) |
| Device | `--device-edge`, `--device-wallpaper`, `--device-wallpaper-light` (the MacBook and banner backdrops) |
| Other | `--wrap`, `--section-pad`, `--hero-pad`, `--edge-strength` (the window-edge glow, 0–1) |

Every font stack ends in a system fallback.

Good to know:
- Inside `.dark` bands, `--ink`, `--ink-2`, `--surface`, `--rule` and `--accent` already point at the band tokens,
  so `color: var(--ink)` there is the light band ink. Buttons in bands use `--band-accent` and `--band-on-accent`.
- `--texture` is painted as `background: var(--texture), var(--bg)` on the body, the hero, `.alt` and the dialog,
  so layers may carry a position and size (`radial-gradient(...) 0 0 / 5px 5px`).
- The hero layout rules in system.css use `:where()`, so a theme's own `.hero-grid` rule wins.
- Prefix the classes your art uses (`.sbx-error`, not `.error`), so shared styles don't reach them.

## Decoration

After the tokens, theme.css may restyle any shared class (`.nav`, `.btn`, `.kicker`, `.card`, `.states .card`,
`.dest`, `.faq`, `.step`, `.stat`, `.guide-list`, `footer`, `dialog`, ...) and add its own classes for what
motif.js draws. Prefix your own classes with a short theme prefix (`.alm-`, `.sbx-`). Rules:

- Never hide or reorder content, never change the words outside `copy`, never restyle the MacBook demo, the
  notification banners or the wallpaper canvas beyond the `--device-*` tokens: they're pictures of the app.
- Text keeps contrast: body text at least 4.5:1 (WCAG AA) on its background, headings and the hero at least 7:1
  where the design allows. Buttons and chips stay at least 44 px tall on a phone.
- Works from 360 px to 1600 px wide, with no sideways scrolling.
- Motion respects `prefers-reduced-motion` (system.css stops animations; motif.js should draw a still frame).

## motif.js

A plain script, loaded after the page has parsed, so theme.css must reserve the art's height on `.hero-art`
(`min-height` or `aspect-ratio`, at every width) or the page jumps when it's drawn. It draws into `document.getElementById("motif")`, which is
`aria-hidden`, so nothing in it is read out: it's art, and any words in it repeat what the page says. Keep it small
(under ~8 KB), with no libraries and no network requests. It can follow the demo: main.js sets `--state` (the
current state's colour) and `data-mood` (`working`, `waiting`, `done`, `error`) on `<html>` every few seconds, so
`fill: var(--state)` in theme.css or a `MutationObserver` on `data-mood` brings the art to life.
