// Brutalist block's hero art: a concrete tower of dark windows. Each lit window is a session in its state's
// colour, and the island pill on the roof shows the most urgent one in the demo's state colour (--state).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const lit = { "1,2": ["#d97757", "claude · api"], "3,5": ["#f2a200", "codex · web"], "5,1": ["#3fc46b", "gemini · docs"], "7,4": ["#10a37f", "codex · infra"], "6,6": ["#ee3b2b", "claude · tests"], "8,2": ["#4f8df7", "gemini · cli"] };
  let w = "";
  for (let r = 0; r < 9; r++) for (let c = 0; c < 7; c++) {
    const x = 70 + c * 66, y = 150 + r * 60, k = lit[r + "," + c];
    if (k) {
      w += `<rect class="lit" x="${x}" y="${y}" width="42" height="44" fill="${k[0]}" style="filter:drop-shadow(0 0 12px ${k[0]})"/>`;
      w += `<text x="${c > 4 ? x + 42 : x}" y="${y + 56}" text-anchor="${c > 4 ? "end" : "start"}" font-family="'Martian Mono', Menlo, monospace" font-size="8.5" letter-spacing=".6" fill="#d8d3c7">${k[1].toUpperCase()}</text>`;
    } else w += `<rect x="${x}" y="${y}" width="42" height="44" fill="#191816"/><rect x="${x}" y="${y}" width="42" height="5" fill="#0f0f0e"/>`;
  }
  art.innerHTML = `
    <svg class="brt-art" viewBox="0 0 560 700" role="presentation">
      <rect x="64" y="40" width="168" height="40" rx="20" fill="#0b0b0a"/>
      <circle class="now" cx="88" cy="60" r="9"/>
      <text x="248" y="64" font-family="'Martian Mono', Menlo, monospace" font-size="10" letter-spacing="1.2" fill="#161513">THE MOST URGENT WINDOW</text>
      <rect x="22" y="128" width="30" height="572" fill="#9c978c"/>
      <rect x="40" y="104" width="500" height="18" fill="#161513"/>
      <rect x="40" y="122" width="500" height="578" fill="#2b2a27"/>
      ${w}
    </svg>`;
})();
