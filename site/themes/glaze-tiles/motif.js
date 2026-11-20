// Glaze tiles' hero art: four bisque test tiles on a shelf, each dipped in one state's glaze. The glaze is glossy
// (a soft streak and a window glint), pools darker where it drips, and is crazed with fine cracks. The tile for
// the demo's current mood lifts off the shelf (theme.css, data-mood on <html>).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  let seed = 23;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const G = [
    ["#183a7e", "#3f77c4", "#b3d3f4", -2.2, "W", "working"],
    ["#9a5a08", "#e0a22c", "#f8df92", 1.4, "N", "needs you"],
    ["#1d5f3b", "#3f9e68", "#b9e6c6", -0.8, "D", "done"],
    ["#5e100e", "#b5342c", "#f0a496", 2.1, "E", "error"],
  ];
  const drips = [
    "M14,10 H256 V300 C256,330 236,330 232,362 C229,386 206,384 204,352 C202,322 178,318 172,340 C166,366 150,402 136,370 C126,346 110,322 96,330 C82,338 86,372 68,366 C50,360 60,318 40,312 C24,308 14,320 14,296 Z",
    "M14,10 H256 V318 C256,350 230,340 226,322 C220,300 196,306 192,336 C188,372 170,380 162,350 C156,326 134,330 130,352 C124,392 100,396 96,356 C94,330 70,326 66,346 C62,366 40,360 38,338 C36,318 14,330 14,302 Z",
    "M14,10 H256 V290 C256,312 242,322 236,346 C230,376 208,372 206,344 C204,318 184,310 176,326 C166,346 150,340 146,322 C140,300 118,306 114,336 C110,384 84,388 80,344 C78,318 56,316 50,334 C44,352 14,346 14,310 Z",
    "M14,10 H256 V306 C256,336 238,356 230,338 C222,318 204,320 200,344 C196,386 172,392 168,350 C166,326 146,318 140,334 C134,350 116,346 112,330 C106,306 84,314 82,340 C80,370 58,372 54,346 C50,322 14,336 14,298 Z",
  ];
  // An uneven slab: corners and sides wobble a little, as a hand-cut tile does.
  const slab = () => {
    const j = () => (rnd() * 5 - 2.5).toFixed(1);
    return `M${12 + +j()},${6 + +j()} Q135,${+j()} ${258 + +j()},${6 + +j()} Q${266 + +j()},220 ${260 + +j()},432 Q135,${440 + +j()} ${10 + +j()},${433 + +j()} Q${4 + +j()},220 ${12 + +j()},6 Z`;
  };
  const craze = () => {
    let d = "";
    for (let k = 0; k < 16; k++) {
      let x = 16 + rnd() * 236, y = 14 + rnd() * 300;
      d += `M${x.toFixed(0)},${y.toFixed(0)}`;
      for (let s = 0; s < 4; s++) { x += rnd() * 60 - 30; y += rnd() * 50 - 18; d += `L${x.toFixed(0)},${y.toFixed(0)}`; }
    }
    return d;
  };
  let tiles = "";
  G.forEach((g, i) => {
    const cz = craze();
    let specks = "";
    for (let k = 0; k < 22; k++) specks += `<circle cx="${(20 + rnd() * 230).toFixed(0)}" cy="${(16 + rnd() * 300).toFixed(0)}" r="${(0.8 + rnd() * 1.4).toFixed(1)}"/>`;
    tiles += `<g class="gt-tile t${i + 1}"><g transform="translate(${48 + i * 290},48) scale(.94) rotate(${g[3]} 135 440)" filter="url(#gt-sh)">
      <defs><linearGradient id="gt-g${i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${g[2]}"/><stop offset=".1" stop-color="${g[1]}"/><stop offset=".66" stop-color="${g[1]}"/><stop offset="1" stop-color="${g[0]}"/></linearGradient>
      <clipPath id="gt-c${i}"><path d="${drips[i]}"/></clipPath></defs>
      <path d="${slab()}" fill="#c4a682"/>
      <path d="${slab()}" fill="#000" filter="url(#gt-bq)" opacity=".5"/>
      <path d="${drips[i]}" fill="url(#gt-g${i})"/>
      <g clip-path="url(#gt-c${i})">
        <rect width="270" height="440" filter="url(#gt-mo)" opacity=".28"/>
        <g fill="${g[0]}" opacity=".55">${specks}</g>
        <path d="${cz}" fill="none" stroke="${g[0]}" stroke-width="1.1" opacity=".45" transform="translate(.8,.9)"/>
        <path d="${cz}" fill="none" stroke="#fff" stroke-width=".7" opacity=".5"/>
        <path d="M36,30 C30,120 32,214 40,296" stroke="#fff" stroke-width="16" stroke-linecap="round" fill="none" opacity=".32" filter="url(#gt-bl)"/>
        <path d="M36,30 C32,96 33,150 35,206" stroke="#fff" stroke-width="3.5" stroke-linecap="round" fill="none" opacity=".75"/>
        <rect x="196" y="34" width="20" height="30" rx="6" fill="#fff" opacity=".7"/><rect x="220" y="34" width="14" height="30" rx="5" fill="#fff" opacity=".5"/>
      </g>
      <path d="${drips[i]}" fill="none" stroke="${g[0]}" stroke-width="3" opacity=".6"/>
      <path d="${drips[i]}" fill="none" stroke="#fff" stroke-width="1.2" opacity=".35" transform="translate(0,-1.6)"/>
      <circle cx="135" cy="44" r="13" fill="#d9d1c1"/><circle cx="135" cy="44" r="13" fill="none" stroke="#2a1c14" stroke-opacity=".5" stroke-width="2.5"/>
      <text x="135" y="418" text-anchor="middle" font-family="Courier Prime, monospace" font-weight="700" font-size="17" fill="#5b3a25" letter-spacing="3">Nº ${i + 1} · ${g[4]}</text>
    </g>
    <text x="${162 + i * 290}" y="528" text-anchor="middle" font-family="Caveat, cursive" font-size="30" fill="#5b3a25" transform="rotate(-1.5 ${162 + i * 290} 528)">${g[5]}</text></g>`;
  });
  art.innerHTML = `<svg viewBox="0 0 1200 540" role="presentation">
    <defs>
      <filter id="gt-bq" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".6" numOctaves="2" seed="5"/><feColorMatrix values="0 0 0 0 .25 0 0 0 0 .15 0 0 0 0 .07 0 0 0 7 -4.4"/><feComposite in2="SourceGraphic" operator="in"/></filter>
      <filter id="gt-mo" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".016 .05" numOctaves="3" seed="3"/><feColorMatrix values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 1.6 -.75"/></filter>
      <filter id="gt-bl"><feGaussianBlur stdDeviation="4"/></filter>
      <filter id="gt-sh" x="-20%" y="-10%" width="140%" height="125%"><feDropShadow dx="0" dy="3" stdDeviation="0" flood-color="#2a1c14" flood-opacity=".25"/><feDropShadow dx="10" dy="2" stdDeviation="9" flood-color="#2a1c14" flood-opacity=".2"/></filter>
      <linearGradient id="gt-wood" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#86634a"/><stop offset="1" stop-color="#5a3e2a"/></linearGradient>
    </defs>
    <rect x="0" y="462" width="1200" height="30" fill="url(#gt-wood)"/>
    <rect x="0" y="462" width="1200" height="3" fill="#fff" opacity=".18"/>
    <rect x="0" y="492" width="1200" height="12" fill="#2a1c14" opacity=".16"/>
    ${tiles}
  </svg>`;
})();
