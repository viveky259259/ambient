// Riso zine's cover art: two ink plates overprinted. A pink disc and a blue halftone block, the island pasted
// on top with its orb in the demo's state colour (--state), and a sticker stuck on crooked.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  art.innerHTML = `
    <svg class="rso-art" viewBox="0 0 560 520" role="presentation">
      <defs>
        <pattern id="rso-dots" width="13" height="13" patternUnits="userSpaceOnUse"><circle cx="6.5" cy="6.5" r="3.8" fill="#1a3fb0"/></pattern>
      </defs>
      <circle class="mx" cx="230" cy="230" r="210" fill="#ff4fa8"/>
      <rect class="mx" x="250" y="250" width="300" height="190" fill="url(#rso-dots)"/>
      <circle class="mx" cx="470" cy="120" r="80" fill="#ff4fa8" opacity=".85"/>
      <g transform="rotate(-4 280 120)">
        <rect x="150" y="84" width="280" height="72" rx="36" fill="#0f1f66"/>
        <circle class="halo" cx="380" cy="120" r="30"/>
        <circle class="orb" cx="380" cy="120" r="19"/>
        <rect x="190" y="112" width="130" height="14" rx="7" fill="#f3ecd9" opacity=".7"/>
      </g>
      <g transform="rotate(-7 300 370)">
        <rect x="128" y="334" width="352" height="76" fill="#ff4fa8"/>
        <rect x="118" y="324" width="352" height="76" fill="#f3ecd9" stroke="#1a3fb0" stroke-width="4"/>
        <text x="294" y="374" text-anchor="middle" font-family="'Bowlby One', 'Arial Black', sans-serif" font-size="30" fill="#1a3fb0" textLength="300" lengthAdjust="spacingAndGlyphs">so you don't have to</text>
      </g>
    </svg>`;
})();
