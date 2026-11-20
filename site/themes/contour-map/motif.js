// Contour map's hero art: three hills on a survey sheet, one per session. Each summit carries a triangle in the
// colour of its state; the tallest is the session the demo is showing, in its current colour (--state).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const hills = [[320, 170, 9, 24, 1.1], [150, 390, 7, 22, 2.3], [430, 430, 5, 22, 4.1]];
  let lines = "";
  for (const [cx, cy, n, step, ph] of hills) {
    for (let i = 1; i <= n; i++) {
      const r = i * step;
      let d = "";
      for (let a = 0; a <= 360; a += 6) {
        const t = (a * Math.PI) / 180;
        const rr = r * (1 + 0.16 * Math.sin(3 * t + ph) + 0.09 * Math.sin(5 * t + ph * 2 + i * 0.25) + 0.05 * Math.sin(2 * t - i * 0.4));
        d += (a ? "L" : "M") + (cx + rr * Math.cos(t) * 1.15).toFixed(1) + " " + (cy + rr * Math.sin(t)).toFixed(1);
      }
      lines += `<path d="${d}Z" stroke-width="${i % 4 === 0 ? 2.2 : 1}" opacity="${(0.8 - i * 0.04).toFixed(2)}"/>`;
    }
  }
  const peak = (x, y, name, sub, cls, color) => `
    <path class="${cls}" d="M${x} ${y - 12} L${x + 11} ${y + 7} L${x - 11} ${y + 7} Z" ${color ? `fill="${color}"` : ""}/>
    <text x="${x + 20}" y="${y + 6}" font-family="Spectral, Georgia, serif" font-style="italic" font-size="25" fill="#2b3327">${name}</text>
    <text x="${x + 21}" y="${y + 26}" font-family="'Overpass Mono', Menlo, monospace" font-size="10.5" letter-spacing="1.3" fill="#4a5143">${sub}</text>`;
  art.innerHTML = `
    <svg class="ctr-art" viewBox="0 0 560 560" role="presentation">
      <g class="lines" fill="none" stroke="#8a7648">${lines}</g>
      ${peak(306, 170, "api-server", "CLAUDE CODE · NOW", "now")}
      ${peak(136, 390, "docs", "GEMINI CLI · WORKING", "p", "#2a5fbf")}
      ${peak(416, 430, "web", "CODEX · DONE", "p", "#2f7d3a")}
    </svg>`;
})();
