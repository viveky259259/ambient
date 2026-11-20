// Chladni's hero art: four black plates with sand settled into a standing-wave figure, one per state, each in
// the state's colour (working in Claude's). The plate for the demo's current state is lifted (theme.css, from
// data-mood on <html>, set by main.js). Sand is scattered once, so reduced motion shows the same still plates.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const S = [["Working", 1, 2, -1, [217, 119, 87]], ["Needs you", 3, 5, 1, [255, 176, 46]], ["Done", 2, 4, 1, [79, 220, 140]], ["Error", 4, 7, -1, [255, 90, 85]]];
  const N = 480;
  let seed = 9;
  const R = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const band = document.createElement("div");
  band.className = "ch-band";
  S.forEach(([name, a, b, sg, col], i) => {
    const el = document.createElement("div");
    el.className = `ch-pl ch-p${i}`;
    el.innerHTML = `<canvas width="${N}" height="${N}"></canvas><div class="m"><span>Plate ${i + 1}</span><span>mode ${a} · ${b}</span></div><b>${name}</b>`;
    band.appendChild(el);
    const c = el.querySelector("canvas").getContext("2d");
    const g = c.createLinearGradient(0, 0, N, N);
    g.addColorStop(0, "#1c1c1e"); g.addColorStop(0.5, "#0c0c0d"); g.addColorStop(1, "#161617");
    c.fillStyle = g; c.fillRect(0, 0, N, N);
    const pad = 12, span = N - 2 * pad;
    for (let placed = 0, tries = 0; placed < 30000 && tries < 900000; tries++) {
      const x = R(), y = R();
      const f = Math.cos(a * Math.PI * x) * Math.cos(b * Math.PI * y) + sg * Math.cos(b * Math.PI * x) * Math.cos(a * Math.PI * y);
      if (R() < Math.exp(-Math.abs(f) * 16)) {
        const l = 0.75 + R() * 0.5;
        c.fillStyle = `rgba(${Math.min(255, col[0] * l) | 0},${Math.min(255, col[1] * l) | 0},${Math.min(255, col[2] * l) | 0},${0.5 + R() * 0.5})`;
        c.fillRect(pad + x * span, pad + y * span, 1.5, 1.5);
        placed++;
      } else if (R() < 0.012) {
        c.fillStyle = `rgba(${col},.22)`;
        c.fillRect(pad + x * span, pad + y * span, 1.2, 1.2);
      }
    }
    c.fillStyle = "#2a2a2c"; c.beginPath(); c.arc(N / 2, N / 2, 11, 0, 7); c.fill();
    c.fillStyle = "#8d8a84"; c.beginPath(); c.arc(N / 2, N / 2, 5, 0, 7); c.fill();
    c.strokeStyle = "rgba(255,255,255,.14)"; c.lineWidth = 2; c.strokeRect(1, 1, N - 2, N - 2);
  });
  art.appendChild(band);
})();
