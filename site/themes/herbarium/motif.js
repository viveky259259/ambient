// Herbarium's hero art: a pressed specimen on its mount sheet. Its blooms are Ambient's four states; the top
// bloom opens in the demo's current state colour (--state), pencil notes name each one, and a typed collection
// label sits in the corner.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const leaf = (x, y, rx, a) => `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${(rx * 0.34).toFixed(1)}" transform="rotate(${a} ${x} ${y})"/>`;
  const hand = (x, y, t, anchor = "start") => `<text x="${x}" y="${y}" text-anchor="${anchor}">${t}</text>`;
  art.innerHTML = `
    <svg class="hrb-sheet" viewBox="0 0 520 640" role="presentation">
      <rect x="8" y="8" width="504" height="624" fill="#f3ebd4" stroke="#b9ad8b"/>
      <g fill="none" stroke="#4d6b2f" stroke-width="3.2" stroke-linecap="round">
        <path d="M250 560 C244 420 262 300 256 150"/>
        <path d="M252 430 C200 390 160 330 136 262"/>
        <path d="M255 330 C310 300 360 250 388 200"/>
        <path d="M254 250 C222 222 196 196 182 160"/>
        <path d="M251 500 C300 476 348 450 378 404"/>
      </g>
      <g fill="#6f8a48" stroke="#4d6b2f" stroke-width="1.5">
        ${leaf(190, 360, 40, -50)}${leaf(330, 280, 42, -42)}${leaf(216, 220, 32, 50)}${leaf(320, 468, 38, -30)}${leaf(212, 470, 34, 28)}${leaf(280, 390, 30, -18)}
      </g>
      <circle class="halo" cx="256" cy="140" r="40"/>
      <circle class="bloom" cx="256" cy="140" r="25"/>
      <circle cx="136" cy="256" r="19" fill="#d97757"/>
      <circle cx="182" cy="154" r="14" fill="#d97757"/>
      <circle cx="390" cy="194" r="19" fill="#3fb950"/>
      <circle cx="380" cy="398" r="16" fill="#e2493d"/>
      <g stroke="#3b4a6b" stroke-width="1"><path d="M290 134 H372"/><path d="M114 256 H54"/><path d="M414 194 H470"/><path d="M400 398 H456"/></g>
      <g font-family="Caveat, 'Bradley Hand', cursive" font-size="23" fill="#3b4a6b">
        ${hand(378, 128, "now showing")}${hand(52, 284, "working")}${hand(52, 306, "(Claude)")}${hand(418, 222, "done")}${hand(404, 426, "error!")}
      </g>
      <rect x="224" y="548" width="66" height="18" fill="#e6d9a8cc" transform="rotate(-4 257 557)"/>
      <rect x="226" y="340" width="18" height="58" fill="#e6d9a8b0" transform="rotate(8 235 369)"/>
      <g transform="translate(300 520)">
        <rect width="196" height="92" fill="#fbf6e6" stroke="#8c8163"/>
        <text x="12" y="27" font-family="'IM Fell English', Georgia, serif" font-style="italic" font-size="20" fill="#2e2a1e">Ambient notchii</text>
        <path d="M12 36 H184" stroke="#8c8163"/>
        <g font-family="'Special Elite', 'Courier New', monospace" font-size="10.5" fill="#2e2a1e">
          <text x="12" y="54">Hab. the notch, Dock, menu bar</text>
          <text x="12" y="69">Coll. hooks, ~15 ms</text>
          <text x="12" y="84">No. 0.10.0 · MIT</text>
        </g>
      </g>
    </svg>`;
})();
