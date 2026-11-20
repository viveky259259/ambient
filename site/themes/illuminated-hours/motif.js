// Illuminated hours' hero art: an arched miniature in lapis and gold. Over green hills an orb in the demo's
// current state colour (--state on <html>) hangs in a field of gilt stars, ringed by slowly turning rays.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const gold = "#f1d27a", ink = "#2a1c10";
  let seed = 11;
  const R = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  let stars = "";
  for (let i = 0; i < 46; i++) stars += `<circle cx="${(R() * 280 + 10).toFixed(1)}" cy="${(R() * 250 + 20).toFixed(1)}" r="${(R() * 1.6 + 1).toFixed(1)}" fill="${gold}" opacity=".85"/>`;
  let rays = "";
  for (let i = 0; i < 24; i++) {
    const a = (i * 15 * Math.PI) / 180, r = i % 2 ? 96 : 76;
    rays += `<line x1="${(Math.cos(a) * 52).toFixed(1)}" y1="${(Math.sin(a) * 52).toFixed(1)}" x2="${(Math.cos(a) * r).toFixed(1)}" y2="${(Math.sin(a) * r).toFixed(1)}"/>`;
  }
  const arch = "M14 376 V150 A136 136 0 0 1 286 150 V376 Z";
  art.innerHTML = `
    <svg class="ilh-mini" viewBox="0 0 300 380" role="presentation">
      <defs><clipPath id="ilh-clip"><path d="${arch}"/></clipPath></defs>
      <path d="${arch}" fill="#1d377e"/>
      <g clip-path="url(#ilh-clip)">
        ${stars}
        <path d="M0 380 V310 Q75 276 150 302 T300 292 V380Z" fill="#2f5a2c"/>
        <path d="M0 380 V336 Q90 314 170 334 T300 326 V380Z" fill="#3d7436"/>
        <g transform="translate(150 168)">
          <g class="rays" stroke="${gold}" stroke-width="3">${rays}</g>
          <circle class="orb" r="46" stroke="${gold}" stroke-width="4"/>
          <circle cx="-13" cy="-15" r="14" fill="#fff" opacity=".35"/>
        </g>
      </g>
      <path d="${arch}" fill="none" stroke="#b08326" stroke-width="9"/>
      <path d="${arch}" fill="none" stroke="${ink}" stroke-width="2" transform="translate(150 190) scale(1.045) translate(-150 -190)"/>
      <path d="${arch}" fill="none" stroke="${ink}" stroke-width="1.5" transform="translate(150 190) scale(.955) translate(-150 -190)"/>
    </svg>`;
})();
