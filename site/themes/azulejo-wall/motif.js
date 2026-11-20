// Azulejo wall's hero art: a panel of cobalt tiles read as one pattern, with a few glazed in the colours of agent
// sessions. The centre tile is the one the eye goes to; it follows the demo's current state (--state on <html>).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const S = 80, B = "#1e4aa8", W = "#fbf9f1", G = "#e0a526";
  const odd = { "0,3": "#d97757", "1,1": "#10a37f", "3,0": "#2a9a5a", "4,3": "#4f8df7", "3,4": "#f0a513", "1,4": "#d83a2b" };
  let s = "";
  for (let r = 0; r < 5; r++) for (let c = 0; c < 5; c++) {
    const live = r === 2 && c === 2;
    const col = odd[r + "," + c];
    const fill = live ? 'class="live"' : `fill="${col || B}"`;
    s += `<g transform="translate(${c * S} ${r * S})"><rect width="${S}" height="${S}" fill="${W}" stroke="#cfd3dc" stroke-width="1.5"/>`;
    for (const [x, y] of [[0, 0], [S, 0], [0, S], [S, S]]) s += `<circle cx="${x}" cy="${y}" r="30" fill="${B}"/><circle cx="${x}" cy="${y}" r="17" fill="${W}"/><circle cx="${x}" cy="${y}" r="8" fill="${G}"/>`;
    s += `<rect x="26" y="26" width="28" height="28" ${fill} transform="rotate(45 40 40)"/><rect x="26" y="26" width="28" height="28" ${fill}/>`;
    s += `<circle cx="40" cy="40" r="${col || live ? 11 : 8}" ${col || live ? fill : `fill="${W}"`} stroke="${W}" stroke-width="${col || live ? 4 : 0}"/>`;
    if (col) s += `<rect x="3" y="3" width="${S - 6}" height="${S - 6}" fill="none" stroke="${col}" stroke-width="5"/>`;
    if (live) s += `<rect class="live-rim" x="3" y="3" width="${S - 6}" height="${S - 6}" fill="none" stroke-width="6"/>`;
    for (const [x, y] of [[40, 6], [40, 74], [6, 40], [74, 40]]) s += `<circle cx="${x}" cy="${y}" r="3.5" fill="${B}"/>`;
    s += `</g>`;
  }
  art.innerHTML = `<svg class="azl-panel" viewBox="0 0 400 400" role="presentation">${s}</svg>`;
})();
