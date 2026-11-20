// Almanac's hero art: an engraved sun whose centre is Ambient's island, its orb in the demo's current state colour
// (--state on <html>, set by main.js), with two marginal notes either side as in an almanac's page head.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const ink = "#1d1812";
  let rays = "";
  for (let i = 0; i < 72; i++) {
    const a = (i * 5 * Math.PI) / 180;
    const len = i % 6 === 0 ? 210 : i % 2 ? 150 : 176;
    const w = i % 6 === 0 ? 3 : 1.2;
    rays += `<line x1="${(Math.cos(a) * 122).toFixed(1)}" y1="${(Math.sin(a) * 122).toFixed(1)}" x2="${(Math.cos(a) * len).toFixed(1)}" y2="${(Math.sin(a) * len).toFixed(1)}" stroke-width="${w}"/>`;
  }
  let hatch = "";
  for (let y = -92; y <= 92; y += 8) {
    if (Math.abs(y) < 30) continue;
    const x = Math.sqrt(100 * 100 - y * y) - 6;
    hatch += `<line x1="${(-x).toFixed(1)}" y1="${y}" x2="${x.toFixed(1)}" y2="${y}"/>`;
  }
  art.innerHTML = `
    <svg class="alm-sun" viewBox="-240 -220 480 440" role="presentation">
      <g class="rays" stroke="${ink}">${rays}</g>
      <circle r="112" fill="#efe3c8" stroke="${ink}" stroke-width="3"/>
      <circle r="100" fill="none" stroke="${ink}" stroke-width="1"/>
      <g stroke="${ink}" stroke-width="1">${hatch}</g>
      <rect x="-70" y="-22" width="140" height="44" rx="22" fill="${ink}"/>
      <circle class="orb-fill" cx="-44" r="11"/>
      <circle class="orb-ring" cx="-44" r="16" fill="none" stroke-width="1.5"/>
      <rect x="-16" y="-3" width="66" height="6" rx="3" fill="#efe3c8" opacity=".55"/>
    </svg>
    <div class="alm-note l"><b>Of Privacy</b>No accounts and no telemetry. Events stay on your Mac.</div>
    <div class="alm-note r"><b>Of Haste</b>Hooks finish in about 15&nbsp;ms, and never slow an agent down.</div>`;
})();
