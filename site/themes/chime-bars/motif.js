// Chime bars' hero art: eight tuned bars on two walnut rails, a pair for each state, pinned with brass. The
// mallet moves to the pair of the demo's current mood and that pair rings (theme.css, data-mood on <html>).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const moods = ["working", "waiting", "done", "error"];
  const cols = [["#2c4f9e", "#9dbdf8", "#4a78d6"], ["#9a6208", "#ffd27a", "#e9a020"], ["#1f6b43", "#93e0b2", "#3fa66c"], ["#8e241b", "#ffa397", "#d84a3b"]];
  let h = `<defs>
    <linearGradient id="cb-rail" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7a5230"/><stop offset="1" stop-color="#4c301a"/></linearGradient>
    <filter id="cb-ds" x="-20%" y="-10%" width="140%" height="130%"><feDropShadow dx="0" dy="14" stdDeviation="10" flood-color="#000" flood-opacity=".55"/></filter>
    <pattern id="cb-brush" width="8" height="5" patternUnits="userSpaceOnUse"><rect width="8" height="1" fill="#fff" opacity=".07"/></pattern>
    <radialGradient id="cb-ball" cx="35%" cy="30%"><stop offset="0" stop-color="#fff3d6"/><stop offset=".5" stop-color="#d9b47a"/><stop offset="1" stop-color="#7a5a30"/></radialGradient></defs>`;
  h += `<path d="M70,82 L1370,166 L1370,196 L70,120 Z" fill="url(#cb-rail)"/><path d="M70,518 L1370,440 L1370,470 L70,556 Z" fill="url(#cb-rail)"/>`;
  const W = 112, cy = 320;
  let x = 120;
  for (let p = 0; p < 4; p++) {
    const c = cols[p];
    h += `<defs><linearGradient id="cb-b${p}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="${c[0]}"/><stop offset=".18" stop-color="${c[2]}"/><stop offset=".42" stop-color="${c[1]}"/><stop offset=".6" stop-color="${c[2]}"/><stop offset="1" stop-color="${c[0]}"/></linearGradient></defs>`;
    const x0 = x;
    for (let b = 0; b < 2; b++) {
      const i = p * 2 + b, H = 560 - i * 34, y = cy - H / 2, mx = x + W / 2;
      const r1 = 82 + (mx - 70) * (84 / 1300) + 19, r2 = 518 - (mx - 70) * (78 / 1300) + 19;
      h += `<g filter="url(#cb-ds)"><rect x="${x}" y="${y}" width="${W}" height="${H}" rx="9" fill="url(#cb-b${p})"/><rect x="${x}" y="${y}" width="${W}" height="${H}" rx="9" fill="url(#cb-brush)"/>
        <rect x="${x}" y="${y}" width="${W}" height="${H}" rx="9" fill="none" stroke="#000" stroke-opacity=".35"/>`;
      for (const ry of [r1, r2]) h += `<circle cx="${mx}" cy="${ry.toFixed(1)}" r="9" fill="#1a110a"/><circle cx="${mx}" cy="${ry.toFixed(1)}" r="5.5" fill="#d3a85c"/><line x1="${mx - 4}" x2="${mx + 4}" y1="${ry.toFixed(1)}" y2="${ry.toFixed(1)}" stroke="#5a4020" stroke-width="1.5"/>`;
      h += `</g>`;
      x += W + (b ? 88 : 10);
    }
    // Sound rings either side of the pair.
    let ring = "";
    for (let r = 1; r <= 3; r++) {
      ring += `<path d="M${x0 - 12 - r * 13},${cy - 80} q-${10 + r * 3},40 0,80" fill="none" stroke="${c[1]}" stroke-width="2.5" stroke-linecap="round" opacity="${0.9 - r * 0.22}"/>`;
      ring += `<path d="M${x0 + 2 * W + 22 + r * 13},${cy - 80} q${10 + r * 3},40 0,80" fill="none" stroke="${c[1]}" stroke-width="2.5" stroke-linecap="round" opacity="${0.9 - r * 0.22}"/>`;
    }
    h += `<g class="cb-ring ${moods[p]}">${ring}</g>`;
  }
  h += `<g class="cb-mallet"><g filter="url(#cb-ds)"><line x1="560" y1="250" x2="860" y2="40" stroke="#c9a070" stroke-width="12" stroke-linecap="round"/><line x1="558" y1="247" x2="858" y2="37" stroke="#fff" stroke-opacity=".25" stroke-width="3" stroke-linecap="round"/><circle cx="556" cy="253" r="30" fill="url(#cb-ball)"/></g></g>`;
  art.innerHTML = `<svg viewBox="0 0 1440 600" role="presentation">${h}</svg>`;
})();
