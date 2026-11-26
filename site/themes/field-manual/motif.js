// Field manual's hero art: Fig. 1, a callout drawing of the notch island and its menu. The orb and the highlighted
// row take the demo's current state colour (--state on <html>, via theme.css); the row's label follows data-mood.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const lbl = { working: "WORKING", waiting: "NEEDS YOU", done: "DONE", error: "ERROR" };
  let hatch = "";
  for (let x = 210; x < 1560; x += 14) hatch += `M${x} 86 l-${Math.min(x - 210, 434)} ${Math.min(x - 210, 434)}`;
  const co = (x, y, a, t1, t2, lx, lw) =>
    `<text x="${x}" y="${y}" font-size="13" font-weight="500" letter-spacing="1">${a}</text>` +
    `<line x1="${x}" y1="${y + 8}" x2="${x + 170}" y2="${y + 8}" stroke="#161614" stroke-width="1.5"/>` +
    `<line x1="${lx}" y1="${y + 8}" x2="${lx + lw}" y2="${y + 8}" stroke="#161614" stroke-width="1.5"/>` +
    `<text x="${x}" y="${y + 30}" font-size="13">${t1}</text><text x="${x}" y="${y + 50}" font-size="13">${t2}</text>`;
  art.innerHTML = `<svg class="fm-fig" viewBox="0 0 1320 520" preserveAspectRatio="xMidYMin slice" role="presentation">
    <defs><clipPath id="fmc"><rect x="210" y="86" width="900" height="434" rx="18"/></clipPath></defs>
    <rect x="0" y="0" width="236" height="30" fill="#161614"/>
    <text x="12" y="20" font-size="12" letter-spacing="1" fill="#efede6" style="fill:#efede6">FIG. 1 — THE NOTCH ISLAND</text>
    <path d="${hatch}" stroke="#16161414" stroke-width="2" clip-path="url(#fmc)"/>
    <path d="M210 520 V104 a18 18 0 0 1 18 -18 H1092 a18 18 0 0 1 18 18 V520" fill="none" stroke="#161614" stroke-width="1.5"/>
    <path d="M495 85 h330 v40 a16 16 0 0 1 -16 16 h-298 a16 16 0 0 1 -16 -16 z" fill="#161614"/>
    <circle class="st" cx="525" cy="113" r="8"/>
    <text id="fm-n" x="800" y="118" font-size="12" letter-spacing="1" text-anchor="end" style="fill:#efede6">1 SESSION</text>
    <g transform="translate(450 180)">
      <rect width="420" height="138" fill="#efede6" stroke="#161614" stroke-width="1.5"/>
      <rect class="st" x="0.75" y="0.75" width="418.5" height="45"/>
      <text x="16" y="28" font-size="13">CLAUDE · api-server</text><text id="fm-s" x="404" y="28" font-size="13" text-anchor="end">WORKING</text>
      <line x1="0" y1="92" x2="420" y2="92" stroke="#16161433"/>
      <text x="16" y="74" font-size="13">CODEX · web-checkout</text><text x="404" y="74" font-size="13" text-anchor="end">WORKING</text>
      <text x="16" y="120" font-size="13">GEMINI · docs</text><text x="404" y="120" font-size="13" text-anchor="end">DONE</text>
    </g>
    ${co(24, 105, "A · STATE ORB", "One colour; the most", "urgent session wins.", 194, 323)}
    ${co(1126, 105, "B · HOVER", "Hover the island to", "see every session.", 826, 300)}
    ${co(24, 262, "C · CLICK TO RETURN", "The exact tab, pane,", "chat or thread.", 194, 256)}
  </svg>`;
  const s = document.getElementById("fm-s");
  const set = () => { s.textContent = lbl[document.documentElement.dataset.mood] || "WORKING"; };
  set();
  new MutationObserver(set).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
