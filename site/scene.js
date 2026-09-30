// The living wallpaper demo: Sky with a black hole, or the Solar System with a sun, at the notch.
// A small port of the app's physics: Kepler launch speeds, fixed 4 ms steps, springs home.
(() => {
  const root = document.getElementById("scene-demo");
  const canvas = document.getElementById("scene-canvas");
  if (!root || !canvas) return;
  const ctx = canvas.getContext("2d");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const TAU = Math.PI * 2;
  const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));

  const AGENTS = [
    { name: "Claude · Needs you", color: "#d97757", glow: "#f5a524", x: 0.26, y: 0.52 },
    { name: "Codex · Working", color: "#10a37f", glow: "#10a37f", x: 0.72, y: 0.46 },
    { name: "Gemini · Done", color: "#4f8df7", glow: "#3fb950", x: 0.42, y: 0.72 },
    { name: "Claude · Working", color: "#d97757", glow: "#d97757", x: 0.84, y: 0.7 },
    { name: "Codex · Failed", color: "#10a37f", glow: "#f85149", x: 0.12, y: 0.78 },
    { name: "Gemini · Working", color: "#4f8df7", glow: "#4f8df7", x: 0.6, y: 0.84 },
  ];
  const LOOKS = {
    dark: { sky: ["#03040c", "#0a1030", "#141a44"], star: "255,255,255", ink: "#f5f5f7", sub: "rgba(245,245,247,.6)", ring: "150,170,255", hills: ["#0b0f26", "#06081a"] },
    light: { sky: ["#6fa6e6", "#a9cdf2", "#e4effa"], star: "30,40,70", ink: "#15171c", sub: "rgba(21,23,28,.6)", ring: "40,60,120", hills: ["#557396", "#3b5575"] },
  };
  const ECC = 0.45, TILT = 0.72, SUN_GM = 0.045;

  let world = "sky", look = LOOKS.dark, open = false;
  let W = 0, H = 0, u = 1, time = 0, openedAt = -99, closedAt = -99, born = false, lastFrame = 0, running = false;
  let bodies = [], stars = [];

  function resize() {
    const d = window.devicePixelRatio || 1;
    W = canvas.clientWidth; H = canvas.clientHeight; u = H / 600;
    canvas.width = Math.round(W * d); canvas.height = Math.round(H * d);
    ctx.setTransform(d, 0, 0, d, 0, 0);
    reset();
  }

  function rowSlot(i, n) {
    const rows = n > 4 ? 2 : 1, perRow = Math.ceil(n / rows), row = Math.floor(i / perRow), col = i % perRow;
    const inRow = row === rows - 1 ? n - perRow * (rows - 1) : perRow;
    const span = Math.min(0.8, 0.26 * (inRow - 1));
    return [inRow === 1 ? 0.5 : (1 - span) / 2 + (span * col) / (inRow - 1), rows === 1 ? 0.5 : row === 0 ? 0.44 : 0.66];
  }

  function reset() {
    let seed = 7;
    const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
    bodies = AGENTS.map((a, i) => {
      const [hx, hy] = world === "solar" ? rowSlot(i, AGENTS.length) : [a.x, a.y];
      return { ...a, agent: true, hx: hx * W, hy: hy * H, x: hx * W, y: hy * H, vx: 0, vy: 0, gone: false, trail: [], orbit: 0, theta: 0, entered: false, spin: 0 };
    });
    const orbits = solarOrbits();
    if (world === "solar") bodies.forEach((b, i) => { b.orbit = orbits[i]; });
    const dust = world === "sky" ? 110 : 90;
    for (let i = 0; i < dust; i++) {
      if (world === "sky") {
        const hx = rnd() * W, hy = (0.05 + rnd() * 0.7) * H;
        bodies.push({ agent: false, hx, hy, x: hx, y: hy, vx: 0, vy: 0, gone: false, a: 0.3 + rnd() * 0.6, s: 0.6 + rnd(), fade: 1 });
      } else {
        const a = orbits[2] + (orbits[3] - orbits[2]) * (0.3 + 0.4 * rnd()), theta = rnd() * TAU;
        bodies.push({ agent: false, belt: true, orbit: a, theta, a: 0.3 + rnd() * 0.5, s: 0.5 + rnd() * 0.8 });
      }
    }
    stars = Array.from({ length: 160 }, () => ({ x: rnd(), y: rnd() * 0.8, s: 0.4 + rnd() * 1.1, a: 0.2 + rnd() * 0.7 }));
    born = false;
  }

  // Geometry: the notch sits at the top centre; the hole and the sun's diameter is its width.
  const notchW = () => W * 0.13;
  const center = () => [W / 2, H * 0.036];
  const scale = () => Math.min(H * 1.1, (W * 0.49) / (0.72 * Math.sqrt(1 - ECC * ECC)));
  const radiusAt = (a, th) => (a * (1 - ECC * ECC)) / (1 - ECC * Math.sin(th));
  function solarOrbits() {
    const s = scale(), clear = (H * 0.34 + 20 * u - H * 0.036) / ((1 + ECC) * s * TILT);
    const inner = Math.max(0.42, clear), outer = Math.max(0.72, inner + 0.12);
    return AGENTS.map((_, i) => inner + ((outer - inner) * i) / (AGENTS.length - 1));
  }
  function project(a, th) {
    const [cx, cy] = center(), r = radiusAt(a, th) * scale();
    return [cx + Math.cos(th) * r, cy + Math.sin(th) * r * TILT];
  }

  const sinceOpen = () => time - openedAt, sinceClose = () => time - closedAt;
  function presence() {
    if (world === "sky") {
      if (open) { const x = clamp((sinceOpen() - 0.18) / 0.7) - 1; return 1 + 2.2 * x * x * x + 1.2 * x * x; }
      return clamp(1 - sinceClose() / 0.45) * (closedAt > openedAt ? 1 : 0);
    }
    return open ? clamp(sinceOpen() / 0.8) : clamp(1 - sinceClose() / 1.0) * (closedAt > openedAt ? 1 : 0);
  }

  function step(h) {
    time += h;
    const [cx, cy] = center(), R = (notchW() / 2) * presence();
    if (world === "sky") {
      const gm = open && sinceOpen() >= 0.35 ? 5.5e6 * u * u * u : 0;
      if (gm > 0 && !born) {
        born = true;
        for (const b of bodies) {
          if (b.gone) continue;
          const dx = b.x - cx, dy = b.y - cy, r = Math.hypot(dx, dy) || 1;
          const peri = b.agent ? Math.max((notchW() / 2) * 1.9, r * 0.42) : r * (0.05 + Math.random() * 0.5);
          const v = Math.sqrt((2 * gm * peri) / (r * (r + peri)));
          b.vx += (-dy / r) * v; b.vy += (dx / r) * v;
        }
      }
      for (const b of bodies) {
        if (b.gone) {
          if (!open && sinceClose() > 0.8) { b.gone = false; b.x = b.hx; b.y = b.hy; b.vx = b.vy = 0; b.fade = 0; }
          continue;
        }
        if (!b.agent) b.fade = Math.min(1, b.fade + h * 0.5);
        const dx = cx - b.x, dy = cy - b.y, r2 = dx * dx + dy * dy, r = Math.sqrt(r2) || 1;
        let ax = 0, ay = 0;
        if (gm > 0) {
          const a = gm / (r2 + 400); ax += (dx / r) * a; ay += (dy / r) * a;
          if (!b.agent) { const near = clamp(1 - r / (R * 3 + 1)); b.vx *= 1 - near * 1.8 * h; b.vy *= 1 - near * 1.8 * h; }
        } else {
          ax += (b.hx - b.x) * 3 - b.vx * 3; ay += (b.hy - b.y) * 3 - b.vy * 3;
        }
        b.vx += ax * h; b.vy += ay * h;
        const sp = Math.hypot(b.vx, b.vy), cap = H * 3.5; if (sp > cap) { b.vx *= cap / sp; b.vy *= cap / sp; }
        b.x += b.vx * h; b.y += b.vy * h;
        if (!b.agent && R > 1 && Math.hypot(cx - b.x, cy - b.y) < R * 0.98) b.gone = true;
      }
    } else {
      const lit = open && presence() > 0.2, K = 7, C = 2 * Math.sqrt(K);
      for (const b of bodies) {
        b.spin += ((lit ? 1 : 0) - b.spin) * Math.min(1, h * (open ? 1.2 : 0.8));
        if (b.belt || b.agent) b.theta += b.spin * (Math.sqrt(SUN_GM * b.orbit * (1 - ECC * ECC)) / radiusAt(b.orbit, b.theta) ** 2) * h;
        if (!b.agent) continue;
        if (lit && !b.entered) { b.theta = Math.atan2((b.y - cy) / (scale() * TILT), (b.x - cx) / scale()); b.entered = true; }
        if (!lit) b.entered = false;
        const [tx, ty] = lit ? project(b.orbit, b.theta) : [b.hx, b.hy];
        b.vx += ((tx - b.x) * K - b.vx * C) * h; b.vy += ((ty - b.y) * K - b.vy * C) * h;
        b.x += b.vx * h; b.y += b.vy * h;
      }
    }
  }

  function settled() {
    if (open || presence() > 0) return false;
    return bodies.every((b) => !b.agent || (Math.hypot(b.x - b.hx, b.y - b.hy) < 1 && Math.hypot(b.vx, b.vy) < 3));
  }

  function draw() {
    const [cx, cy] = center(), p = presence(), R = (notchW() / 2) * (world === "sky" ? p : 0.6 + 0.4 * p);
    const sky = ctx.createLinearGradient(0, 0, 0, H);
    sky.addColorStop(0, look.sky[0]); sky.addColorStop(0.6, look.sky[1]); sky.addColorStop(1, look.sky[2]);
    ctx.fillStyle = sky; ctx.fillRect(0, 0, W, H);
    for (const s of stars) {
      ctx.fillStyle = `rgba(${look.star},${s.a * (look === LOOKS.light ? 0.25 : 1)})`;
      ctx.beginPath(); ctx.arc(s.x * W, s.y * H, s.s * Math.max(u, 0.6), 0, TAU); ctx.fill();
    }
    if (world === "sky") {
      ctx.fillStyle = look.hills[0];
      ctx.beginPath(); ctx.moveTo(0, H * 0.86); ctx.quadraticCurveTo(W * 0.3, H * 0.76, W * 0.6, H * 0.8); ctx.quadraticCurveTo(W * 0.85, H * 0.83, W, H * 0.74); ctx.lineTo(W, H); ctx.lineTo(0, H); ctx.fill();
      ctx.fillStyle = look.hills[1];
      ctx.beginPath(); ctx.moveTo(0, H * 0.93); ctx.quadraticCurveTo(W * 0.5, H * 0.86, W, H * 0.92); ctx.lineTo(W, H); ctx.lineTo(0, H); ctx.fill();
    }

    if (world === "solar") {
      for (const b of bodies) if (b.agent) {
        ctx.strokeStyle = `rgba(${look.ring},${0.22 * p})`; ctx.lineWidth = 1;
        ctx.beginPath(); ctx.ellipse(cx, cy + b.orbit * ECC * scale() * TILT, b.orbit * Math.sqrt(1 - ECC * ECC) * scale(), b.orbit * scale() * TILT, 0, 0, TAU); ctx.stroke();
      }
      for (const b of bodies) if (b.belt) {
        const [x, y] = project(b.orbit, b.theta);
        ctx.fillStyle = `rgba(${look.ring},${b.a * p})`; ctx.beginPath(); ctx.arc(x, y, b.s * u, 0, TAU); ctx.fill();
      }
      if (p > 0.01) {
        const corona = ctx.createRadialGradient(cx, cy, R * 0.8, cx, cy, R * 4.2);
        corona.addColorStop(0, `rgba(255,214,140,${0.75 * p})`); corona.addColorStop(0.35, `rgba(255,150,70,${0.25 * p})`); corona.addColorStop(1, "rgba(255,120,40,0)");
        ctx.fillStyle = corona; ctx.beginPath(); ctx.arc(cx, cy, R * 4.2, 0, TAU); ctx.fill();
        const disk = ctx.createRadialGradient(cx, cy - R * 0.2, 0, cx, cy, R);
        disk.addColorStop(0, `rgba(255,252,235,${p})`); disk.addColorStop(0.7, `rgba(255,210,120,${p})`); disk.addColorStop(1, `rgba(255,150,60,${p})`);
        ctx.fillStyle = disk; ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI); ctx.fill();
      }
    } else {
      for (const b of bodies) if (!b.agent && !b.gone) {
        const dx = b.x - cx, dy = b.y - cy, r = Math.hypot(dx, dy) || 1, heat = R > 1 ? clamp((R * 3) / r - 0.8) : 0;
        const len = Math.min(40, Math.hypot(b.vx, b.vy) * 0.018 + (R > 1 ? clamp(((R * 2.2) / r) ** 3, 0, 14) * 2.5 : 0));
        const col = look === LOOKS.light ? `rgba(30,40,70,${b.a * b.fade * 0.5})` : `rgba(255,${Math.round(255 - 120 * heat)},${Math.round(255 - 200 * heat)},${b.a * b.fade})`;
        if (len > 1.2) {
          ctx.strokeStyle = col; ctx.lineWidth = Math.max(0.6, b.s * u * 0.8); ctx.lineCap = "round";
          ctx.beginPath(); ctx.moveTo(b.x - (dx / r) * len * 0.5, b.y - (dy / r) * len * 0.5); ctx.lineTo(b.x + (dx / r) * len * 0.5, b.y + (dy / r) * len * 0.5); ctx.stroke();
        } else { ctx.fillStyle = col; ctx.beginPath(); ctx.arc(b.x, b.y, b.s * u * 0.8, 0, TAU); ctx.fill(); }
      }
    }

    const showLabels = W >= 520;
    for (const b of bodies) {
      if (!b.agent) continue;
      b.trail.push([b.x, b.y]); if (b.trail.length > 30) b.trail.shift();
      if (Math.hypot(b.vx, b.vy) > 8) for (let i = 1; i < b.trail.length; i++) {
        ctx.strokeStyle = b.glow + Math.round((i / b.trail.length) * 120).toString(16).padStart(2, "0");
        ctx.lineWidth = 2 * u * (i / b.trail.length); ctx.beginPath(); ctx.moveTo(...b.trail[i - 1]); ctx.lineTo(...b.trail[i]); ctx.stroke();
      }
      const size = (world === "solar" ? 11 : 6) * u, g = ctx.createRadialGradient(b.x, b.y, 0, b.x, b.y, size * 7);
      g.addColorStop(0, b.glow + "cc"); g.addColorStop(0.3, b.glow + "44"); g.addColorStop(1, b.glow + "00");
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(b.x, b.y, size * 7, 0, TAU); ctx.fill();
      if (world === "solar") {
        const globe = ctx.createRadialGradient(b.x - size * 0.35, b.y - size * 0.4, size * 0.1, b.x, b.y, size);
        globe.addColorStop(0, "#fff"); globe.addColorStop(0.35, b.color); globe.addColorStop(1, look === LOOKS.light ? "#3a3f4c" : "#05060a");
        ctx.fillStyle = globe; ctx.beginPath(); ctx.arc(b.x, b.y, size, 0, TAU); ctx.fill();
      } else {
        ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.arc(b.x, b.y, size, 0, TAU); ctx.fill();
        ctx.fillStyle = b.color; ctx.beginPath(); ctx.arc(b.x, b.y, size * 0.5, 0, TAU); ctx.fill();
      }
      if (showLabels && b.y > H * 0.08) {
        const inRow = world === "solar" && p < 0.5;
        ctx.font = `600 ${Math.max(10, 12 * u)}px -apple-system, system-ui, sans-serif`;
        ctx.textAlign = inRow ? "center" : "left"; ctx.textBaseline = "middle";
        ctx.fillStyle = b.glow === "#f5a524" ? (look === LOOKS.light ? "#a86200" : "#f5b94a") : look.ink;
        ctx.fillText(b.name, inRow ? b.x : b.x + size + 10 * u, inRow ? b.y + size + 14 * u : b.y);
      }
    }

    if (world === "sky" && R > 0.5) {
      const diskOut = R * 3.4;
      for (let i = 0; i < 60; i++) {
        const x0 = cx - diskOut + (i / 59) * diskOut * 2, rr = Math.abs(x0 - cx);
        if (rr < R * 1.02) continue;
        const heat = clamp(1 - (rr - R) / (diskOut - R)), th = R * 0.075 * (0.4 + heat);
        ctx.fillStyle = `rgba(255,${Math.round(170 + 70 * heat)},${Math.round(90 + 120 * heat)},${0.85 * heat * (x0 < cx ? 1 : 0.55) * p})`;
        ctx.fillRect(x0, cy - th, (diskOut * 2) / 59 + 1, th * 2);
      }
      for (let j = 0; j < 3; j++) {
        ctx.strokeStyle = `rgba(255,${200 - j * 30},${140 - j * 30},${(0.7 - j * 0.2) * p})`; ctx.lineWidth = (3.2 - j) * u;
        ctx.beginPath(); ctx.arc(cx, cy, R * (1.12 + j * 0.08), 0.05, Math.PI - 0.05); ctx.stroke();
      }
      ctx.fillStyle = "#000"; ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI); ctx.fill();
      const ring = ctx.createRadialGradient(cx, cy, R * 0.96, cx, cy, R * 1.06);
      ring.addColorStop(0, "rgba(255,240,210,0)"); ring.addColorStop(0.45, `rgba(255,240,210,${0.95 * p})`); ring.addColorStop(1, "rgba(255,200,140,0)");
      ctx.fillStyle = ring; ctx.beginPath(); ctx.arc(cx, cy, R * 1.06, 0, Math.PI); ctx.fill();
      ctx.fillStyle = "#000"; ctx.beginPath(); ctx.arc(cx, cy, R * 0.97, 0, Math.PI); ctx.fill();
    }
  }

  function frame(now) {
    const dt = Math.min(0.25, (now - lastFrame) / 1000 || 0); lastFrame = now;
    const steps = Math.max(1, Math.ceil(dt / 0.004));
    for (let i = 0; i < steps; i++) step(dt / steps);
    draw();
    if (!reduceMotion && visible && (!settled() || open)) { requestAnimationFrame(frame); } else running = false;
  }
  function kick() {
    if (reduceMotion) { stillFrame(); return; }
    if (running || !visible) return;
    running = true; lastFrame = performance.now(); requestAnimationFrame(frame);
  }
  // Reduce Motion: no bodies move; the hole or the sun simply appears or goes.
  function stillFrame() {
    time += 5;
    for (const b of bodies) if (b.agent) { b.x = b.hx; b.y = b.hy; b.vx = b.vy = 0; b.trail = []; }
    draw();
  }

  const openButton = document.getElementById("scene-open");
  function setOpen(next) {
    if (next === open) return;
    open = next;
    if (open) { openedAt = time; if (world === "sky") born = false; } else closedAt = time;
    root.classList.toggle("open", open);
    openButton.setAttribute("aria-pressed", String(open));
    openButton.textContent = open ? "Close the island" : "Open the island";
    kick();
  }
  function describe() {
    canvas.setAttribute("aria-label", world === "sky"
      ? `A living wallpaper, ${look === LOOKS.light ? "light" : "dark"}: agents as stars in a sky${open ? ", orbiting a black hole at the notch" : ""}`
      : `A living wallpaper, ${look === LOOKS.light ? "light" : "dark"}: agents as planets${open ? " orbiting the notch, lit as the sun" : " standing in rows"}`);
  }
  openButton.addEventListener("click", () => { setOpen(!open); describe(); });
  document.querySelectorAll("[data-world]").forEach((chip) => chip.addEventListener("click", () => {
    world = chip.dataset.world;
    document.querySelectorAll("[data-world]").forEach((c) => c.setAttribute("aria-pressed", String(c === chip)));
    open = false; root.classList.remove("open"); openButton.setAttribute("aria-pressed", "false"); openButton.textContent = "Open the island";
    time = 0; openedAt = closedAt = -99; reset(); describe(); draw(); kick();
  }));
  document.querySelectorAll("[data-look]").forEach((chip) => chip.addEventListener("click", () => {
    look = LOOKS[chip.dataset.look];
    document.querySelectorAll("[data-look]").forEach((c) => c.setAttribute("aria-pressed", String(c === chip)));
    root.style.background = look.sky[0]; describe(); draw();
  }));
  // Hovering the notch opens the island, as on a Mac.
  root.addEventListener("pointermove", (e) => {
    if (e.pointerType !== "mouse") return;
    const r = root.getBoundingClientRect(), x = (e.clientX - r.left) / r.width, y = (e.clientY - r.top) / r.height;
    if (y < 0.06 && Math.abs(x - 0.5) < 0.1 && !open) { stopTour(); setOpen(true); describe(); }
  });

  let visible = false;
  new IntersectionObserver((entries) => {
    visible = entries[0].isIntersecting;
    if (visible) { kick(); startTour(); }
  }).observe(root);

  // A guided tour: a fingertip taps through the controls while the demo is on screen, until the visitor takes over.
  const controls = document.querySelector(".scene-controls");
  const hint = document.getElementById("scene-hint");
  const finger = document.createElement("span");
  finger.className = "tour-finger"; finger.setAttribute("aria-hidden", "true");
  controls.appendChild(finger);
  const TOUR = [
    ["#scene-open", 800], ["#scene-open", 3500], ['[data-world="solar"]', 1600], ["#scene-open", 1200],
    ['[data-look="light"]', 3000], ["#scene-open", 2200], ['[data-world="sky"]', 1800], ['[data-look="dark"]', 1000],
  ];
  let tourStep = 0, tourTimer = null, touring = false, tourStopped = reduceMotion;
  function startTour() {
    if (tourStopped || touring) return;
    touring = true; hint.hidden = false; schedule();
  }
  function schedule() {
    const [, delay] = TOUR[tourStep % TOUR.length];
    tourTimer = setTimeout(tapNext, delay);
  }
  function tapNext() {
    if (tourStopped) return;
    if (!visible) { touring = false; return; }   // resumes from this step when the demo is back on screen
    const target = document.querySelector(TOUR[tourStep % TOUR.length][0]);
    const box = controls.getBoundingClientRect(), t = target.getBoundingClientRect();
    finger.style.transform = `translate(${t.left - box.left + t.width / 2}px, ${t.top - box.top + t.height / 2}px)`;
    finger.classList.add("shown");
    tourTimer = setTimeout(() => {
      if (tourStopped) return;
      finger.classList.add("press");
      target.classList.add("tapping");
      const ripple = document.createElement("span");
      ripple.className = "tap-ripple"; target.appendChild(ripple);
      setTimeout(() => ripple.remove(), 600);
      setTimeout(() => { finger.classList.remove("press"); target.classList.remove("tapping"); }, 220);
      target.click();
      tourStep++;
      schedule();
    }, 450);
  }
  function stopTour() {
    tourStopped = true; touring = false; clearTimeout(tourTimer);
    finger.classList.remove("shown", "press"); hint.hidden = true;
  }
  // The visitor's own taps and clicks take over from the tour.
  controls.addEventListener("click", (e) => { if (e.isTrusted && e.target.closest("button")) stopTour(); }, true);
  document.getElementById("scene-stop").addEventListener("click", stopTour);
  new ResizeObserver(() => { resize(); draw(); }).observe(root);
  resize(); draw();
})();
