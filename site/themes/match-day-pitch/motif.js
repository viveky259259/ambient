// Match day's hero art: a pitch seen from the stand, every agent session a player in the colour of what it's
// doing. The ringed player follows the demo's current state (--state on <html>, set by main.js).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const W = 1200, H = 600, chalk = "#f3f2e7";
  let s = "";
  for (let i = 0; i < 10; i++) s += `<rect x="${i * 120}" width="120" height="${H}" fill="${i % 2 ? "#1f7a40" : "#1b6d39"}"/>`;
  const L = `fill="none" stroke="${chalk}" stroke-width="4" opacity=".9"`;
  s += `<rect x="30" y="30" width="1140" height="540" ${L}/><line x1="600" y1="30" x2="600" y2="570" ${L}/>`;
  s += `<circle cx="600" cy="300" r="96" ${L}/><circle cx="600" cy="300" r="6" fill="${chalk}"/>`;
  s += `<rect x="30" y="140" width="190" height="320" ${L}/><rect x="30" y="220" width="70" height="160" ${L}/>`;
  s += `<rect x="980" y="140" width="190" height="320" ${L}/><rect x="1100" y="220" width="70" height="160" ${L}/>`;
  s += `<path d="M220 240 A90 90 0 0 1 220 360" ${L}/><path d="M980 240 A90 90 0 0 0 980 360" ${L}/>`;
  s += `<rect x="12" y="270" width="18" height="60" ${L}/><rect x="1170" y="270" width="18" height="60" ${L}/>`;
  // Runs: dotted chalk paths where a working player is heading.
  for (const [a, b, c, d] of [[340, 150, 470, 110], [520, 250, 640, 190], [780, 150, 900, 200], [1040, 470, 940, 520]]) {
    s += `<path d="M${a} ${b} Q${(a + c) / 2} ${b - 40} ${c} ${d}" fill="none" stroke="${chalk}" stroke-width="3" stroke-dasharray="3 10" stroke-linecap="round"/><circle cx="${c}" cy="${d}" r="5" fill="${chalk}"/>`;
  }
  const P = [
    [180, 300, "#ffb627", "codex · web", "needs you"],
    [340, 150, "#d97757", "claude · api", "working"],
    [360, 470, "#2fd06c", "gemini · docs", "done"],
    [520, 250, "#10a37f", "codex · infra", "working"],
    [760, 400, null, "claude · tests", ""],
    [780, 150, "#4f8df7", "gemini · cli", "working"],
    [900, 300, "#2fd06c", "claude · site", "done"],
    [1040, 470, "#d97757", "claude · sdk", "working"],
  ];
  for (const [x, y, c, name, st] of P) {
    const live = !c;
    if (live) s += `<circle class="ring" cx="${x}" cy="${y}" r="52" fill="none" stroke-width="3"/>`;
    s += `<ellipse cx="${x + 5}" cy="${y + 8}" rx="26" ry="22" fill="#000" opacity=".25"/>`;
    s += `<circle ${live ? 'class="live"' : `fill="${c}"`} cx="${x}" cy="${y}" r="26" stroke="${chalk}" stroke-width="4"/>`;
    const w = name.length * 9.3 + 24;
    s += `<g class="lbl"><rect x="${x - w / 2}" y="${y + 40}" width="${w}" height="26" fill="#0e2a1c"/><text x="${x}" y="${y + 58}" fill="${chalk}" font-family="Azeret Mono, monospace" font-size="14" text-anchor="middle">${name}</text>`;
    if (st) s += `<text x="${x}" y="${y + 86}" fill="${chalk}" font-family="Barlow Condensed, sans-serif" font-weight="800" font-size="18" letter-spacing="1.5" text-anchor="middle">${st.toUpperCase()}</text>`;
    s += `</g>`;
  }
  // The referee holds up a card for the player who needs you.
  s += `<rect x="218" y="218" width="30" height="42" rx="4" fill="#ffb627" stroke="#0e2a1c" stroke-width="2" transform="rotate(10 233 239)"/>`;
  art.innerHTML = `<svg class="mdp-pitch" viewBox="0 0 ${W} ${H}" role="presentation">${s}</svg>`;
})();
