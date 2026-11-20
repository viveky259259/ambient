// Neon sign's hero art: an indoor blade sign hung from a wrought bracket on the brick. A dark box holds the
// word "ambient" in pink tube and four state tubes of bent glass; only the tube of the demo's current mood is
// lit, the others show as cold grey glass (theme.css, data-mood on <html>).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const font = "Tilt Neon, Avenir Next, sans-serif";
  const T = [["working", "#5aa2ff", "Working"], ["waiting", "#ffb02e", "Needs you"], ["done", "#34f595", "Done"], ["error", "#ff4658", "Error"]];
  const glass = "#5b4c6a";
  const tube = (mood, c, word, y) => {
    const shape = (stroke, w) => `<rect x="70" y="${y}" width="340" height="150" rx="26" fill="none" stroke="${stroke}" stroke-width="${w}"/>
      <circle cx="128" cy="${y + 75}" r="28" fill="none" stroke="${stroke}" stroke-width="${w}"/><circle cx="128" cy="${y + 75}" r="9" fill="${stroke}"/>`;
    const text = (fill, stroke) => `<text x="176" y="${y + 92}" font-family="${font}" font-size="${word.length > 6 ? 42 : 50}" fill="${fill}" stroke="${stroke}" stroke-width="1">${word}</text>`;
    return `<g class="nn-tube ${mood}">
      <g opacity=".9">${shape(glass, 4)}${text("none", glass)}</g>
      <g class="lit"><g filter="url(#nn-glow)" opacity=".95">${shape(c, 6)}${text(c, c)}</g>
        ${shape("#fff", 2)}${text("#fff", "none")}</g></g>`;
  };
  let tubes = "";
  T.forEach(([m, c, w], i) => (tubes += tube(m, c, w, 244 + i * 158)));
  art.innerHTML = `<svg viewBox="0 0 480 920" role="presentation"><defs>
      <filter id="nn-glow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur in="SourceGraphic" stdDeviation="3" result="a"/><feGaussianBlur in="SourceGraphic" stdDeviation="12" result="b"/>
        <feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="a"/></feMerge></filter>
      <linearGradient id="nn-iron" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4a3d58"/><stop offset="1" stop-color="#1a1222"/></linearGradient>
      <radialGradient id="nn-spill" cx="50%" cy="55%" r="55%"><stop offset="0" stop-color="#ff4fc1" stop-opacity=".22"/><stop offset="1" stop-color="#ff4fc1" stop-opacity="0"/></radialGradient></defs>
    <ellipse cx="240" cy="520" rx="240" ry="420" fill="url(#nn-spill)"/>
    <rect x="0" y="20" width="22" height="80" rx="3" fill="url(#nn-iron)"/><circle cx="11" cy="34" r="3.5" fill="#7a6a8a"/><circle cx="11" cy="86" r="3.5" fill="#7a6a8a"/>
    <path d="M20,44 H440 M20,80 C120,80 150,44 230,44" fill="none" stroke="url(#nn-iron)" stroke-width="9" stroke-linecap="round"/>
    <path d="M60,62 c10,-18 34,-18 34,0 c0,14 -20,14 -20,2" fill="none" stroke="#3a2e46" stroke-width="5"/>
    <g stroke="#6d5d7e" stroke-width="3" fill="none"><path d="M90,48 V100 M390,48 V100"/>${[0, 1, 2, 3].map((k) => `<ellipse cx="90" cy="${56 + k * 12}" rx="4" ry="6"/><ellipse cx="390" cy="${56 + k * 12}" rx="4" ry="6"/>`).join("")}</g>
    <rect x="34" y="100" width="412" height="800" rx="24" fill="#0a0610" stroke="#2c2138" stroke-width="3"/>
    <rect x="46" y="112" width="388" height="776" rx="18" fill="none" stroke="#1c1428" stroke-width="2"/>
    <g filter="url(#nn-glow)"><text x="240" y="212" text-anchor="middle" font-family="${font}" font-size="82" fill="#ff4fc1" stroke="#ff4fc1" stroke-width="2">ambient</text></g>
    <text x="240" y="212" text-anchor="middle" font-family="${font}" font-size="82" fill="#ffe8f7">ambient</text>
    ${tubes}
    <path d="M440,900 v12" stroke="#2c2138" stroke-width="4"/>
  </svg>`;
})();
