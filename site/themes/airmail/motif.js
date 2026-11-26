// Airmail's hero art: four perforated stamps, one per state, and a postmark that moves to cancel the stamp of the
// demo's current state (data-mood on <html>, set by main.js).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const P = "#f3efe3", K = "#1d2233";
  const S = [
    ["working", "Working", "--claude", "#fff", "An orb in the agent's", "colour breathes.",
      `<circle r="60" fill="none" stroke="#fff" stroke-width="1.5" stroke-dasharray="2 4"/><circle r="46" fill="none" stroke="#fff" stroke-width="2"/><circle r="28" fill="#fff"/>`],
    ["waiting", "Needs you", "--waiting", K, "An amber pulse.", "",
      `<circle r="60" fill="none" stroke="${K}" stroke-width="2"/><circle r="44" fill="none" stroke="${K}" stroke-width="2"/><circle r="28" fill="none" stroke="${K}" stroke-width="2"/><circle r="13" fill="${K}"/>`],
    ["done", "Done", "--done", "#fff", "Green, until you look", "at the session.",
      `<circle r="56" fill="#fff"/><path d="M-27 2l19 21 36-44" fill="none" stroke-width="10" class="tk"/>`],
    ["error", "Error", "--error", "#fff", "Red, with the reason", "one hover away.",
      `<circle r="56" fill="none" stroke="#fff" stroke-width="3"/><path d="M-26 -26L26 26M26 -26L-26 26" stroke="#fff" stroke-width="11"/>`],
  ];
  const w = 270, h = 320, at = [[20, 30], [310, 30], [20, 370], [310, 370]];
  let stamps = "";
  S.forEach(([mood, name, c, t, d1, d2, icon], i) => {
    const [x, y] = at[i];
    let perf = "";
    for (let k = 0; k <= w / 18; k++) perf += `<circle cx="${x + k * 18}" cy="${y}" r="5.5"/><circle cx="${x + k * 18}" cy="${y + h}" r="5.5"/>`;
    for (let k = 1; k < h / 18; k++) perf += `<circle cx="${x}" cy="${y + k * 18}" r="5.5"/><circle cx="${x + w}" cy="${y + k * 18}" r="5.5"/>`;
    const tone = mood === "waiting" ? `var(${c})` : `color-mix(in srgb, var(${c}) 72%, #000)`;
    stamps += `<g style="--t:${tone}"><rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#fffdf6"/><g fill="${P}">${perf}</g>
      <rect x="${x + 14}" y="${y + 14}" width="${w - 28}" height="${h - 28}" style="fill:var(--t)"/>
      <rect x="${x + 14}" y="${y + 14}" width="${w - 28}" height="${h - 28}" fill="url(#am-lines)"/>
      <g transform="translate(${x + w / 2} ${y + 112})">${icon}</g>
      <text class="nm" x="${x + 30}" y="${y + 228}" fill="${t}">${name}</text>
      <text class="ds" x="${x + 30}" y="${y + 256}" fill="${t}">${d1}</text><text class="ds" x="${x + 30}" y="${y + 275}" fill="${t}">${d2}</text></g>`;
  });
  let waves = "";
  for (let k = 0; k < 5; k++) waves += `<path d="M96 ${-44 + k * 22}q18-14 36 0t36 0 36 0 36 0"/>`;
  art.innerHTML = `<svg class="am" viewBox="0 0 600 700" role="presentation">
    <defs><pattern id="am-lines" width="6" height="5" patternUnits="userSpaceOnUse"><rect width="6" height="2" fill="#fff" opacity=".1"/></pattern>
      <path id="am-a" d="M-68 0A68 68 0 0 1 68 0"/><path id="am-b" d="M-66 0A66 66 0 0 0 66 0"/></defs>
    <g filter="drop-shadow(0 3px 4px rgba(0,0,0,.2))">${stamps}</g>
    <g class="pm"><g fill="none" stroke="${K}" opacity=".78" transform="rotate(-8)">
      <circle r="82" stroke-width="3"/><circle r="54" stroke-width="2"/>
      <text font-size="15" fill="${K}" stroke="none" letter-spacing="3"><textPath href="#am-a" startOffset="50%" text-anchor="middle">YAML.CAFE</textPath></text>
      <text font-size="13" fill="${K}" stroke="none" letter-spacing="2" dy="12"><textPath href="#am-b" startOffset="50%" text-anchor="middle">macOS 14 OR LATER</textPath></text>
      <text y="-3" text-anchor="middle" font-size="17" fill="${K}" stroke="none">ABOUT</text><text y="17" text-anchor="middle" font-size="17" fill="${K}" stroke="none">15 MS</text>
      <g stroke-width="3">${waves}</g></g></g>
  </svg>`;
  art.querySelectorAll(".tk").forEach((p) => p.setAttribute("style", "stroke:var(--t)"));
  const pm = art.querySelector(".pm");
  const spot = { working: 0, waiting: 1, done: 2, error: 3 };
  const sync = () => {
    const [x, y] = at[spot[document.documentElement.dataset.mood] ?? 0];
    pm.style.transform = `translate(${x + 30}px, ${y + 26}px)`;
  };
  sync();
  new MutationObserver(sync).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
