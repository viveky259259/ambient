// Zellige's hero art: an arch of hand-cut eight-pointed stars on teal grout. Most are white and teal glaze; a few
// are glazed in the state colours, one per session. The keystone is Ambient's island, its lamp and word in the
// demo's current state (theme.css, --state and data-mood on <html>).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const star = (cx, cy, R) => {
    let p = "";
    for (let i = 0; i < 16; i++) {
      const r = i % 2 ? R * 0.7654 : R, a = (i * Math.PI) / 8;
      p += (i ? "L" : "M") + (cx + Math.sin(a) * r).toFixed(1) + "," + (cy - Math.cos(a) * r).toFixed(1);
    }
    return p + "Z";
  };
  let seed = 7;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const A = "M40,1000 V470 A280,280 0 1 1 600,470 V1000 Z";
  const S = 70, white = ["#f4ecdc", "#ebe1cd", "#f8f2e6", "#e4d9c2", "#efe6d3"], teal = ["#2a7f83", "#3a9296", "#1f6468"];
  const sess = { "4,1": "#e3a21a", "2,4": "#2a4fa3", "6,5": "#2d8a57", "3,7": "#c8673f", "5,9": "#b3271f", "2,10": "#2d8a57", "6,11": "#2a4fa3", "4,12": "#2a4fa3", "1,7": "#2d8a57" };
  let h = `<defs><clipPath id="zl-ac"><path d="${A}"/></clipPath>
    <filter id="zl-gz" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".04" numOctaves="3" seed="5"/><feColorMatrix values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 1.4 -.6"/></filter></defs>
    <path d="${A}" fill="none" stroke="#e3a21a" stroke-width="34"/><path d="${A}" fill="none" stroke="#143f42" stroke-width="22"/>
    <g clip-path="url(#zl-ac)"><rect width="640" height="1010" fill="#17494d"/>`;
  for (let r = 0; r < 15; r++)
    for (let c = 0; c < 10; c++) {
      const cx = 5 + c * S, cy = 20 + r * S, k = c + "," + r;
      let f = sess[k];
      if (!f) { const v = rnd(); f = v < 0.16 ? teal[Math.floor(rnd() * 3)] : white[Math.floor(rnd() * 5)]; }
      // Hand-cut: each star a touch off size and off centre.
      h += `<path d="${star(cx + rnd() * 2 - 1, cy + rnd() * 2 - 1, S / 2 - 2.5 - rnd() * 1.5)}" fill="${f}"/>`;
      if (sess[k]) h += `<ellipse cx="${cx - 8}" cy="${cy - 10}" rx="9" ry="5" fill="#fff" opacity=".4" transform="rotate(-30 ${cx - 8} ${cy - 10})"/>`;
      h += `<rect x="${cx + S / 2 - 7}" y="${cy + S / 2 - 7}" width="14" height="14" transform="rotate(45 ${cx + S / 2} ${cy + S / 2})" fill="${rnd() < 0.5 ? "#b8663d" : "#e3a21a"}"/>`;
    }
  h += `<rect width="640" height="1010" filter="url(#zl-gz)" opacity=".16"/></g>`;
  const words = { working: "WORKING", waiting: "NEEDS YOU", done: "DONE", error: "ERROR" };
  h += `<rect x="244" y="214" width="152" height="46" rx="23" fill="#0d0d0d" stroke="#f2e9d9" stroke-width="4"/><circle class="zl-key" cx="272" cy="237" r="11"/>`;
  for (const m in words) h += `<text class="zl-t ${m}" x="292" y="242.5" font-family="Inconsolata, monospace" font-weight="600" font-size="15" fill="#f2e9d9" letter-spacing="1.5">${words[m]}</text>`;
  art.innerHTML = `<svg viewBox="0 156 640 856" role="presentation">${h}</svg>`;
})();
