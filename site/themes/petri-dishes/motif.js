// Petri dishes' hero art: four glass dishes cascading across the bench, one culture per state — a pulsing amber
// colony (needs you), a ragged red streak with a clear zone (error), an even green lawn (done) and colonies
// still growing in Claude's colour (working) — each with a torn tape label in marker. The dish for the demo's
// current state gets a marker ring (theme.css, from data-mood on <html>, set by main.js). Static otherwise.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  let seed = 21;
  const R = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const f = (n) => n.toFixed(1);
  const D = [
    { n: "Needs you", k: "dish A", c: "#f09c00", t: "#8a5a00", x: 420, y: 150, rot: -3 },
    { n: "Error", k: "dish B", c: "#de3b3b", t: "#a3201f", x: 170, y: 250, rot: 2.5 },
    { n: "Done", k: "dish C", c: "#19a35b", t: "#0f6b3a", x: 440, y: 430, rot: -2 },
    { n: "Working", k: "dish D", c: "#d9734f", t: "#9c4424", x: 180, y: 500, rot: 3 },
  ];
  const r = 112, ri = 102;
  let s = `<defs><filter id="pd-sh" x="-30%" y="-30%" width="160%" height="170%"><feGaussianBlur stdDeviation="10"/></filter><filter id="pd-fz"><feGaussianBlur stdDeviation=".8"/></filter>`;
  D.forEach((d, i) => (s += `<radialGradient id="pd-c${i}"><stop offset="0" stop-color="#fff" stop-opacity=".85"/><stop offset=".35" stop-color="${d.c}"/><stop offset=".85" stop-color="${d.c}" stop-opacity=".85"/><stop offset="1" stop-color="${d.c}" stop-opacity=".25"/></radialGradient><clipPath id="pd-k${i}"><circle cx="${d.x}" cy="${d.y}" r="${ri}"/></clipPath>`));
  s += "</defs>";
  D.forEach((d, i) => {
    const { x, y, c } = d;
    let g = "";
    if (i === 0) { [80, 62, 46].forEach((q, j) => (g += `<circle cx="${x - 6}" cy="${y - 10}" r="${q}" fill="${c}" opacity="${0.12 + j * 0.1}"/>`)); g += `<circle cx="${x - 6}" cy="${y - 10}" r="34" fill="url(#pd-c0)"/>`; }
    else if (i === 1) {
      g += `<path d="M${x - 80} ${y - 50} q32 -22 60 6 t54 0 t48 -6" fill="none" stroke="${c}" stroke-width="9" stroke-linecap="round" opacity=".55"/>`;
      for (let k = 0; k < 18; k++) { const a = R() * 6.28, q = R() * 80; g += `<circle cx="${f(x + q * Math.cos(a))}" cy="${f(y - 10 + q * Math.sin(a) * 0.7)}" r="${f(3 + R() * 9)}" fill="url(#pd-c1)"/>`; }
      g += `<circle cx="${x + 36}" cy="${y - 4}" r="25" fill="#f1eccb"/><circle cx="${x + 36}" cy="${y - 4}" r="25" fill="none" stroke="#0f1f1b" stroke-dasharray="3 4" stroke-opacity=".5"/>`;
    } else if (i === 2) { g += `<circle cx="${x}" cy="${y}" r="${ri}" fill="${c}" opacity=".3"/>`; for (let k = 0; k < 120; k++) { const a = R() * 6.28, q = Math.sqrt(R()) * 96; g += `<circle cx="${f(x + q * Math.cos(a))}" cy="${f(y + q * Math.sin(a))}" r="${f(3.5 + R() * 5)}" fill="url(#pd-c2)" opacity=".9"/>`; } }
    else { for (let k = 0; k < 11; k++) { const a = R() * 6.28, q = Math.sqrt(R()) * 84, cx = x + q * Math.cos(a), cy = y + q * Math.sin(a) * 0.8, rr = 5 + R() * 13; g += `<circle cx="${f(cx)}" cy="${f(cy)}" r="${f(rr + 8)}" fill="none" stroke="${c}" stroke-opacity=".35" stroke-width="1.3"/><circle cx="${f(cx)}" cy="${f(cy)}" r="${f(rr + 4)}" fill="${c}" opacity=".18"/><circle cx="${f(cx)}" cy="${f(cy)}" r="${f(rr)}" fill="url(#pd-c3)"/>`; } }
    s += `<g class="pd-d${i}"><circle cx="${x + 6}" cy="${y + 14}" r="${r}" fill="#0f1f1b" opacity=".26" filter="url(#pd-sh)"/>
      <circle cx="${x}" cy="${y}" r="${r}" fill="#fff" fill-opacity=".75" stroke="#fff" stroke-width="2.5"/><circle cx="${x}" cy="${y}" r="${ri + 4}" fill="#f1eccb" stroke="#0f1f1b" stroke-opacity=".25"/>
      <g clip-path="url(#pd-k${i})" filter="url(#pd-fz)">${g}</g>
      <path d="M${x - 92} ${y - 50} A${ri} ${ri} 0 0 1 ${x - 32} ${y - 96}" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round" opacity=".8"/>
      <circle cx="${x}" cy="${y}" r="${r}" fill="none" stroke="#0f1f1b" stroke-opacity=".35" stroke-width="1.2"/>
      <path class="pd-ring" d="M${x - r - 10} ${y + 6} C${x - r - 12} ${y - r - 18} ${x + r + 22} ${y - r - 14} ${x + r + 10} ${y + 4} S${x - r + 4} ${y + r + 26} ${x - r - 4} ${y - 18}" fill="none" stroke="#0f1f1b" stroke-width="3.5" stroke-linecap="round"/>
      <g transform="translate(${x - 70} ${y + 56}) rotate(${d.rot})"><path d="M0 2 L5 0 L9 3 L14 0 L140 0 L140 40 L135 42 L130 39 L125 42 L0 42Z" fill="#fffbe6"/>
        <text class="mono" x="8" y="13" font-size="8.5" letter-spacing="1.3" fill="#0f1f1b">${d.k.toUpperCase()}</text><line x1="8" y1="17" x2="132" y2="17" stroke="#0f1f1b" stroke-width="1"/>
        <text class="mk" x="8" y="36" font-size="22" fill="${d.t}">${d.n}</text></g></g>`;
  });
  art.innerHTML = `<svg class="pd-bench" viewBox="0 0 600 620" role="presentation">${s}</svg>`;
})();
