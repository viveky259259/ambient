// Letterpress broadside's hero art: the bill's "four inks" block. A fat roundel per state, printed with its
// impression ring a hair out of register, worn where the ink didn't take, over the state's name in tall
// condensed caps. The roundel of the demo's current mood presses a little larger (theme.css, data-mood).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const ink = "#1a1410";
  const I = [["#1d3c8f", "WORKING", "first"], ["#dd6400", "NEEDS YOU", "second"], ["#1c7446", "DONE", "third"], ["#c2241a", "ERROR", "fourth"]];
  let cells = "";
  I.forEach(([c, name, nth], i) => {
    const x = 150 + i * 300;
    if (i) cells += `<line x1="${i * 300}" y1="96" x2="${i * 300}" y2="420" stroke="${ink}" stroke-width="2"/>`;
    cells += `<text x="${x}" y="134" text-anchor="middle" font-family="Cutive Mono, monospace" font-size="15" letter-spacing="2.5" fill="${ink}">INK THE ${nth.toUpperCase()}</text>
      <g class="lp-ink i${i + 1}" filter="url(#lp-wear)"><circle cx="${x}" cy="226" r="68" fill="${c}" style="mix-blend-mode:multiply"/>
      <circle cx="${x + 5}" cy="230" r="77" fill="none" stroke="${c}" stroke-width="3.5"/></g>
      <text x="${x}" y="398" text-anchor="middle" font-family="Six Caps, Impact, sans-serif" font-size="${name.length > 6 ? 92 : 104}" letter-spacing="1" fill="${c}" filter="url(#lp-wear)">${name}</text>`;
  });
  art.innerHTML = `<svg viewBox="0 0 1200 440" role="presentation">
    <defs><filter id="lp-wear" x="-5%" y="-5%" width="110%" height="110%"><feTurbulence type="fractalNoise" baseFrequency="1.1" numOctaves="2" seed="3" result="n"/>
      <feColorMatrix in="n" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 9 -6.1" result="m"/><feComposite in="SourceGraphic" in2="m" operator="out"/></filter></defs>
    <g stroke="${ink}"><line x1="0" y1="30" x2="470" y2="30" stroke-width="5"/><line x1="0" y1="40" x2="470" y2="40" stroke-width="1.5"/>
      <line x1="730" y1="30" x2="1200" y2="30" stroke-width="5"/><line x1="730" y1="40" x2="1200" y2="40" stroke-width="1.5"/></g>
    <text x="600" y="44" text-anchor="middle" font-family="Old Standard TT, Georgia, serif" font-size="30" fill="${ink}">✦ In four inks ✦</text>
    <text x="600" y="80" text-anchor="middle" font-family="Old Standard TT, Georgia, serif" font-style="italic" font-size="21" fill="${ink}">shown most urgent first: needs you, then error, then done, then working</text>
    <rect x="0" y="94" width="1200" height="5" fill="${ink}"/>
    ${cells}
    <rect x="0" y="420" width="1200" height="5" fill="${ink}"/>
  </svg>`;
})();
