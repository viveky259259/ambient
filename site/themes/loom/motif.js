// Loom's hero art: cloth on a loom. Each warp stripe is a session dyed in its state's colour (working stripes in
// their agent's colour), woven in a twill with ecru weft, labelled by agent and ending in a fringe. The beam above
// shows the most urgent state's colour and name, following the demo (theme.css reads --state and data-mood on
// <html>, set by main.js). The cloth is drawn once, so reduced motion shows the same still frame.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const W = 700, H = 820, S = 10, COLS = 70, TOP = 92, ROWS = 64;
  art.innerHTML = `<div class="lm-loom"><canvas width="${W}" height="${H}"></canvas><div class="lm-beam"><b></b><span></span></div></div>`;
  const x = art.querySelector("canvas").getContext("2d");
  const css = getComputedStyle(document.documentElement);
  const v = (n, f) => css.getPropertyValue(n).trim() || f;
  const cl = v("--claude", "#c8643f"), cx = v("--codex", "#2e8a6a"), gm = v("--gemini", "#3f63b8");
  const sessions = [["claude", cl], ["codex", v("--done", "#4d7c4a")], ["claude", v("--waiting", "#d8962a")], ["gemini", gm], ["codex", v("--error", "#b83a2a")], ["claude", cl], ["gemini", v("--done", "#4d7c4a")]];
  const ground = "#2b2623", weft = "#e4d8be";
  const warp = (c) => { const k = c % 10; return k >= 2 && k < 8 ? sessions[Math.floor(c / 10)][1] : ground; };
  // the rail under the beam
  x.fillStyle = "#5a4635"; x.fillRect(0, 26, W, 14);
  x.fillStyle = "rgba(0,0,0,.2)"; x.fillRect(0, 40, W, 3);
  x.font = "500 13px 'DM Mono', ui-monospace, monospace"; x.textAlign = "center"; x.fillStyle = ground;
  sessions.forEach(([name], i) => x.fillText(name.toUpperCase(), i * 100 + 50, 72));
  for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) {
    const px = c * S, py = TOP + r * S;
    if ((r + c) % 4 !== 0) {
      x.fillStyle = warp(c); x.fillRect(px + 1, py, S - 2, S);
      x.fillStyle = "rgba(0,0,0,.22)"; x.fillRect(px + 1, py, 1.5, S); x.fillRect(px + S - 2.5, py, 1.5, S);
      x.fillStyle = "rgba(255,255,255,.14)"; x.fillRect(px + 4, py, 2, S);
      x.fillStyle = "rgba(0,0,0,.18)"; x.fillRect(px + 1, py + S - 1, S - 2, 1);
    } else {
      x.fillStyle = weft; x.fillRect(px, py + 1, S, S - 2);
      x.fillStyle = "rgba(0,0,0,.2)"; x.fillRect(px, py + 1, S, 1.2); x.fillRect(px, py + S - 2.2, S, 1.2);
    }
  }
  const base = TOP + ROWS * S;
  x.lineWidth = 3;
  for (let c = 0; c < COLS; c++) {
    const px = c * S + 5;
    x.strokeStyle = warp(c); x.beginPath(); x.moveTo(px, base);
    x.bezierCurveTo(px + Math.sin(c) * 3, base + 25, px - Math.cos(c * 1.7) * 4, base + 45, px + Math.sin(c * 2.3) * 3, base + 66 + (c % 3) * 2);
    x.stroke();
  }
})();
