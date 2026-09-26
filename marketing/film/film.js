// Ambient's launch film. Every frame is a pure function of time: window.renderAt(seconds).
// The renderer injects window.TIMELINE (out/film/timeline.json) and ?ratio=16x9|1x1|9x16.
(() => {
  const params = new URLSearchParams(location.search);
  const ratio = params.get("ratio") || "16x9";
  const [FW, FH] = { "16x9": [1920, 1080], "1x1": [1080, 1080], "9x16": [1080, 1920] }[ratio];
  const L = {
    "16x9": { W: 1280, ax: 960, ay: 470, capY: 1000, capW: 1500, capSize: 44 },
    "1x1": { W: 960, ax: 540, ay: 450, capY: 985, capW: 960, capSize: 40 },
    "9x16": { W: 1000, ax: 540, ay: 860, capY: 1560, capW: 940, capSize: 50 },
  }[ratio];
  document.body.dataset.ratio = ratio;

  const $ = (id) => document.getElementById(id);
  const frame = $("frame");
  frame.style.width = FW + "px";
  frame.style.height = FH + "px";
  const camera = $("camera");
  camera.style.width = L.W + "px";
  const caption = $("caption");
  caption.style.width = L.capW + "px";
  caption.style.fontSize = L.capSize + "px";

  // MARK: - Math

  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
  const seg = (t, a, b) => clamp((t - a) / (b - a));
  const lerp = (a, b, x) => a + (b - a) * x;
  const ease = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
  const easeOut = (x) => 1 - Math.pow(1 - x, 3);
  /** A spring from 0 to 1 that overshoots a little, like the island's. */
  const spring = (x) => (x <= 0 ? 0 : x >= 1 ? 1 : 1 - Math.exp(-6 * x) * Math.cos(8 * x));
  const breathe = (t, period) => 0.5 - 0.5 * Math.cos((t / period) * 2 * Math.PI);

  const COLORS = { working: "var(--claude)", waiting: "var(--waiting)", done: "var(--done)", error: "var(--error)" };

  // MARK: - Timeline

  let scenes = [];
  let S = {};
  const at = (id) => S[id].start;
  const dur = (id) => S[id].duration;

  function setTimeline(tl) {
    scenes = tl.scenes;
    S = Object.fromEntries(scenes.map((s) => [s.id, s]));
    buildShots();
  }

  // MARK: - Camera

  let shots = [];
  function buildShots() {
    shots = [
      { t: 0, d: 0.01, s: 1.0, fx: 0.5, fy: 0.5 },
      { t: 0.6, d: 4.4, s: 1.12, fx: 0.5, fy: 0.4 },
      { t: at("island") + 0.1, d: 1.4, s: 2.1, fx: 0.5, fy: 0.07, fit: 0.52 },
      { t: at("needs-you") + 2.6, d: 1.3, s: 1.5, fx: 0.6, fy: 0.15, fit: 1.08 },
      { t: at("done") + 0.1, d: 1.0, s: 2.0, fx: 0.5, fy: 0.07, fit: 0.52 },
      { t: at("return") + 0.2, d: 1.2, s: 1.15, fx: 0.5, fy: 0.4 },
      { t: at("dock") + 0.2, d: 1.4, s: 1.45, fx: 0.5, fy: 0.8, fit: 0.9 },
      { t: at("agents") + 0.1, d: 1.2, s: 0.9, fx: 0.5, fy: 0.5 },
      { t: at("cta") + 0.1, d: 1.2, s: 1.18, fx: 0.5, fy: 0.42 },
    ];
  }

  const shotScale = (sh) => (sh.fit ? Math.min(sh.s, (FW * 0.94) / (sh.fit * L.W)) : sh.s);

  function cameraAt(t) {
    let i = 0;
    while (i + 1 < shots.length && t >= shots[i + 1].t) i++;
    const cur = shots[i];
    const prev = shots[Math.max(0, i - 1)];
    const p = ease(seg(t, cur.t, cur.t + cur.d));
    return {
      s: lerp(shotScale(prev), shotScale(cur), p),
      fx: lerp(prev.fx, cur.fx, p),
      fy: lerp(prev.fy, cur.fy, p),
    };
  }

  // MARK: - Story state

  /** What the agents are doing at time t: the color of the island, menu bar orb and Dock. */
  function moodAt(t) {
    if (t < at("island") + 0.3) return null;
    if (t < at("needs-you") + 0.3) return "working";
    if (t < at("done")) return "waiting";
    if (t < at("return") + 3.2) return "done";
    if (t < at("dock") + 0.3) return null;
    if (t < at("dock") + 3.2) return "working";
    if (t < at("agents")) return "waiting";
    return "working";
  }

  const TERM = [
    { t: 0.5, html: '<span class="p">~/api-server ❯</span> ', typed: 'claude "make the test suite pass"', typeEnd: 2.2 },
    { t: 2.6, html: '<span class="c">✻</span> Running npm test…' },
    { t: 3.3, html: '  ⎿  38 passed, 4 failed' },
    { t: 4.1, html: '<span class="c">✻</span> Editing src/cache.ts' },
    { at: () => at("needs-you") + 0.2, html: '<span class="w">⏺</span> Bash(rm -rf build)' },
    { at: () => at("needs-you") + 0.4, html: '<span class="d">  Allow this command? ❯ Yes  No</span>' },
    { at: () => at("done") + 0.1, html: '<span class="g">✓</span> 42 passed. Ready for review.' },
  ];

  function termText(t) {
    const out = [];
    for (const line of TERM) {
      const start = line.at ? line.at() : line.t;
      if (t < start) break;
      if (line.typed) {
        const n = Math.floor(line.typed.length * seg(t, start, line.typeEnd));
        const caret = t < line.typeEnd + 0.4 ? '<span class="d">▌</span>' : "";
        out.push(line.html + line.typed.slice(0, n) + caret);
      } else {
        out.push(line.html);
      }
    }
    return out.slice(-6).join("\n");
  }

  // MARK: - Render

  let macH = 0;

  function set(el, styles) { Object.assign(el.style, styles); }

  window.renderAt = (t) => {
    if (!macH) macH = camera.querySelector(".macbook").offsetHeight;
    const mood = moodAt(t);
    const color = mood ? COLORS[mood] : "var(--claude)";
    frame.style.setProperty("--mood", color);
    frame.style.setProperty("--state", color);
    $("glow").style.opacity = mood ? 0.22 : 0.08;

    // Camera and the overlays that replace it.
    const cam = cameraAt(t);
    const dimAgents = seg(t, at("agents") + 0.1, at("agents") + 0.9) * (1 - seg(t, at("cta"), at("cta") + 0.8));
    const endcard = seg(t, at("cta") + 4.6, at("cta") + 5.4);
    set(camera, {
      transform: `translate(${L.ax - cam.s * cam.fx * L.W}px, ${L.ay - cam.s * cam.fy * macH}px) scale(${cam.s})`,
      opacity: String(1 - 0.8 * dimAgents),
      filter: dimAgents > 0 ? `blur(${6 * dimAgents}px)` : "none",
    });
    set($("cards"), { opacity: String(dimAgents * (1 - endcard)), transform: `translateY(${(1 - easeOut(dimAgents)) * 40}px)` });
    document.querySelectorAll(".agent-card").forEach((c, i) => {
      const p = easeOut(seg(t, at("agents") + 0.5 + i * 0.35, at("agents") + 1.2 + i * 0.35));
      set(c, { opacity: String(p), transform: `translateY(${(1 - p) * 30}px)` });
      c.querySelector(".orb").style.transform = `scale(${0.9 + 0.18 * breathe(t, 3.2)})`;
    });
    const facts = easeOut(seg(t, at("agents") + 4.0, at("agents") + 4.8));
    set(document.querySelector(".facts"), { opacity: String(facts), transform: `translateY(${(1 - facts) * 30}px)` });
    set($("endcard"), { opacity: String(endcard) });
    set($("brand"), { opacity: String(1 - endcard) });

    // Menu bar: which app is in front, and Ambient's status orb.
    const inBrowser = t >= at("needs-you") + 0.9 && t < at("return") + 3.2;
    const inSettings = t >= at("cta") + 0.3;
    $("app-name").textContent = inSettings ? "Ambient" : inBrowser ? "Safari" : "Terminal";
    set($("menu-orb"), { opacity: mood ? "1" : "0.35" });

    // Windows.
    $("term-text").innerHTML = termText(t);
    const browserIn = easeOut(seg(t, at("needs-you") + 0.7, at("needs-you") + 1.3));
    const raised = t >= at("return") + 3.2;
    set($("win-browser"), {
      opacity: String(browserIn * (1 - seg(t, at("return") + 3.2, at("return") + 3.6) * 0.0)),
      transform: `translateY(${(1 - browserIn) * 3}cqw)`,
      zIndex: raised ? "1" : "2",
    });
    const bump = raised ? 1 + 0.02 * (1 - seg(t, at("return") + 3.2, at("return") + 3.7)) : 1;
    set($("win-term"), { zIndex: raised ? "3" : "1", transform: `scale(${bump})` });
    const settingsIn = easeOut(seg(t, at("cta") + 0.2, at("cta") + 0.9));
    set($("win-settings"), { opacity: String(settingsIn), transform: `translateX(-50%) scale(${0.96 + 0.04 * settingsIn})`, zIndex: "5" });
    const connected = t >= at("cta") + 2.3;
    $("check-agents").classList.toggle("done", connected);
    $("agents-count").textContent = connected ? "3 of 3 connected" : "0 of 3 connected";
    set($("connect-all"), { visibility: connected ? "hidden" : "visible" });

    // Island: hidden → wings → bloom, springing between sizes.
    const island = $("island");
    const open = islandOpen(t);
    const shown = islandShown(t);
    const w = lerp(13, lerp(34, 46, open), shown);
    const h = lerp(3.9, 12.5, open);
    set(island, { width: w + "cqw", height: h + "cqw", borderRadius: `0 0 ${lerp(1.7, 3.2, open)}cqw ${lerp(1.7, 3.2, open)}cqw`,
      boxShadow: open > 0.05 ? `0 2.2cqw 5cqw rgba(0,0,0,${0.5 * open})` : "none" });
    set(island.querySelector(".wings"), { opacity: String(clamp(shown * (1 - open * 3))) });
    set(island.querySelector(".bloom"), { opacity: String(clamp((open - 0.55) * 3)) });
    const doneState = t >= at("done");
    $("bloom-orb").className = "orb big " + (doneState ? "check" : "");
    $("bloom-msg").textContent = doneState ? "All 42 tests pass. Ready for review." : "Needs permission · Bash: rm -rf build";
    $("bloom-elapsed").textContent = doneState ? "4m" : "2m";
    const pulse = mood === "waiting" ? breathe(t, 1.2) : breathe(t, 3.2);
    $("bloom-orb").style.transform = doneState ? "none" : `scale(${0.9 + 0.18 * pulse})`;
    $("wing-orb").style.transform = `scale(${0.9 + 0.18 * pulse})`;
    $("wing-orb").className = "orb" + (mood === "done" ? " big check" : "");
    const elapsed = Math.max(1, Math.floor(t - at("island")));
    $("wing-timer").textContent = mood === "done" ? "" : mood === "waiting" ? "✋" : elapsed < 60 ? `${elapsed}s` : `${Math.floor(elapsed / 60)}m`;

    // Notification banner.
    const bIn = spring(seg(t, at("needs-you") + 0.9, at("needs-you") + 1.6));
    const bOut = easeOut(seg(t, at("done") + 3.6, at("done") + 4.2));
    set($("banner"), { opacity: String(clamp(bIn * 1.4) * (1 - bOut)), transform: `translateX(${(1 - bIn) * 34 + bOut * 34}cqw)` });
    $("banner-title").textContent = doneState ? "api-server is done" : "api-server needs your permission";
    $("banner-body").textContent = doneState ? "All 42 tests pass. Ready for review." : "Bash: rm -rf build";

    // The Dock and its glow.
    const glowOn = mood ? 1 : 0;
    const dockColor = mood ? COLORS[mood] : "var(--claude)";
    const dockEmphasis = seg(t, at("dock"), at("dock") + 1) * (1 - seg(t, at("agents"), at("agents") + 1));
    const period = mood === "waiting" ? 1.2 : 3.2;
    const level = mood === "done" ? 0.75 : lerp(0.35, 0.9, breathe(t, period));
    $("dockbar").style.setProperty("--dock", dockColor);
    set($("d-glow"), { opacity: String(glowOn * level * lerp(0.35, 1, dockEmphasis)) });
    set($("d-pill"), { opacity: String(glowOn * level * lerp(0.4, 1, dockEmphasis)) });

    // Cursor: clicks the island in "return", then Connect All in "cta".
    const c = cursorAt(t);
    set($("cursor"), { opacity: String(c.o), transform: `translate(${c.x}cqw, ${c.y}cqw)` });
    const ring = c.click;
    set($("click-ring"), { opacity: String(ring > 0 ? 1 - ring : 0),
      transform: `translate(${c.x - 2.5}cqw, ${c.y - 2.5}cqw) scale(${0.4 + ring})` });

    // Captions follow the voice.
    const sc = scenes.find((s) => t >= s.start && t < s.start + s.duration) || scenes[scenes.length - 1];
    const a = sc.voiceStart - 0.15, b = sc.voiceStart + sc.voiceDuration + 0.4;
    const capOpacity = seg(t, a, a + 0.25) * (1 - seg(t, b, b + 0.25));
    caption.textContent = sc.caption;
    $("scrim").style.opacity = String(capOpacity * (1 - endcard));
    set(caption, { opacity: String(capOpacity), top: L.capY - caption.offsetHeight / 2 + "px" });
  };

  function islandShown(t) {
    if (t < at("island")) return 0;
    if (t < at("return") + 3.2) return spring(seg(t, at("island") + 0.3, at("island") + 1.2));
    if (t < at("dock") + 0.3) return 1 - easeOut(seg(t, at("return") + 3.3, at("return") + 3.8));
    return spring(seg(t, at("dock") + 0.3, at("dock") + 1.1));
  }

  function islandOpen(t) {
    const openAt = at("needs-you") + 0.3;
    if (t < openAt) return 0;
    const closeAt = at("done") + 3.8;
    if (t < closeAt) return spring(seg(t, openAt, openAt + 0.9));
    // Hovered by the cursor in "return", before the click.
    const hoverAt = at("return") + 1.9, clickAt = at("return") + 3.2;
    if (t >= hoverAt && t < clickAt + 0.2) return spring(seg(t, hoverAt, hoverAt + 0.8)) * (1 - easeOut(seg(t, clickAt, clickAt + 0.2)));
    return clamp(1 - easeOut(seg(t, closeAt, closeAt + 0.5)));
  }

  function cursorAt(t) {
    const r0 = at("return"), c0 = at("cta");
    if (t >= r0 + 0.4 && t < r0 + 4.6) {
      const p = ease(seg(t, r0 + 0.4, r0 + 2.1));
      return { o: seg(t, r0 + 0.4, r0 + 0.7) * (1 - seg(t, r0 + 4.2, r0 + 4.6)), x: lerp(60, 49.5, p), y: lerp(38, 5.5, p),
        click: t >= r0 + 3.1 ? seg(t, r0 + 3.1, r0 + 3.6) : 0 };
    }
    if (t >= c0 + 0.8 && t < c0 + 4.2) {
      const p = ease(seg(t, c0 + 0.8, c0 + 2.0));
      return { o: seg(t, c0 + 0.8, c0 + 1.0) * (1 - seg(t, c0 + 3.8, c0 + 4.2)), x: lerp(50, 73, p), y: lerp(44, 27.2, p),
        click: t >= c0 + 2.2 ? seg(t, c0 + 2.2, c0 + 2.7) : 0 };
    }
    return { o: 0, x: 0, y: 0, click: 0 };
  }

  window.filmReady = (async () => {
    const tl = window.TIMELINE || (await fetch("../out/film/timeline.json").then((r) => r.json()));
    setTimeline(tl);
    await document.fonts.ready;
    await Promise.all([...document.images].map((i) => (i.complete ? null : new Promise((r) => { i.onload = i.onerror = r; }))));
    window.renderAt(Number(params.get("t") || 0));
    return tl;
  })();
})();
