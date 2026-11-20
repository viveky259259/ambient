// Watch dial's hero art: a chronograph dial. Four sub-dials hold the four states as jewel lamps; the aperture at
// twelve is Ambient's island, its lamp in the demo's current colour (--state), and the blued hand turns to the
// sub-dial of the current mood (theme.css, data-mood on <html>).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const ink = "#14161b", blue = "#1f3a7a", mono = "Azeret Mono, monospace", serif = "Bodoni Moda, Didot, serif";
  const rot = (a) => `transform="rotate(${a})"`;
  let h = `<defs>
    <radialGradient id="wd-face" cx="40%" cy="35%" r="75%"><stop offset="0" stop-color="#fbfbfa"/><stop offset=".7" stop-color="#e3e4e6"/><stop offset="1" stop-color="#c9ccd1"/></radialGradient>
    <linearGradient id="wd-bez" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fdfdfd"/><stop offset=".3" stop-color="#9fa4ac"/><stop offset=".55" stop-color="#eef0f2"/><stop offset=".8" stop-color="#7d838c"/><stop offset="1" stop-color="#d7dadf"/></linearGradient>
    <linearGradient id="wd-blue" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#162a5c"/><stop offset=".5" stop-color="#3a62c2"/><stop offset="1" stop-color="#162a5c"/></linearGradient>
    <radialGradient id="wd-sub" cx="50%" cy="40%" r="70%"><stop offset="0" stop-color="#eceef0"/><stop offset="1" stop-color="#cfd3d8"/></radialGradient>
    <filter id="wd-sh" x="-10%" y="-10%" width="120%" height="120%"><feDropShadow dx="0" dy="6" stdDeviation="6" flood-opacity=".3"/></filter></defs>`;
  h += `<rect x="405" y="-34" width="42" height="68" rx="6" fill="url(#wd-bez)" stroke="#6d727a"/>`;
  for (let i = 0; i < 8; i++) h += `<line x1="412" x2="444" y1="${-28 + i * 8}" y2="${-28 + i * 8}" stroke="#6d727a" stroke-width="1.5"/>`;
  h += `<circle r="418" fill="url(#wd-bez)" filter="url(#wd-sh)"/><circle r="392" fill="#b9bdc3"/><circle r="386" fill="url(#wd-face)"/>`;
  for (let r = 14; r < 120; r += 5) h += `<circle r="${r}" fill="none" stroke="#b9bdc4" stroke-width=".7"/>`;
  for (let a = 0; a < 360; a += 6) h += `<ellipse rx="118" ry="38" ${rot(a)} fill="none" stroke="#c3c7cd" stroke-width=".5"/>`;
  h += `<circle r="372" fill="none" stroke="${ink}"/><circle r="346" fill="none" stroke="${ink}"/>`;
  for (let i = 0; i < 240; i++) {
    const big = i % 20 === 0, mid = i % 4 === 0;
    h += `<line y1="-372" y2="${big ? -346 : mid ? -356 : -364}" ${rot(i * 1.5)} stroke="${ink}" stroke-width="${big ? 3 : mid ? 1.3 : 0.6}"/>`;
  }
  for (let i = 1; i < 12; i++) {
    const a = (i * 30 * Math.PI) / 180;
    h += `<text x="${(Math.sin(a) * 322).toFixed(1)}" y="${(-Math.cos(a) * 322 + 6).toFixed(1)}" text-anchor="middle" font-family="${mono}" font-size="15" fill="${ink}">${String(i * 5).padStart(2, "0")}</text>`;
  }
  // The island in the aperture at twelve.
  const words = { working: "WORKING", waiting: "NEEDS YOU", done: "DONE", error: "ERROR" };
  h += `<rect x="-80" y="-338" width="160" height="38" rx="19" fill="#0c0d10"/><circle class="wd-lamp" cx="-56" cy="-319" r="9"/><circle class="wd-lamp" cx="-56" cy="-319" r="14" fill-opacity="0" style="stroke:var(--state,#e39a16)" stroke-opacity=".5" stroke-width="2"/>`;
  for (const m in words) h += `<text class="wd-t ${m}" x="-36" y="-314.5" font-family="${mono}" font-size="11" fill="#f1f1f1" letter-spacing="1.5">${words[m]}</text>`;
  h += `<text y="-262" text-anchor="middle" font-family="${serif}" font-style="italic" font-size="30" fill="${ink}">ambient</text>`;
  h += `<text y="282" text-anchor="middle" font-family="${mono}" font-size="10.5" fill="${ink}" letter-spacing="4">FOUR STATES</text><text y="300" text-anchor="middle" font-family="${mono}" font-size="10.5" fill="${blue}" letter-spacing="4">ONE COLOUR</text>`;
  const S = [[-45, "WORKING", "#2f62d6", "I"], [45, "NEEDS YOU", "#e39a16", "II"], [135, "DONE", "#2f9960", "III"], [225, "ERROR", "#c8372d", "IV"]];
  S.forEach(([ang, name, col, rn]) => {
    const a = (ang * Math.PI) / 180;
    h += `<g transform="translate(${(Math.sin(a) * 200).toFixed(1)},${(-Math.cos(a) * 200).toFixed(1)})"><circle r="108" fill="#aeb2b9"/><circle r="104" fill="url(#wd-sub)"/><circle r="94" fill="none" stroke="${ink}" stroke-width=".8"/>`;
    for (let k = 0; k < 60; k++) h += `<line y1="-94" y2="${k % 5 ? -88 : -82}" ${rot(k * 6)} stroke="${ink}" stroke-width="${k % 5 ? 0.6 : 1.6}"/>`;
    for (let r = 30; r < 78; r += 6) h += `<circle r="${r}" fill="none" stroke="#bfc3c9" stroke-width=".6"/>`;
    h += `<text y="-52" text-anchor="middle" font-family="${mono}" font-size="11.5" letter-spacing="2.5" fill="${ink}">${name}</text><text y="68" text-anchor="middle" font-family="${serif}" font-size="20" fill="${blue}">${rn}</text>`;
    h += `<circle r="34" fill="${col}" opacity=".16"/><circle r="26" fill="${col}" opacity=".28"/><circle r="18" fill="${col}"/><ellipse cx="-5" cy="-7" rx="6" ry="4" fill="#fff" opacity=".55"/></g>`;
  });
  h += `<g class="wd-hand"><g filter="url(#wd-sh)"><path d="M-7,24 L-3.5,-128 L0,-150 L3.5,-128 L7,24 Z" fill="url(#wd-blue)"/><circle cy="-112" r="9" fill="none" stroke="${blue}" stroke-width="3.5"/></g></g>`;
  h += `<circle r="15" fill="url(#wd-bez)" stroke="#6d727a"/><circle r="5" fill="${blue}"/>`;
  art.innerHTML = `<svg viewBox="-452 -452 904 904" role="presentation">${h}</svg>`;
})();
