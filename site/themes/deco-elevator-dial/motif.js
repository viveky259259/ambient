// Deco elevator dial's hero art: the half-dial above a lift door, with a sunburst and stepped setbacks. Its four
// floors are Ambient's states; the needle follows the demo (data-mood on <html>) and that floor's lamp lights.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const cx = 600, cy = 520, R = Math.PI / 180;
  const P = (r, a) => [(cx + r * Math.cos(a * R)).toFixed(1), (cy - r * Math.sin(a * R)).toFixed(1)];
  const arc = (r, a1, a2) => `M${P(r, a1)} A${r} ${r} 0 0 1 ${P(r, a2)}`;
  let s = "";
  for (let a = 0; a <= 180; a += 5) {
    const major = a % 15 === 0;
    s += `<line x1="${P(470, a)[0]}" y1="${P(470, a)[1]}" x2="${P(major ? 590 : 530, a)[0]}" y2="${P(major ? 590 : 530, a)[1]}" stroke="#c9a44a" stroke-width="${major ? 1.6 : 0.6}" opacity="${major ? 0.6 : 0.35}"/>`;
  }
  s += `<path d="${arc(373, 180, 0)}" fill="none" stroke="#10231f" stroke-width="144" opacity=".92"/>`;
  [460, 446, 300, 150].forEach((r, i) => (s += `<path d="${arc(r, 180, 0)}" fill="none" stroke="#c9a44a" stroke-width="${i ? 1.2 : 4}"/>`));
  const floors = [["working", "WORKING", "#d97757"], ["done", "DONE", "#49d17c"], ["error", "ERROR", "#ff5a45"], ["waiting", "NEEDS YOU", "#ffb52e"]];
  floors.forEach(([mood, label, c], i) => {
    const a1 = 180 - i * 45, m = a1 - 22.5, [lx, ly] = P(398, m), [tx, ty] = P(336, m);
    if (i) s += `<line x1="${P(300, a1)[0]}" y1="${P(300, a1)[1]}" x2="${P(446, a1)[0]}" y2="${P(446, a1)[1]}" stroke="#c9a44a" stroke-width="1.2"/>`;
    for (let k = 1; k < 9; k++) s += `<line x1="${P(446, a1 - k * 5)[0]}" y1="${P(446, a1 - k * 5)[1]}" x2="${P(434, a1 - k * 5)[0]}" y2="${P(434, a1 - k * 5)[1]}" stroke="#c9a44a"/>`;
    s += `<g class="lamp" data-floor="${mood}"><circle class="ring" cx="${lx}" cy="${ly}" r="26" fill="none" stroke="${c}" stroke-width="2"/><circle cx="${lx}" cy="${ly}" r="30" fill="${c}" opacity=".16"/><circle cx="${lx}" cy="${ly}" r="16" fill="${c}"/></g>`;
    s += `<text x="${tx}" y="${ty}" fill="#f3e9d2" font-family="'Josefin Sans', Futura, sans-serif" font-size="17" letter-spacing="4" text-anchor="middle" transform="rotate(${90 - m} ${tx} ${ty})">${label}</text>`;
  });
  for (const d of [-1, 1]) for (let k = 0; k < 4; k++) {
    const h = 20 + (3 - k) * 26, x = cx + d * (500 + k * 22) - (d < 0 ? 18 : 0);
    s += `<rect x="${x}" y="${cy - h}" width="18" height="${h}" fill="none" stroke="#c9a44a" stroke-width="1.2"/>`;
  }
  s += `<line x1="20" y1="${cy + 1}" x2="1180" y2="${cy + 1}" stroke="#c9a44a" stroke-width="3"/>`;
  s += `<g class="needle"><polygon points="${cx + 290},${cy} ${cx},${cy - 14} ${cx - 60},${cy} ${cx},${cy + 14}" fill="#e8cf85"/></g>`;
  s += `<circle cx="${cx}" cy="${cy}" r="34" fill="#0d0f12" stroke="#c9a44a" stroke-width="3"/><circle cx="${cx}" cy="${cy}" r="12" fill="#e8cf85"/>`;
  art.innerHTML = `<svg class="dco-art" viewBox="0 0 1200 560" role="presentation">${s}</svg>`;
  const angle = { working: 157.5, done: 112.5, error: 67.5, waiting: 22.5 };
  const needle = art.querySelector(".needle"), root = document.documentElement;
  const point = () => {
    const mood = angle[root.dataset.mood] ? root.dataset.mood : "working";
    needle.style.transform = `rotate(${-angle[mood]}deg)`;
    for (const l of art.querySelectorAll(".lamp")) l.classList.toggle("on", l.dataset.floor === mood);
  };
  point();
  new MutationObserver(point).observe(root, { attributes: true, attributeFilter: ["data-mood"] });
})();
