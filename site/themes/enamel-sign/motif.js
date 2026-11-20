// Enamel sign's hero art: four arrow plates, one per state, in cream-bordered enamel with a lamp in a cream ring.
// The lamp of the demo's current mood glows (theme.css, data-mood on <html>); a chip or two is knocked out.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const cream = "#f6f1e4", navy = "#0a1c4a";
  const P = [
    ["working", "#36a9dc", navy, "WORKING", "An orb in the agent's colour breathes."],
    ["waiting", "#f2a516", navy, "NEEDS YOU", "An amber pulse."],
    ["done", "#1f8f4e", cream, "DONE", "Green, until you look at the session."],
    ["error", "#d6281e", cream, "ERROR", "Red, with the reason one hover away."],
  ];
  const arrow = (x, y, w, h, tip) => `M${x},${y} H${x + w - tip} L${x + w},${y + h / 2} L${x + w - tip},${y + h} H${x} Z`;
  let h = `<defs>
    <linearGradient id="en-sheen" x1="0" y1="0" x2=".3" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".24"/><stop offset=".35" stop-color="#fff" stop-opacity="0"/><stop offset=".75" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".2"/></linearGradient>
    <filter id="en-sh" x="-5%" y="-5%" width="115%" height="120%"><feDropShadow dx="6" dy="10" stdDeviation="8" flood-color="#050e28" flood-opacity=".45"/></filter>
    <filter id="en-glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="14"/></filter></defs>`;
  P.forEach(([mood, c, t, name, line], i) => {
    const y = i * 252, cy = y + 110;
    h += `<g filter="url(#en-sh)"><path d="${arrow(0, y, 556, 220, 74)}" fill="${cream}"/>
      <path d="${arrow(8, y + 8, 530, 204, 68)}" fill="${c}"/><path d="${arrow(8, y + 8, 530, 204, 68)}" fill="url(#en-sheen)"/></g>
      <circle class="en-lamp ${mood}" cx="82" cy="${cy}" r="62" fill="${c}" filter="url(#en-glow)"/>
      <circle cx="82" cy="${cy}" r="50" fill="${cream}"/>
      <circle cx="82" cy="${cy}" r="34" fill="${c}"/><circle cx="82" cy="${cy}" r="34" fill="url(#en-sheen)"/>
      <circle cx="70" cy="${cy - 12}" r="10" fill="#fff" opacity=".7"/>
      <text x="162" y="${y + 104}" font-family="Anton, Impact, sans-serif" font-size="58" fill="${t}" letter-spacing="1">${name}</text>
      <text x="164" y="${y + 146}" font-family="Archivo Narrow, Arial Narrow, sans-serif" font-weight="600" font-size="22" fill="${t}">${line}</text>`;
  });
  // Chips in the enamel, down to the black steel with a rust rim.
  h += `<g fill="#120c06" stroke="#8a4a1c" stroke-width="4" stroke-linejoin="round">
    <path d="M500,208 l14,-10 16,6 8,-12 10,10 -6,16 -16,8 -14,-2 z"/><path d="M20,742 l12,-8 8,10 14,0 -6,14 6,14 -16,-2 -10,10 -6,-16 z"/></g>`;
  art.innerHTML = `<svg viewBox="0 -4 572 990" role="presentation">${h}</svg>`;
})();
