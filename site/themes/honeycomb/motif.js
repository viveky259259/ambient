// Honeycomb's hero art: a patch of brood comb. Most cells are quiet wax, capped or open; the lit ones are sessions,
// glowing in their state's colour (working cells in their agent's colour). Cells in the demo's current state
// pulse (theme.css, from data-mood on <html>, set by main.js); with reduced motion they simply glow.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const css = getComputedStyle(document.documentElement);
  const v = (n, f) => css.getPropertyValue(n).trim() || f;
  const C = { c: v("--claude", "#e07a52"), x: v("--codex", "#12b08a"), g: v("--gemini", "#6aa7ff"), n: v("--waiting", "#ff9a1f"), d: v("--done", "#45d483"), e: v("--error", "#ff5548") };
  const cls = { c: "hc-w", x: "hc-w", g: "hc-w", n: "hc-n", d: "hc-d", e: "hc-e" };
  const hex = (cx, cy, r) => {
    const p = [];
    for (let i = 0; i < 6; i++) { const a = (Math.PI / 3) * i + Math.PI / 6; p.push(`${(cx + r * Math.cos(a)).toFixed(1)},${(cy + r * Math.sin(a)).toFixed(1)}`); }
    return p.join(" ");
  };
  let s = "<defs>";
  for (const k in C) s += `<radialGradient id="hc-o${k}"><stop offset="0" stop-color="#fff"/><stop offset=".32" stop-color="${C[k]}"/><stop offset="1" stop-color="${C[k]}" stop-opacity="0"/></radialGradient>`;
  s += "</defs>";
  const r = 46, w = Math.sqrt(3) * r;
  const lit = { "0,3": "c", "1,1": "n", "1,4": "x", "2,2": "d", "2,5": "c", "3,0": "g", "3,3": "e", "4,1": "c", "4,4": "d", "5,2": "x", "5,5": "g", "6,3": "c" };
  const gone = new Set(["0,0", "0,6", "6,0", "6,6", "0,5"]);
  for (let row = 0; row < 7; row++) for (let col = 0; col < 7; col++) {
    if (gone.has(`${row},${col}`) || (row % 2 && col === 6)) continue;
    const cx = 50 + col * w + (row % 2 ? w / 2 : 0), cy = 52 + row * r * 1.5;
    const k = lit[`${row},${col}`];
    if (k) s += `<g class="${cls[k]}"><polygon points="${hex(cx, cy, r - 3)}" fill="#15110a"/><circle class="hc-glow" cx="${cx.toFixed(1)}" cy="${cy}" r="32" fill="url(#hc-o${k})"/></g>`;
    else {
      const capped = (row * 7 + col * 13) % 5 === 0;
      s += `<polygon points="${hex(cx, cy, r - 3)}" fill="${capped ? "#e9ac0c" : "#f9cc45"}" stroke="#c98f00" stroke-width="2.5"/>` + (capped ? "" : `<polygon points="${hex(cx, cy, r - 14)}" fill="#e2a40a" opacity=".55"/>`);
    }
  }
  s += `<text x="300" y="548" text-anchor="middle" font-size="13" font-weight="700" letter-spacing="2" fill="#15110a">EVERY LIT CELL IS A SESSION</text>`;
  art.innerHTML = `<svg class="hc-comb" viewBox="0 0 600 560" role="presentation">${s}</svg>`;
})();
