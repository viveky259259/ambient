// Periodic table's hero art: a block of the chart. The three agents and "Free" across the top, the four states
// as heavy elements below, ordered by urgency, and a row of where Ambient shows. The element for the demo's
// current state (data-mood on <html>, set by main.js) gets a heavy outline. Static, so reduced motion is a still.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const ink = "#111";
  const U = 100;
  const cell = (x, y, w, h, fill, txt, z, tag, sym, name, sub, big, cls = "") => {
    const S = big ? 2 : 1;
    return `<g class="${cls}"><rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}" stroke="${ink}" stroke-width="1.5"/>
      <rect class="hi" x="${x + 5}" y="${y + 5}" width="${w - 10}" height="${h - 10}" fill="none" stroke="${ink}" stroke-width="5"/>
      <text x="${x + 9 * S}" y="${y + 16 * S}" font-size="${10 * S}" font-weight="600" fill="${txt}">${z}</text>
      <text x="${x + w - 9 * S}" y="${y + 16 * S}" font-size="${7.5 * S}" text-anchor="end" letter-spacing=".6" fill="${txt}" opacity=".8">${tag}</text>
      <text class="sym" x="${x + 9 * S}" y="${y + (big ? 118 : 60)}" font-size="${big ? 96 : 40}" letter-spacing="-2" fill="${txt}">${sym}</text>
      <text x="${x + 9 * S}" y="${y + h - (big ? 26 : 22)}" font-size="${big ? 19 : 10.5}" font-weight="600" fill="${txt}">${name}</text>
      <text x="${x + 9 * S}" y="${y + h - (big ? 10 : 10)}" font-size="${big ? 10.5 : 7.5}" fill="${txt}" opacity=".85">${sub}</text></g>`;
  };
  let s = "";
  [["A1", "agent", "Cc", "Claude Code", "terminal · editors · app", "#e3e1d6", ink],
   ["A2", "agent", "Cx", "Codex", "the CLI and the app", "#e3e1d6", ink],
   ["A3", "agent", "Gm", "Gemini CLI", "any terminal", "#e3e1d6", ink],
   ["00", "free", "Fr", "Free", "every feature", ink, "#f6f5ef"]]
    .forEach(([z, tag, sym, name, sub, f, t], i) => (s += cell(i * U, 0, U, U, f, t, z, tag, sym, name, sub)));
  [["pt-ny", "1", "most urgent", "Ny", "Needs you", "waiting for an answer", "#ffb400"],
   ["pt-er", "2", "then", "Er", "Error", "the turn failed", "#e8382c"],
   ["pt-dn", "3", "then", "Dn", "Done", "the turn finished", "#1faa5c"],
   ["pt-wk", "4", "then", "Wk", "Working", "thinking, running tools", "#5b74ff"]]
    .forEach(([cls, z, tag, sym, name, sub, f], i) => (s += cell((i % 2) * 2 * U, U + Math.floor(i / 2) * 2 * U, 2 * U, 2 * U, f, ink, z, tag, sym, name, sub, true, cls)));
  [["5", "No", "Notch island"], ["6", "Nf", "Notifications"], ["7", "Dk", "Dock glow"], ["8", "Wp", "Wallpaper"]]
    .forEach(([z, sym, name], i) => (s += cell(i * U, 5 * U, U, U, "#dfe7f2", ink, z, "shows", sym, name, "")));
  const key = [["#e3e1d6", "AGENTS"], ["#ffb400", "STATES"], ["#dfe7f2", "SHOWS"]]
    .map(([c, t], i) => `<rect x="${i * 120 + 1}" y="618" width="12" height="12" fill="${c}" stroke="${ink}" stroke-width="1.2"/><text x="${i * 120 + 20}" y="628" font-size="10.5" letter-spacing="1" fill="${ink}">${t}</text>`).join("");
  art.innerHTML = `<svg class="pt-table" viewBox="-2 -2 404 636" role="presentation">${s}${key}</svg>`;
})();
