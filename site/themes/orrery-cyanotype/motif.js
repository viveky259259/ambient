// Orrery cyanotype's hero art: a cyanotype print, pinned to the page. Cream rag paper, a brushed Prussian-blue
// emulsion with ragged edges and grain, and the orrery exposed in white line: the notch as the sun, four orbits
// in order of urgency, hand-tinted bodies. A pencilled plate caption sits on the paper. The body for the demo's
// current state (data-mood on <html>, set by main.js) gets a white halo. Static, so reduced motion is a still.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const cx = 300, cy = 300, W = "#f4f8fd";
  const P = (r, a) => [cx + r * Math.cos((a * Math.PI) / 180), cy + r * Math.sin((a * Math.PI) / 180)];
  const f = (n) => n.toFixed(1);
  let o = "";
  [72, 124, 178, 232].forEach((r, i) => {
    o += `<circle cx="${cx}" cy="${cy}" r="${r}" stroke-width="1.3" stroke-opacity=".85"/><circle cx="${cx}" cy="${cy}" r="${r + 5}" stroke-opacity=".3" stroke-dasharray="1 6"/>`;
    const [tx, ty] = P(r, -90);
    o += `<text x="${f(tx + 6)}" y="${f(ty - 5)}" font-size="10" fill="${W}" stroke="none" opacity=".8">${["I", "II", "III", "IV"][i]}</text>`;
  });
  for (let a = 0; a < 360; a += 5) { const [x1, y1] = P(250, a), [x2, y2] = P(a % 30 ? 256 : 264, a); o += `<line x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}" stroke-opacity=".7"/>`; }
  // bodies: needs you (I), error (II), done (III), working (IV); hand tint over white
  [[72, -38, "#ffbe4d", 13], [124, 205, "#ff7b73", 11], [178, 48, "#6fe3a0", 14], [232, 148, "#c3b5ff", 15]].forEach(([r, a, c, z], i) => {
    const [x, y] = P(r, a);
    o += `<g class="oc-b${i}"><line x1="${cx}" y1="${cy}" x2="${f(x)}" y2="${f(y)}" stroke-opacity=".4"/><circle class="oc-halo" cx="${f(x)}" cy="${f(y)}" r="${z + 9}" stroke-width="2.4"/><circle cx="${f(x)}" cy="${f(y)}" r="${z}" fill="${W}" stroke-width="1.3"/><circle cx="${f(x)}" cy="${f(y)}" r="${z - 1.5}" fill="${c}" fill-opacity=".78" stroke="none"/><path d="M${f(x - z)} ${f(y)} A${z} ${f(z * 0.35)} 0 0 0 ${f(x + z)} ${f(y)}" stroke="#0e3b74" stroke-opacity=".45"/></g>`;
  });
  [[232, 18, 8], [232, 262, 9], [178, 250, 7]].forEach(([r, a, z]) => { const [x, y] = P(r, a); o += `<circle cx="${f(x)}" cy="${f(y)}" r="${z}" fill="#c3b5ff" fill-opacity=".7" stroke-width="1.1"/>`; });
  let rays = "";
  for (let a = 0; a < 360; a += 15) { const [x1, y1] = P(34, a), [x2, y2] = P(a % 30 ? 44 : 54, a); rays += `<line x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}" stroke-width="1.4"/>`; }
  o += rays + `<circle cx="${cx}" cy="${cy}" r="28" fill="#ffbe4d" fill-opacity=".72" stroke-width="1.4"/><rect x="${cx - 18}" y="${cy - 6}" width="36" height="12" rx="6" fill="#082a55" stroke="none"/><circle cx="${cx + 11}" cy="${cy}" r="3" fill="#ffbe4d" stroke="none"/>`;
  art.innerHTML = `
  <svg class="oc-print" viewBox="0 0 600 690" role="presentation">
    <defs>
      <filter id="oc-deckle" x="-5%" y="-5%" width="110%" height="110%"><feTurbulence type="fractalNoise" baseFrequency=".06" numOctaves="3" seed="3"/><feDisplacementMap in="SourceGraphic" scale="7"/></filter>
      <filter id="oc-brush" x="-8%" y="-8%" width="116%" height="116%"><feTurbulence type="fractalNoise" baseFrequency=".012 .09" numOctaves="3" seed="11"/><feDisplacementMap in="SourceGraphic" scale="34"/></filter>
      <filter id="oc-grain"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" seed="5"/><feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 .16 0"/><feComposite in2="SourceGraphic" operator="in"/></filter>
      <linearGradient id="oc-wash" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1d5296"/><stop offset=".55" stop-color="#123f7a"/><stop offset="1" stop-color="#0a2d5e"/></linearGradient>
    </defs>
    <g transform="rotate(-1.6 300 345)">
      <rect x="6" y="14" width="588" height="668" fill="#000" opacity=".28" filter="url(#oc-deckle)" transform="translate(6 10)"/>
      <rect x="6" y="10" width="588" height="668" fill="#f1ece0" filter="url(#oc-deckle)"/>
      <g filter="url(#oc-brush)"><rect x="42" y="42" width="516" height="516" fill="url(#oc-wash)"/></g>
      <g filter="url(#oc-brush)"><rect x="42" y="42" width="516" height="516" fill="#fff" filter="url(#oc-grain)"/></g>
      <g fill="none" stroke="${W}">${o}</g>
      <text class="cap" x="58" y="608" font-size="19" fill="#3b4a63">Plate VII — an orrery of agent sessions</text>
      <text x="58" y="634" font-size="10.5" letter-spacing="1.6" fill="#5b6a82">THE SUN IS THE NOTCH · ORBIT ORDER IS URGENCY</text>
      <text x="542" y="634" text-anchor="end" font-size="10.5" letter-spacing="1.6" fill="#5b6a82">CYANOTYPE</text>
      <rect x="250" y="-4" width="100" height="26" fill="#efe3bf" opacity=".8" transform="rotate(3 300 9)"/>
    </g>
  </svg>`;
})();
