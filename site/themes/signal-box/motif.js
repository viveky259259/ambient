// Signal box's hero art: a signal head with one lamp per state, most urgent at the top, beside its brass label
// plate. The lamp for the demo's current state is lit (data-mood on <html>, set by main.js; see theme.css).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const lamps = [["waiting", "Needs you", "#ffb224"], ["error", "Error", "#ff4d4d"], ["done", "Done", "#3fd07a"], ["working", "Working", "#d97757"]];
  let s = `<defs><radialGradient id="sbx-g"><stop offset="0" stop-color="#fff" stop-opacity=".9"/><stop offset=".35" stop-color="#fff" stop-opacity="0"/></radialGradient></defs>`;
  s += `<rect x="78" y="440" width="20" height="120" fill="#55665f"/><rect x="40" y="546" width="96" height="14" fill="#2a3833"/>`;
  s += `<rect x="13" y="10" width="150" height="436" rx="75" fill="#050807" stroke="#2c3d37" stroke-width="3"/>`;
  lamps.forEach(([mood, label, c], i) => {
    const y = 84 + i * 100;
    s += `<circle class="glow m-${mood}" cx="88" cy="${y}" r="70" fill="${c}" opacity="0" style="filter:blur(18px)"/>`;
    s += `<circle cx="88" cy="${y}" r="40" fill="#0b1310" stroke="#1c2824" stroke-width="4"/>`;
    s += `<circle class="lamp m-${mood}" cx="88" cy="${y}" r="36" fill="${c}"/><circle class="lamp m-${mood}" cx="78" cy="${y - 10}" r="22" fill="url(#sbx-g)"/>`;
    s += `<path d="M42 ${y - 30} A50 50 0 0 1 134 ${y - 30}" fill="none" stroke="#1c2824" stroke-width="8"/>`;
    s += `<line x1="170" y1="${y}" x2="200" y2="${y}" stroke="#c8a55a" stroke-width="1.5"/>`;
    s += `<text class="lab m-${mood}" x="208" y="${y + 9}" font-family="Saira Condensed, sans-serif" font-weight="800" font-size="30" letter-spacing="2">${label.toUpperCase()}</text>`;
  });
  s += `<rect x="200" y="452" width="206" height="40" fill="none" stroke="#c8a55a" stroke-width="2"/>`;
  s += `<text x="214" y="477" fill="#c8a55a" font-family="B612 Mono, monospace" font-size="12" letter-spacing="2">MOST URGENT FIRST</text>`;
  art.innerHTML = `<svg class="sbx-head" viewBox="0 0 420 560" role="presentation">${s}</svg>`;
})();
