// Neon roadside's hero art: four neon signs on a roadside pole, one per state. The sign for the demo's current
// state is lit and the rest are dark tubes (data-mood on <html>, set by main.js; see theme.css).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const signs = [["working", "Working", "#d97757"], ["waiting", "Needs you", "#ffad1f"], ["done", "Done", "#35e07a"], ["error", "Error", "#ff3b30"]];
  let s = `<defs><filter id="neo-glow" x="-30%" y="-60%" width="160%" height="220%"><feGaussianBlur stdDeviation="6" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
    <linearGradient id="neo-pole" x1="0" x2="1"><stop offset="0" stop-color="#2a2530"/><stop offset=".45" stop-color="#57505e"/><stop offset="1" stop-color="#1c1820"/></linearGradient></defs>`;
  s += `<rect x="248" y="0" width="24" height="640" fill="url(#neo-pole)"/>`;
  signs.forEach(([mood, label, c], i) => {
    const y = 16 + i * 156;
    s += `<rect x="26" y="${y}" width="468" height="132" rx="26" fill="#0c090f" stroke="#2e2834" stroke-width="3"/>`;
    s += `<g class="sign m-${mood}" filter="url(#neo-glow)">
      <rect x="38" y="${y + 12}" width="444" height="108" rx="18" fill="none" stroke="${c}" stroke-width="3.5"/>
      <circle cx="94" cy="${y + 66}" r="17" fill="#fff" stroke="${c}" stroke-width="6"/>
      <text x="134" y="${y + 84}" fill="#fff" stroke="${c}" stroke-width="1" font-family="Outfit, sans-serif" font-weight="600" font-size="48" letter-spacing="1">${label.toUpperCase()}</text></g>`;
  });
  art.innerHTML = `<svg class="neo-signs" viewBox="0 0 520 640" role="presentation">${s}</svg>`;
})();
