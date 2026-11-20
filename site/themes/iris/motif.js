// Iris's hero art: an ophthalmic plate. A canvas iris whose stroma carries four sectors of pigment, one per state
// (needs you upper left, error upper right, done lower left, working lower right), under a measuring ring with
// degree ticks and lettered keys. An oxblood marker on the ring turns to the demo's current state (theme.css,
// from data-mood on <html>, set by main.js). The iris is drawn once, so reduced motion shows a still plate.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const N = 1000, cx = 500, cy = 500, R0 = 120, R1 = 380;
  art.innerHTML = `<div class="ir-plate"><canvas width="${N}" height="${N}"></canvas><svg viewBox="0 0 ${N} ${N}" role="presentation"></svg></div>`;
  const c = art.querySelector("canvas").getContext("2d");
  let seed = 3;
  const R = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const SEC = [[180, 270, [213, 138, 16]], [270, 360, [194, 47, 58]], [90, 180, [47, 148, 96]], [0, 90, [63, 111, 196]]];
  const col = (a) => { a = ((a % 360) + 360) % 360; for (const s of SEC) if (a >= s[0] && a < s[1]) return s[2]; return SEC[0][2]; };
  c.fillStyle = "#25110f"; c.beginPath(); c.arc(cx, cy, R1 + 8, 0, 7); c.fill();
  for (let i = 0; i < 4200; i++) {
    const a = R() * 360, b = col(a + (R() - 0.5) * 16), l = 0.45 + R(), ar = (a * Math.PI) / 180;
    const r0 = R0 - 4 + R() * 26, r1 = R1 * (0.55 + R() * 0.45), w = (R() - 0.5) * 0.06, m = (r0 + r1) / 2;
    c.strokeStyle = `rgba(${Math.min(255, b[0] * l) | 0},${Math.min(255, b[1] * l) | 0},${Math.min(255, b[2] * l) | 0},${0.25 + R() * 0.5})`;
    c.lineWidth = 0.6 + R() * 2;
    c.beginPath(); c.moveTo(cx + r0 * Math.cos(ar), cy + r0 * Math.sin(ar));
    c.quadraticCurveTo(cx + m * Math.cos(ar + w), cy + m * Math.sin(ar + w), cx + r1 * Math.cos(ar), cy + r1 * Math.sin(ar)); c.stroke();
  }
  for (let i = 0; i < 700; i++) {
    const a = R() * 6.283, r = 180 + R() * 34 + Math.sin(a * 9) * 8;
    c.strokeStyle = `rgba(255,240,215,${0.12 + R() * 0.3})`; c.lineWidth = 1 + R() * 1.4;
    c.beginPath(); c.moveTo(cx + (r - 18) * Math.cos(a), cy + (r - 18) * Math.sin(a)); c.lineTo(cx + (r + 12) * Math.cos(a + 0.02), cy + (r + 12) * Math.sin(a + 0.02)); c.stroke();
  }
  let g = c.createRadialGradient(cx, cy, R1 - 60, cx, cy, R1 + 8);
  g.addColorStop(0, "rgba(37,17,15,0)"); g.addColorStop(1, "rgba(37,17,15,.85)");
  c.fillStyle = g; c.beginPath(); c.arc(cx, cy, R1 + 8, 0, 7); c.fill();
  g = c.createRadialGradient(cx, cy, R0 - 10, cx, cy, R0 + 42);
  g.addColorStop(0, "rgba(20,8,8,.9)"); g.addColorStop(1, "rgba(20,8,8,0)");
  c.fillStyle = g; c.beginPath(); c.arc(cx, cy, R0 + 42, 0, 7); c.fill();
  c.fillStyle = "#0c0505"; c.beginPath(); c.arc(cx, cy, R0, 0, 7); c.fill();
  c.fillStyle = "rgba(255,255,255,.9)"; c.beginPath(); c.ellipse(cx - 50, cy - 56, 28, 18, -0.6, 0, 7); c.fill();
  c.fillStyle = "rgba(255,255,255,.5)"; c.beginPath(); c.arc(cx + 56, cy + 54, 7, 0, 7); c.fill();
  // overlay: measuring ring, degree ticks, lettered keys, and the marker
  const P = (r, a) => [cx + r * Math.cos((a * Math.PI) / 180), cy + r * Math.sin((a * Math.PI) / 180)];
  const f = (n) => n.toFixed(1);
  let s = `<g fill="none" stroke="#6a1c28"><circle cx="${cx}" cy="${cy}" r="420" stroke-width="1.2"/>`;
  for (let a = 0; a < 360; a += 3) { const [x1, y1] = P(420, a), [x2, y2] = P(a % 15 ? 428 : 440, a); s += `<line x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}"/>`; }
  s += `</g><g font-size="17" fill="#6a1c28" text-anchor="middle">`;
  [[0, "0°"], [90, "90°"], [180, "180°"], [270, "270°"]].forEach(([a, t]) => { const [x, y] = P(470, a); s += `<text x="${f(x)}" y="${f(y + 6)}">${t}</text>`; });
  s += `</g>`;
  [[45, "a"], [225, "b"], [135, "c"], [315, "d"]].forEach(([a, k]) => {
    const [x, y] = P(300, a), [x2, y2] = P(406, a);
    s += `<line x1="${f(x)}" y1="${f(y)}" x2="${f(x2)}" y2="${f(y2)}" stroke="#fff" stroke-width="4" opacity=".5"/><line x1="${f(x)}" y1="${f(y)}" x2="${f(x2)}" y2="${f(y2)}" stroke="#25110f" stroke-width="1.6"/>`;
    s += `<circle cx="${f(x)}" cy="${f(y)}" r="19" fill="#f1dcd2" stroke="#25110f" stroke-width="1.6"/><text x="${f(x)}" y="${f(y + 7)}" text-anchor="middle" font-size="20" fill="#25110f">${k}</text>`;
  });
  s += `<g class="ir-mark"><polygon points="${cx + 452},${cy} ${cx + 476},${cy - 13} ${cx + 476},${cy + 13}" fill="#6a1c28"/></g>`;
  art.querySelector("svg").innerHTML = s;
})();
