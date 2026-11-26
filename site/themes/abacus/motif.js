// Abacus's hero art: a counting frame built as an instrument. Oiled walnut with mitred corners and brass corner
// plates, an engraved scale on the top rail, a reckoning beam, brass rods and turned bicone beads. Counted beads,
// stained in a state's colour, sit against the beam; the boxwood ones wait at the far end. A brass pointer marks
// the row of the demo's current mood (theme.css, data-mood on <html>).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const W = 1200, H = 640, T = 36, beam = 392;
  const mono = "IBM Plex Mono, monospace", serif = "Spectral, Georgia, serif";
  const R = [["waiting", "Needs you", "#d49516", 1], ["error", "Error", "#a83a28", 1], ["done", "Done", "#357d50", 2], ["working", "Working", "#c66a4a", 4]];
  const top = T + 26, rowH = (H - 2 * T - 52) / 4;
  const bead = (x, y, c, id) => `<g transform="translate(${x},${y})"><path d="M-25,-20 L0,-46 L25,-20 L25,20 L0,46 L-25,20 Z" fill="url(#ab-b${id})"/>
    <path d="M0,-46 L0,46" stroke="#fff" stroke-opacity=".28" stroke-width="1.5"/><path d="M-25,-20 L25,-20 M-25,20 L25,20" stroke="#000" stroke-opacity=".18"/>
    <path d="M-25,-20 L0,-46 L25,-20 L25,20 L0,46 L-25,20 Z" fill="none" stroke="#1f140c" stroke-opacity=".55" stroke-width="1.2"/></g>`;
  const mix = (a, b, t) => "#" + [1, 3, 5].map((i) => Math.round(parseInt(a.substr(i, 2), 16) * (1 - t) + parseInt(b.substr(i, 2), 16) * t).toString(16).padStart(2, "0")).join("");
  const grad = (id, c) => `<linearGradient id="ab-b${id}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="${mix(c, "#ffffff", 0.45)}"/><stop offset=".48" stop-color="${c}"/><stop offset=".52" stop-color="${mix(c, "#000000", 0.2)}"/><stop offset="1" stop-color="${mix(c, "#000000", 0.45)}"/></linearGradient>`;
  let defs = grad("x", "#d2b07c"), rows = "";
  R.forEach(([mood, name, c, n], i) => {
    defs += grad(i, c);
    const y = top + rowH * (i + 0.5);
    rows += `<rect x="${beam}" y="${y - 3.5}" width="${W - T - beam}" height="7" fill="url(#ab-rod)"/>`;
    for (let k = 0; k < n; k++) rows += bead(beam + 34 + k * 52, y, c, i);
    for (let k = 0; k < 9 - n; k++) rows += bead(W - T - 30 - k * 52, y, "#d2b07c", "x");
    rows += `<g><rect x="${T + 30}" y="${y - 34}" width="${beam - T - 62}" height="68" rx="3" fill="url(#ab-brass)" stroke="#6e5526"/>
      <circle cx="${T + 42}" cy="${y - 22}" r="3.5" fill="#6e5526"/><circle cx="${beam - 44}" cy="${y + 22}" r="3.5" fill="#6e5526"/>
      <text x="${T + 58}" y="${y + 11}" font-family="${serif}" font-weight="600" font-size="32" fill="#2a1b12">${name}</text>
      <text x="${beam - 54}" y="${y + 9}" text-anchor="end" font-family="${mono}" font-size="20" fill="#2a1b12">${String(n).padStart(2, "0")}</text></g>
      <path class="ab-ptr ${mood}" d="M${T + 6},${y - 13} L${T + 24},${y} L${T + 6},${y + 13} Z" fill="#e8cf8e" stroke="#6e5526"/>
      <circle cx="${beam + 9}" cy="${y}" r="3" fill="#e8cf8e"/>`;
  });
  let scale = "";
  for (let k = 0; k <= 72; k++) {
    const x = beam + 20 + k * 10.4;
    scale += `<line x1="${x.toFixed(1)}" y1="${T + 2}" x2="${x.toFixed(1)}" y2="${T + (k % 8 ? 9 : 16)}"/>`;
    if (k % 8 === 0 && k < 72) scale += `<text x="${(x + 4).toFixed(1)}" y="${T + 24}" stroke="none" fill="#e8cf8e" font-family="${mono}" font-size="11">${k / 8 + 1}</text>`;
  }
  const plate = (x, y, sx, sy) => `<g transform="translate(${x},${y}) scale(${sx},${sy})"><path d="M0,0 H70 V14 H14 V70 H0 Z" fill="url(#ab-brass)" stroke="#6e5526"/><circle cx="7" cy="7" r="3" fill="#6e5526"/><circle cx="54" cy="7" r="2.5" fill="#6e5526"/><circle cx="7" cy="54" r="2.5" fill="#6e5526"/></g>`;
  art.innerHTML = `<svg viewBox="0 0 ${W} ${H}" role="presentation"><defs>${defs}
    <linearGradient id="ab-rod" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f3e2b0"/><stop offset=".5" stop-color="#b08d4a"/><stop offset="1" stop-color="#5e4720"/></linearGradient>
    <linearGradient id="ab-brass" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f0dca2"/><stop offset=".5" stop-color="#c29d55"/><stop offset="1" stop-color="#8d6c30"/></linearGradient>
    <filter id="ab-grain" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".003 .09" numOctaves="3" seed="7"/><feColorMatrix values="0 0 0 0 .1 0 0 0 0 .05 0 0 0 0 .02 0 0 0 1.4 -.35"/></filter>
    <filter id="ab-sh" x="-5%" y="-5%" width="110%" height="115%"><feDropShadow dx="0" dy="14" stdDeviation="14" flood-color="#1f1a14" flood-opacity=".3"/></filter>
    <clipPath id="ab-fr"><path fill-rule="evenodd" d="M0,0 H${W} V${H} H0 Z M${T},${T} V${H - T} H${W - T} V${T} Z"/></clipPath></defs>
    <rect width="${W}" height="${H}" rx="6" fill="#4a2e1c" filter="url(#ab-sh)"/>
    <rect x="${T}" y="${T}" width="${W - 2 * T}" height="${H - 2 * T}" fill="#2e1d12"/>
    <rect x="${T}" y="${T}" width="${W - 2 * T}" height="${H - 2 * T}" fill="url(#ab-rod)" opacity=".05"/>
    <g clip-path="url(#ab-fr)"><rect width="${W}" height="${H}" filter="url(#ab-grain)"/>
      <path d="M0,0 L${T},${T} M${W},0 L${W - T},${T} M0,${H} L${T},${H - T} M${W},${H} L${W - T},${H - T}" stroke="#1c100a" stroke-width="2"/>
      <rect width="${W}" height="3" fill="#fff" opacity=".14"/></g>
    <rect x="${T}" y="${T}" width="${W - 2 * T}" height="${H - 2 * T}" fill="none" stroke="#1c100a" stroke-width="3"/>
    <rect x="${beam - 12}" y="${T}" width="24" height="${H - 2 * T}" fill="#4a2e1c"/><rect x="${beam - 12}" y="${T}" width="24" height="${H - 2 * T}" filter="url(#ab-grain)"/>
    <rect x="${beam - 12}" y="${T}" width="24" height="${H - 2 * T}" fill="none" stroke="#1c100a" stroke-width="1.5"/>
    <g stroke="#e8cf8e" stroke-width="1">${scale}</g>
    ${rows}
    ${plate(4, 4, 1, 1)}${plate(W - 4, 4, -1, 1)}${plate(4, H - 4, 1, -1)}${plate(W - 4, H - 4, -1, -1)}
  </svg>`;
})();
