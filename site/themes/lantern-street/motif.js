// Lantern street's hero art: strings of paper lanterns across a night street, each a session in its state's
// colour. The big lantern in the middle is the session the demo shows, lit in its current colour (--state).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  let seed = 7;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const cols = ["#d97757", "#ffad1f", "#3ccf73", "#f0452f", "#4f8df7", "#10a37f"];
  const lantern = (x, y, sc, c, cls = "") => `<g class="lan">
      <ellipse class="${cls ? "now-glow" : ""}" cx="${x}" cy="${y + 27 * sc}" rx="${58 * sc}" ry="${58 * sc}" fill="${c}" opacity=".13"/>
      <rect x="${x - 8 * sc}" y="${y}" width="${16 * sc}" height="${5 * sc}" fill="#2a1a14"/>
      <ellipse class="${cls}" cx="${x}" cy="${y + 27 * sc}" rx="${19 * sc}" ry="${23 * sc}" fill="${c}"/>
      <ellipse cx="${x}" cy="${y + 29 * sc}" rx="${9 * sc}" ry="${12 * sc}" fill="#fff" opacity=".42"/>
      <rect x="${x - 6 * sc}" y="${y + 49 * sc}" width="${12 * sc}" height="${4 * sc}" fill="#2a1a14"/></g>`;
  let s = "";
  for (let i = 0; i < 70; i++) s += `<circle cx="${(rnd() * 1200).toFixed(0)}" cy="${(rnd() * 330).toFixed(0)}" r="${(rnd() * 1.2 + 0.3).toFixed(1)}" fill="#f6e7c8" opacity="${(rnd() * 0.45 + 0.1).toFixed(2)}"/>`;
  [[-40, 56, 1240, 40, 110, 12], [-40, 146, 1240, 124, 84, 9], [-40, 48, 1240, 200, 46, 7]].forEach(([x1, y1, x2, y2, sag, n], si) => {
    let d = "";
    const pts = [];
    for (let i = 0; i <= 60; i++) {
      const t = i / 60, x = x1 + (x2 - x1) * t, y = y1 + (y2 - y1) * t + sag * 4 * t * (1 - t);
      d += (i ? "L" : "M") + x.toFixed(1) + " " + y.toFixed(1);
      pts.push([x, y]);
    }
    s += `<path d="${d}" fill="none" stroke="#6b5a4a" stroke-width="1.5"/>`;
    for (let k = 1; k < n; k++) {
      const [x, y] = pts[Math.round((k * 60) / n)];
      if (si === 0 && Math.abs(x - 600) < 60) continue;
      const c = si === 0 ? cols[k % 4] : rnd() < 0.6 ? "#e8c58a" : cols[Math.floor(rnd() * 6)];
      s += lantern(+x.toFixed(1), +y.toFixed(1), 1 - si * 0.22, c);
    }
  });
  s += `<path d="M600 0 V108" stroke="#6b5a4a" stroke-width="1.5"/>`;
  s += lantern(600, 108, 2.6, "#ffad1f", "now");
  art.innerHTML = `<svg class="lnt-art" viewBox="0 0 1200 330" preserveAspectRatio="xMidYMid slice" role="presentation">${s}</svg>`;
})();
