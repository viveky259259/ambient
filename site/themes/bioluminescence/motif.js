// Bioluminescence's hero art: four jellyfish, one per state, hanging lower the less urgent they are, in marine
// snow. The jelly of the demo's current state (data-mood on <html>, set by main.js) glows brighter. A row for wide
// screens and a 2 x 2 drift for phones (theme.css shows one).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const S = [
    ["waiting", "Needs you", "amber pulse", "--waiting"],
    ["error", "Error", "red · the reason", "--error"],
    ["done", "Done", "green until seen", "--done"],
    ["working", "Working", "the agent's colour", "--claude"],
  ];
  let seed = 7;
  const R = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const bell = "M30 122 C30 30,210 30,210 122 C192 138,172 112,150 126 C130 140,110 112,90 126 C68 140,48 112,30 122Z";
  const jelly = (p, i, [mood, name, lat, c], x, y, sc, label = true) => {
    let t = "";
    for (let k = 0; k < 7; k++) {
      const tx = 48 + k * 24, len = 150 + ((k * 37 + i * 53) % 90), a = (k % 2 ? 1 : -1) * (8 + ((k * 13 + i * 7) % 8));
      t += `<path d="M${tx} 124 C${tx + a} ${124 + len * 0.3},${tx - a} ${124 + len * 0.6},${tx + a * 0.6} ${124 + len}" stroke-opacity="${(0.35 + ((k * 17) % 40) / 100).toFixed(2)}" stroke-width="${k % 3 ? 1.2 : 2.2}"/>`;
    }
    const id = `${p}g${i}`;
    return `<g class="jl${label ? "" : " far"}" data-m="${mood}" style="--c:var(${c})"><defs><radialGradient id="${id}" cx="50%" cy="38%" r="60%"><stop offset="0" stop-color="#fff" stop-opacity=".95"/><stop offset=".18" stop-opacity=".85" style="stop-color:var(${c})"/><stop offset="1" stop-opacity=".12" style="stop-color:var(${c})"/></radialGradient></defs><g transform="translate(${x} ${y}) scale(${sc})">
      <ellipse class="glow" cx="120" cy="96" rx="96" ry="72" style="fill:var(--c)" filter="url(#${p}b)"/>
      <g fill="none" stroke-linecap="round" style="stroke:var(--c)">${t}</g>
      <path d="${bell}" fill="url(#${id})" stroke-width="1.5" style="stroke:var(--c)"/>
      <path d="M52 108 C60 60,180 60,188 108" stroke="#fff" stroke-opacity=".35" fill="none"/><path d="M76 112 C84 76,156 76,164 112" stroke="#fff" stroke-opacity=".25" fill="none"/>
      ${label ? `<text class="nm" x="120" y="372" text-anchor="middle" style="fill:var(--c)">${name}</text><text class="lt" x="120" y="400" text-anchor="middle" style="fill:var(--c)">${lat}</text>` : ""}
    </g></g>`;
  };
  const defs = (p) => `<defs><filter id="${p}b" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="26"/></filter></defs>`;
  const snow = (w, h, n) => { let s = ""; for (let i = 0; i < n; i++) s += `<circle cx="${(R() * w).toFixed(0)}" cy="${(R() * h).toFixed(0)}" r="${(0.5 + R() * 1.6).toFixed(1)}" fill="#c8f0ee" opacity="${(0.1 + R() * 0.35).toFixed(2)}"/>`; return s; };
  const svg = (p, w, h, pos, far) => {
    let g = "";
    far.forEach(([x, y, sc], j) => { g += jelly(p, j + 5, S[3], x, y, sc, false); });
    S.forEach((s, i) => { g += jelly(p, i, s, pos[i][0], pos[i][1], pos[i][2]); });
    return `<svg class="blm blm-${p === "w" ? "wide" : "tall"}" viewBox="0 0 ${w} ${h}" role="presentation">${defs(p)}${snow(w, h, p === "w" ? 140 : 90)}${g}</svg>`;
  };
  art.innerHTML =
    svg("w", 1200, 560, [[80, 0, 0.74], [370, 50, 0.74], [660, 100, 0.74], [950, 150, 0.74]], [[20, 380, 0.24], [560, 440, 0.2], [1120, 40, 0.22]]) +
    svg("t", 600, 760, [[20, 0, 0.7], [320, 60, 0.7], [20, 380, 0.7], [320, 440, 0.7]], [[250, 330, 0.2], [520, 700, 0.16]]);
  art.querySelectorAll(".far").forEach((g) => { g.style.opacity = ".35"; });
  const sync = () => {
    const m = document.documentElement.dataset.mood || "working";
    art.querySelectorAll(".jl:not(.far)").forEach((g) => g.classList.toggle("on", g.dataset.m === m));
  };
  sync();
  new MutationObserver(sync).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
