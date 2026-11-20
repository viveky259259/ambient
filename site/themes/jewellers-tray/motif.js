// Jeweller's tray's hero art: a dark lined tray of four compartments, each holding a brilliant-cut stone in a
// four-claw gold bezel, one per state. The stone of the demo's current mood catches the light: a glint and a
// brighter halo (theme.css, data-mood on <html>).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  let seed = 11;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const pt = (r, a) => [Math.sin((a * Math.PI) / 180) * r, -Math.cos((a * Math.PI) / 180) * r];
  const gem = (hue, sat, id, mood) => {
    const R = 100, T = [], B = [], G = [];
    for (let k = 0; k < 8; k++) { T.push(pt(R * 0.47, 22.5 + 45 * k)); B.push(pt(R * 0.74, 45 * k)); }
    for (let j = 0; j < 16; j++) G.push(pt(R, 22.5 * j));
    const lit = (ps, base) => {
      const cx = ps.reduce((s, p) => s + p[0], 0) / ps.length, cy = ps.reduce((s, p) => s + p[1], 0) / ps.length;
      return Math.max(12, Math.min(86, base + ((-cx - cy) / (R * 1.4)) * 24 + (rnd() - 0.5) * 30));
    };
    const poly = (ps, l) => `<polygon points="${ps.map((p) => p[0].toFixed(1) + "," + p[1].toFixed(1)).join(" ")}" fill="hsl(${hue} ${sat}% ${l.toFixed(0)}%)" stroke="hsl(${hue} ${sat}% ${Math.min(92, l + 16).toFixed(0)}%)" stroke-width=".6" stroke-opacity=".6"/>`;
    const f = (ps, b) => poly(ps, lit(ps, b));
    let h = `<circle r="128" fill="url(#jt-h${id})"/><circle r="${R + 8}" fill="#0d0511"/><circle r="${R + 8}" fill="none" stroke="url(#jt-au)" stroke-width="8"/>`;
    for (let k = 0; k < 8; k++) {
      const n = (k + 1) % 8;
      h += f([B[k], T[k], B[n], G[(2 * k + 1) % 16]], 46) + f([T[k], T[n], B[n]], 58) + f([B[k], G[2 * k], G[2 * k + 1]], 36) + f([B[n], G[2 * k + 1], G[(2 * k + 2) % 16]], 36);
    }
    for (let k = 0; k < 8; k++) h += poly([[0, 0], T[k], T[(k + 1) % 8]], Math.max(30, Math.min(84, 58 + (rnd() - 0.5) * 34)));
    h += `<path d="M-34,-38 L-7,-45 L-26,-15 Z" fill="#fff" opacity=".55"/>`;
    for (let k = 0; k < 4; k++) { const p = pt(R + 4, 45 + 90 * k); h += `<circle cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="11" fill="url(#jt-au)" stroke="#6b4c18"/>`; }
    h += `<g class="jt-glint ${mood}"><circle r="132" fill="url(#jt-h${id})"/><path d="M52,-74 L57,-56 L75,-51 L57,-46 L52,-28 L47,-46 L29,-51 L47,-56 Z" fill="#fff"/><circle cx="52" cy="-51" r="10" fill="#fff" opacity=".35"/></g>`;
    return h;
  };
  const S = [["I", "Working", 218, 78, "working"], ["II", "Needs you", 38, 96, "waiting"], ["III", "Done", 152, 72, "done"], ["IV", "Error", 352, 82, "error"]];
  let defs = `<linearGradient id="jt-au" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fbeeb9"/><stop offset=".35" stop-color="#b98a3a"/><stop offset=".6" stop-color="#f3d98d"/><stop offset="1" stop-color="#8c6524"/></linearGradient>
    <linearGradient id="jt-tray" x1="0" y1="0" x2=".4" y2="1"><stop offset="0" stop-color="#1d0c24"/><stop offset="1" stop-color="#120716"/></linearGradient>
    <filter id="jt-in" x="-5%" y="-5%" width="110%" height="110%"><feDropShadow dx="0" dy="14" stdDeviation="16" flood-color="#000" flood-opacity=".7"/></filter>`;
  let slots = "";
  S.forEach(([n, name, hue, sat, mood], i) => {
    defs += `<radialGradient id="jt-h${i}"><stop offset="0" stop-color="hsl(${hue} ${sat}% 60%)" stop-opacity=".6"/><stop offset="1" stop-color="hsl(${hue} ${sat}% 50%)" stop-opacity="0"/></radialGradient>`;
    const cx = 170 + (i % 2) * 300, cy = 200 + Math.floor(i / 2) * 400;
    slots += `<g transform="translate(${cx},${cy})">${gem(hue, sat, i, mood)}</g>
      <text x="${cx}" y="${cy + 160}" text-anchor="middle" font-family="Martian Mono, monospace" font-size="11" letter-spacing="3" fill="#dcb96c">STONE ${n}</text>
      <text x="${cx}" y="${cy + 206}" text-anchor="middle" font-family="Italiana, Didot, serif" font-size="44" fill="#fbf3e6">${name}</text>`;
  });
  art.innerHTML = `<svg viewBox="0 0 640 860" role="presentation"><defs>${defs}</defs>
    <rect x="10" y="20" width="620" height="820" rx="26" fill="#0b0410" filter="url(#jt-in)"/>
    <rect x="10" y="20" width="620" height="820" rx="26" fill="url(#jt-tray)"/>
    <rect x="24" y="34" width="592" height="792" rx="16" fill="none" stroke="#dcb96c" stroke-opacity=".45" stroke-dasharray="4 4"/>
    <path d="M320,20 V840 M10,430 H630" stroke="#dcb96c" stroke-opacity=".2"/>
    ${slots}
  </svg>`;
})();
