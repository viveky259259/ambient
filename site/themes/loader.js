// The design test. Runs in <head>, before the page paints.
//
// Every visitor is shown one design (a "variant") and keeps it on later visits. A new visitor adds one anonymous
// record ({variant, day}) through /api/ab, and their download carries ?v=<variant> (main.js), so
// scripts/ab-report.sh can compare downloads per visitor across designs. No cookie, no identifier.
//
//   /?theme=<id>      preview a design; not stored or counted
//   /?theme=reset     forget this browser's design and draw again
//
// Both work only on this Mac and on Netlify draft and branch deploys (PREVIEW_HOST, kept in step with
// netlify/edge-functions/lib/ab-core.ts). On yaml.cafe the parameter is ignored, so a visitor can't pick a design.
//
// The list between the markers is written by scripts/build-themes.mjs from site/themes/*/meta.json.
(() => {
  /* @themes */
  const THEMES = [{"id":"almanac","hero":"stack"},{"id":"signal-halo","hero":"stack","copy":{"kicker":"A free, native macOS app"}},{"id":"night-desk","hero":"split","copy":{"kicker":"Ambient for macOS · Free and open source","h1":"Glance, don't babysit."}},{"id":"field-manual","hero":"under","copy":{"kicker":"Field manual for coding agents on macOS","h1":"Glance. Don't babysit."}},{"id":"living-sky","hero":"under","copy":{"kicker":"Ambient · a calmer Mac for coding agents"}},{"id":"session-score","hero":"under","copy":{"kicker":"Free · native · macOS 14+","h1":"Agents work for minutes. Know the second they stop."}},{"id":"lighthouse","hero":"stack","copy":{"kicker":"A beacon for coding agents on macOS","h1":"A light for the moment your agents need you."}},{"id":"departure-board","hero":"under","copy":{"kicker":"Every session on one board, most urgent first","h1":"Glance, don't babysit."}},{"id":"hifi-receiver","hero":"split","copy":{"h1":"Less noise. More aware."}},{"id":"radar-scope","hero":"split","copy":{"kicker":"Ambient · approach control for coding agents","h1":"Every agent on one scope."}},{"id":"riso-zine","hero":"split","copy":{"kicker":"Issue 0.10 · a free Mac app for coding agents","h1":"Your Mac watches the agents."}},{"id":"herbarium","hero":"split","copy":{"kicker":"Ambient · macOS 14 or later · free","h1":"A field guide to the agents living on your Mac."}},{"id":"jazz-sleeve","hero":"split","copy":{"kicker":"Stereo · for macOS 14 or later","h1":"Glance, don't babysit."}},{"id":"contour-map","hero":"split","copy":{"kicker":"Ambient · a survey of your coding agents","h1":"Know where every agent stands."}},{"id":"rose-window","hero":"stack","copy":{"kicker":"Ambient · for coding agents on macOS","h1":"Light, when it matters."}},{"id":"ink-tearoom","hero":"split","copy":{"kicker":"Ambient · for macOS","h1":"Quiet, until it matters."}},{"id":"brutalist-block","hero":"split","copy":{"kicker":"Free · native macOS · Claude Code, Codex, Gemini CLI","h1":"Glance, don't babysit."}},{"id":"deco-elevator-dial","hero":"under"},{"id":"lantern-street","hero":"stack","copy":{"kicker":"A free, native macOS app for coding agents","h1":"Your Mac tells you, quietly, at the moment it matters."}},{"id":"match-day-pitch","hero":"under","copy":{"kicker":"Free · native macOS · every agent on one pitch","h1":"Glance, don't babysit."}},{"id":"bauhaus-forms","hero":"split","copy":{"kicker":"Free · native macOS · Claude Code / Codex / Gemini CLI","h1":"One color at the notch."}},{"id":"diner-ticket-rail","hero":"split","copy":{"kicker":"Free · native macOS · banners and soft chimes","h1":"Alerts only when they matter."}},{"id":"azulejo-wall","hero":"split","copy":{"kicker":"Free · native macOS · made for the Mac","h1":"Every agent in one place, read in one color."}},{"id":"stage-cue-lights","hero":"under","copy":{"kicker":"Free · native macOS · for Claude Code, Codex and Gemini CLI","h1":"Alerts only when they matter."}},{"id":"neon-roadside","hero":"split","copy":{"kicker":"Free · native macOS · no account","h1":"Back in one click."}},{"id":"illuminated-hours","hero":"split","copy":{"kicker":"A free, native macOS app · for Claude Code, Codex & Gemini CLI","h1":"Glance, don't babysit."}},{"id":"signal-box","hero":"split","copy":{"kicker":"Free · native macOS · open source","h1":"Every agent on the line. One color at the notch."}},{"id":"switchboard","hero":"split","copy":{"kicker":"A free, native macOS app","h1":"Your agents are calling. Ambient puts you through."}},{"id":"till-receipt","hero":"split","copy":{"kicker":"Free · native macOS · open source","h1":"Your agents, itemised."}},{"id":"elevator-panel","hero":"split","copy":{"kicker":"A free, native macOS app","h1":"Know which floor your agents are on."}},{"id":"road-signs","hero":"under","copy":{"kicker":"Free · native macOS · open source","h1":"Read your agents like the road ahead."}},{"id":"punch-cards","hero":"split","copy":{"kicker":"Free · native macOS · open source","h1":"Agents run for minutes. Your Mac tells you when."}},{"id":"airmail","hero":"split","copy":{"kicker":"Free · native macOS · open source","h1":"Word from your agents, delivered to the notch."}},{"id":"engine-telegraph","hero":"split","copy":{"kicker":"Free · native macOS · open source","h1":"The agent rings down. You answer in one click."}},{"id":"test-card","hero":"stack","copy":{"kicker":"Free · native macOS · open source","h1":"Stop standing by for your agents."}},{"id":"bioluminescence","hero":"under","copy":{"kicker":"Free · native macOS · open source","h1":"Agents that glow when they need you."}},{"id":"mineral-cabinet","hero":"split","copy":{"kicker":"Cabinet of agent states · free for macOS","h1":"Four states, one colour at the notch."}},{"id":"prism","hero":"stack","copy":{"kicker":"Free · native macOS · open source","h1":"Every agent, resolved into one colour."}},{"id":"periodic-table","hero":"split","copy":{"kicker":"The elements of knowing what your agents are doing","h1":"Four states. One colour at the notch."}},{"id":"barometer","hero":"split","copy":{"kicker":"An instrument for coding agents · free for macOS","h1":"Glance, don't babysit."}},{"id":"honeycomb","hero":"split","copy":{"kicker":"Free · native macOS · open source","h1":"Every agent in one place."}},{"id":"orrery-cyanotype","hero":"split","copy":{"kicker":"Free · native macOS · open source","h1":"Your agents, in orbit around the notch."}},{"id":"iris","hero":"split","copy":{"kicker":"Plate I · the anatomy of a glance · free for macOS","h1":"Know at a glance."}},{"id":"chladni","hero":"under","copy":{"kicker":"Free · native macOS · open source","h1":"Each state has its own figure."}},{"id":"petri-dishes","hero":"split","copy":{"kicker":"Free · native macOS · open source"}},{"id":"loom","hero":"split","copy":{"kicker":"Free native macOS app","h1":"Every agent, woven into one colour."}},{"id":"glaze-tiles","hero":"under","copy":{"kicker":"A free Mac app · four glazes for your coding agents","h1":"Glance, don't babysit."}},{"id":"watch-dial","hero":"split","copy":{"kicker":"Calibre macOS · free · native"}},{"id":"letterpress-broadside","hero":"under","copy":{"kicker":"❦ A free, native macOS app for coding agents ❦","h1":"Glance, don't babysit."}},{"id":"enamel-sign","hero":"split","copy":{"kicker":"Free native macOS app · coding agents","h1":"Back in one click."}},{"id":"abacus","hero":"under","copy":{"kicker":"Free native macOS app","h1":"Every agent in one place."}},{"id":"chime-bars","hero":"under","copy":{"kicker":"Free native macOS app · eight bars, four states","h1":"A soft chime, the moment it matters."}},{"id":"neon-sign","hero":"split","copy":{"kicker":"Free native macOS app · for coding agents","h1":"Visible from across the room."}},{"id":"zellige","hero":"split","copy":{"kicker":"A free, native macOS app","h1":"One colour says what every agent is doing."}},{"id":"jewellers-tray","hero":"split","copy":{"kicker":"A free, native macOS app","h1":"Your Mac tells you, quietly."}}];
  /* @end */
  const DEFAULT = "almanac";
  const KEY = "ambient-variant";
  const root = document.documentElement;
  const store = {
    get() { try { return localStorage.getItem(KEY); } catch { return null; } },
    set(v) { try { localStorage.setItem(KEY, v); } catch { /* ignore */ } },
    clear() { try { localStorage.removeItem(KEY); } catch { /* ignore */ } },
  };
  const byId = (id) => THEMES.find((t) => t.id === id);
  const bot = /bot|crawl|spider|slurp|preview|headless|lighthouse|facebookexternalhit|embedly/i.test(navigator.userAgent);
  const PREVIEW_HOST = /^(localhost|127\.0\.0\.1|\[::1\])$|\.localhost$|--[a-z0-9-]+\.netlify\.app$/i;
  const asked = PREVIEW_HOST.test(location.hostname) ? new URLSearchParams(location.search).get("theme") : null;
  if (asked === "reset") store.clear();

  let theme, preview = false, fresh = false;
  if (asked && asked !== "reset" && /^[a-z0-9-]{1,40}$/.test(asked)) {
    // A preview may name a theme that isn't in the test yet; its files are used as they are.
    theme = byId(asked) || { id: asked, hero: "stack" };
    preview = true;
  } else if (bot) {
    theme = byId(DEFAULT);
  } else {
    theme = byId(store.get());
    if (!theme) {
      const live = THEMES.filter((t) => !t.off);
      theme = live[Math.floor(Math.random() * live.length)] || byId(DEFAULT);
      store.set(theme.id);
      fresh = true;
    }
  }

  const counted = !preview && !bot;
  window.AmbientAB = { variant: theme.id, preview, counted };
  root.dataset.theme = theme.id;
  root.dataset.hero = theme.hero || "stack";

  // Load only this theme's stylesheets (the page links none, so no visitor fetches a design they weren't given;
  // a <noscript> in index.html gives Almanac to browsers without JavaScript). The page stays hidden until they're
  // in, at most 2.5 s, and until a theme's own hero words are in, so nobody sees the design or the words change.
  root.classList.add("theming");
  let waiting = 3;
  const reveal = () => { if (--waiting <= 0) root.classList.remove("theming"); };
  setTimeout(() => root.classList.remove("theming"), 2500);
  for (const file of ["fonts.css", "theme.css"]) {
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = `/themes/${theme.id}/${file}`;
    link.onload = link.onerror = reveal;
    document.head.appendChild(link);
  }

  // The theme's own art for the hero, and its words for the hero if it has any (crawlers keep the page's own).
  const ready = () => {
    if (theme.copy && !bot) {
      for (const el of document.querySelectorAll("[data-copy]")) {
        const text = theme.copy[el.dataset.copy];
        if (text) el.textContent = text;
      }
    }
    reveal();
    if (theme.motif !== false) {
      const s = document.createElement("script");
      s.src = `/themes/${theme.id}/motif.js`;
      s.onerror = () => {};
      document.body.appendChild(s);
    }
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ready); else ready();

  // One record per new visitor; sendBeacon doesn't hold up the page.
  if (fresh && counted) {
    try { navigator.sendBeacon("/api/ab", JSON.stringify({ v: theme.id })); } catch { /* ignore */ }
  }
})();
