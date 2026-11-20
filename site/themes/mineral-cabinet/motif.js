// Mineral cabinet's hero art: a walnut drawer of four cells, each holding a cluster of faceted crystals in a
// state's colour with its typed label. The cell of the demo's current state (data-mood on <html>) is outlined.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const S = [
    ["waiting", "I", "Needs you", "var. citrine", [227, 154, 18]],
    ["error", "II", "Error", "var. ruby", [196, 38, 58]],
    ["done", "III", "Done", "var. emerald", [31, 154, 91]],
    ["working", "IV", "Working", "var. rhodochrosite", [200, 103, 63]],
  ];
  let seed = 11;
  const R = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const sh = (c, f) => `rgb(${c.map((v) => Math.max(0, Math.min(255, f > 1 ? v + (255 - v) * (f - 1) : v * f)) | 0).join(",")})`;
  const prism = (cx, by, w, h, rot, c) => {
    const t = h * 0.2, a = w * 0.28, top = cx + w * 0.05;
    const L = cx - w / 2, A = cx - a / 2, B = cx + a, Rr = cx + w / 2;
    return `<g transform="rotate(${rot.toFixed(1)} ${cx.toFixed(0)} ${by})">
      <polygon points="${L},${by} ${L},${by - h + t} ${A},${by - h + t * 0.55} ${A},${by}" fill="${sh(c, 0.55)}"/>
      <polygon points="${A},${by} ${A},${by - h + t * 0.55} ${B},${by - h + t * 0.8} ${B},${by}" fill="${sh(c, 1)}"/>
      <polygon points="${B},${by} ${B},${by - h + t * 0.8} ${Rr},${by - h + t * 1.2} ${Rr},${by}" fill="${sh(c, 1.45)}"/>
      <polygon points="${L},${by - h + t} ${A},${by - h + t * 0.55} ${top},${by - h - t * 0.2}" fill="${sh(c, 0.75)}"/>
      <polygon points="${A},${by - h + t * 0.55} ${B},${by - h + t * 0.8} ${top},${by - h - t * 0.2}" fill="${sh(c, 1.25)}"/>
      <polygon points="${B},${by - h + t * 0.8} ${Rr},${by - h + t * 1.2} ${top},${by - h - t * 0.2}" fill="${sh(c, 1.7)}"/></g>`;
  };
  const round = (s) => s.replace(/(\d+\.\d{2,})/g, (m) => (+m).toFixed(1));
  const at = [[24, 24], [390, 24], [24, 452], [390, 452]], cw = 346, ch = 404;
  let cells = "";
  S.forEach(([mood, no, name, vr, c], i) => {
    const [x, y] = at[i], mid = x + cw / 2, base = y + 250;
    const P = [];
    for (let k = 0; k < 8; k++) P.push({ x: mid + (R() - 0.5) * 140, w: 30 + R() * 38, h: 90 + R() * 130, r: (R() - 0.5) * 36 });
    P.push({ x: mid, w: 62, h: 220, r: -4 + i * 3 });
    let g = "";
    P.sort((p, q) => q.h - p.h).forEach((p) => { g += prism(p.x, base, p.w, p.h, p.r, c); });
    cells += `<g class="cell" data-m="${mood}">
      <rect x="${x}" y="${y}" width="${cw}" height="${ch}" fill="#f6efdf" stroke="#2c1c13"/>
      <rect x="${x}" y="${y}" width="${cw}" height="18" fill="url(#mnl-sh)"/>
      <ellipse cx="${mid}" cy="${base + 6}" rx="130" ry="16" fill="#2c1c13" opacity=".2"/>
      ${round(g)}
      <polygon points="${mid - 140},${base} ${mid - 112},${base - 20} ${mid - 60},${base - 10} ${mid},${base - 24} ${mid + 62},${base - 8} ${mid + 112},${base - 18} ${mid + 142},${base + 2} ${mid + 112},${base + 20} ${mid - 104},${base + 22}" fill="#8b7a63"/>
      <polygon points="${mid - 140},${base} ${mid - 112},${base - 20} ${mid - 60},${base - 10} ${mid - 34},${base + 4} ${mid - 104},${base + 22}" fill="#6f604d"/>
      <rect x="${x + 22}" y="${y + 290}" width="${cw - 44}" height="94" fill="#fffaf0" stroke="#1d1612"/>
      <text class="no" x="${x + 36}" y="${y + 310}">SPECIMEN ${no}</text>
      <line x1="${x + 36}" x2="${x + cw - 36}" y1="${y + 318}" y2="${y + 318}" stroke="#1d1612"/>
      <text class="nm" x="${x + 36}" y="${y + 352}">${name}</text>
      <text class="vr" x="${x + 36}" y="${y + 374}">${vr}</text>
      <rect class="lit" x="${x + 3}" y="${y + 3}" width="${cw - 6}" height="${ch - 6}" fill="none" stroke-width="5" style="stroke:rgb(${c.join(",")})"/></g>`;
  });
  art.innerHTML = `<svg class="mnl" viewBox="0 0 760 880" role="presentation">
    <defs><linearGradient id="mnl-sh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2c1c13" stop-opacity=".3"/><stop offset="1" stop-color="#2c1c13" stop-opacity="0"/></linearGradient>
      <pattern id="mnl-grain" width="23" height="10" patternUnits="userSpaceOnUse" patternTransform="rotate(92)"><rect width="2" height="10" fill="#000" opacity=".12"/><rect x="9" width="2" height="10" fill="#ffdcaa" opacity=".06"/></pattern></defs>
    <rect width="760" height="880" fill="#4a3122"/><rect width="760" height="880" fill="url(#mnl-grain)"/>
    <rect x="1.5" y="1.5" width="757" height="877" fill="none" stroke="#2c1c13" stroke-width="3"/><rect x="6" y="6" width="748" height="868" fill="none" stroke="#6a4833" stroke-width="3"/>
    ${cells}</svg>`;
  const sync = () => {
    const m = document.documentElement.dataset.mood || "waiting";
    art.querySelectorAll(".cell").forEach((g) => g.classList.toggle("on", g.dataset.m === m));
  };
  sync();
  new MutationObserver(sync).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
