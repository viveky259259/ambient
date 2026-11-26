// Jazz sleeve's cover art: the notch as a black shape cut into the blue field, its spot lit in the demo's state
// colour (--state), a level meter in the four state colours, and the sleeve's small print.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const bars = [["#d97757", 170], ["#ffb21e", 330], ["#2f9e44", 230], ["#e0453d", 100]]
    .map(([c, h], i) => `<rect class="bar" x="${70 + i * 100}" y="${470 - h}" width="84" height="${h}" fill="${c}"/>`).join("");
  art.innerHTML = `
    <svg class="jzs-art" viewBox="0 0 520 560" role="presentation">
      <path d="M100 0 H420 V60 Q420 112 368 112 H152 Q100 112 100 60 Z" fill="#080808"/>
      <circle class="spot" cx="160" cy="56" r="28"/>
      <rect x="214" y="48" width="140" height="14" rx="7" fill="#efe9db" opacity=".5"/>
      <g>${bars}</g>
      <rect x="60" y="476" width="410" height="6" fill="#080808"/>
      <g font-family="'Libre Franklin', 'Helvetica Neue', sans-serif" font-weight="800" font-size="13" letter-spacing="2.6" fill="#efe9db">
        <text x="60" y="516">WORKING · NEEDS YOU · DONE · ERROR</text>
        <text x="60" y="540" fill="#ffb21e">STEREO · 0.10</text>
      </g>
    </svg>`;
})();
