// Hi-fi receiver's hero art: a receiver with a grille, four state lamps, a dial for the agents and a row of keys.
// The lamp for the demo's current state lights and the needle swings to it (data-mood on <html>, via theme.css).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const lamps = [["working", "var(--claude)"], ["waiting", "var(--waiting)"], ["done", "var(--done)"], ["error", "var(--error)"]];
  const names = { working: "working", waiting: "needs you", done: "done", error: "error" };
  const keys = ["notch", "dock", "chime", "menu", "wall"];
  let ticks = "";
  for (let a = -60; a <= 60; a += 5) {
    const r = (a * Math.PI) / 180, l = a % 20 === 0 ? 14 : 7;
    ticks += `<line x1="${(500 + Math.sin(r) * 88).toFixed(1)}" y1="${(196 - Math.cos(r) * 88).toFixed(1)}" x2="${(500 + Math.sin(r) * (88 - l)).toFixed(1)}" y2="${(196 - Math.cos(r) * (88 - l)).toFixed(1)}" stroke="#1b1b1a" stroke-width="1.2"/>`;
  }
  art.innerHTML = `<svg class="hf-unit" viewBox="0 0 640 400" role="presentation">
    <defs>
      <linearGradient id="hfc" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f1eee8"/><stop offset="1" stop-color="#e5e1d8"/></linearGradient>
      <pattern id="hfg" width="12" height="12" patternUnits="userSpaceOnUse"><circle cx="6" cy="6" r="2.3" fill="#1b1b1a"/></pattern>
    </defs>
    <rect x="4" y="4" width="632" height="384" rx="12" fill="url(#hfc)"/>
    <rect x="4" y="384" width="632" height="4" rx="2" fill="#c6c1b6"/>
    <rect x="28" y="28" width="236" height="336" rx="4" fill="url(#hfg)"/>
    <text x="292" y="50" font-size="17" font-weight="500" style="fill:#1b1b1a;font-size:17px">ambient</text>
    <text x="612" y="50" text-anchor="end">agent receiver · 0.10</text>
    <line x1="292" y1="64" x2="612" y2="64" stroke="#b9b4a8"/>
    <text x="292" y="92">state</text>
    ${lamps.map(([m, c], i) => `<g transform="translate(${306 + i * 0}, ${118 + i * 44})"><circle cx="8" cy="0" r="11" fill="#cfcabf"/><circle class="hf-lamp ${m}" style="--c:${c}" cx="8" cy="0" r="8" fill="${c}"/><text x="28" y="4">${names[m]}</text></g>`).join("")}
    <circle cx="500" cy="196" r="96" fill="#f6f4ef" stroke="#d7d2c7" stroke-width="2"/>
    ${ticks}
    <text x="500" y="244" text-anchor="middle">claude · codex · gemini</text>
    <g class="hf-needle"><rect x="498" y="118" width="4" height="54" rx="2" fill="#e8501c"/></g>
    <circle cx="500" cy="196" r="9" fill="#1b1b1a"/>
    <line x1="292" y1="316" x2="612" y2="316" stroke="#b9b4a8"/>
    ${keys.map((k, i) => `<g transform="translate(${292 + i * 52}, 330)"><rect width="44" height="30" rx="5" fill="#bdb8ad" y="3"/><rect width="44" height="30" rx="5" fill="#f6f4ef"/><text x="22" y="19" text-anchor="middle" style="font-size:10px">${k}</text></g>`).join("")}
    <circle cx="590" cy="347" r="21" fill="#8a2e08"/><circle cx="590" cy="343" r="21" fill="#e8501c"/>
  </svg>`;
})();
