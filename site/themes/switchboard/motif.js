// Switchboard's hero art: an exchange board with a designation strip for each agent, a lamp over every jack, a few
// lamps lit in the colour of what that session is doing, and patch cords. The pulsing lamp follows the demo's
// current state (--state on <html>, set by main.js).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const G = [["CLAUDE CODE", "TERMINAL · EDITORS · APP"], ["CODEX", "CLI · CODEX APP"], ["GEMINI CLI", "ANY TERMINAL"]];
  const lit = { "0-0-1": "#4fd17c", "0-1-2": "#d97757", "1-0-1": "#10a37f", "1-1-2": "#4fd17c", "2-0-4": "#ff5340", "2-1-7": "#4f8df7" };
  const live = "0-0-6";
  let s = `<rect x="6" y="6" width="588" height="628" rx="6" fill="#14100d" stroke="#1f120a" stroke-width="12"/><rect x="12" y="12" width="576" height="616" fill="none" stroke="#5d3d20" stroke-width="2"/>`;
  let y = 34, n = 1;
  G.forEach(([name, sub], g) => {
    s += `<rect x="34" y="${y}" width="532" height="26" fill="#f2e6c9"/><text x="44" y="${y + 18}" font-family="Courier Prime, monospace" font-weight="700" font-size="14" letter-spacing="1.6" fill="#1c120a">${name}</text><text x="556" y="${y + 18}" text-anchor="end" font-family="Courier Prime, monospace" font-weight="700" font-size="11" letter-spacing="1" fill="#1c120a">${sub}</text>`;
    y += 42;
    for (let r = 0; r < 2; r++) {
      for (let c = 0; c < 9; c++) {
        const x = 64 + c * 59, k = `${g}-${r}-${c}`, col = lit[k];
        if (k === live) s += `<circle class="live-glow" cx="${x}" cy="${y + 10}" r="20" style="filter:blur(6px)"/><circle class="live" cx="${x}" cy="${y + 10}" r="9" stroke="#fff" stroke-opacity=".5" stroke-width="2"/>`;
        else if (col) s += `<circle cx="${x}" cy="${y + 10}" r="16" fill="${col}" opacity=".45" style="filter:blur(6px)"/><circle cx="${x}" cy="${y + 10}" r="9" fill="${col}" stroke="#fff" stroke-opacity=".5" stroke-width="2"/>`;
        else s += `<circle cx="${x}" cy="${y + 10}" r="9" fill="#2a221c" stroke="#40342a" stroke-width="2"/>`;
        s += `<circle cx="${x}" cy="${y + 40}" r="16" fill="#6b5226"/><circle cx="${x}" cy="${y + 40}" r="13" fill="#c39447"/><circle cx="${x}" cy="${y + 40}" r="8" fill="#000"/>`;
        s += `<text x="${x}" y="${y + 66}" text-anchor="middle" font-family="Courier Prime, monospace" font-size="10" fill="#8d7b5c">${String(n++).padStart(2, "0")}</text>`;
      }
      y += 74;
    }
    y += 10;
  });
  // Patch cords from two lit jacks, down and out of the board.
  const cord = (x1, y1, x2, c) => `<path d="M${x1} ${y1} C${x1 - 10} ${y1 + 140} ${x2 + 40} 560 ${x2} 640" fill="none" stroke="${c}" stroke-width="8" stroke-linecap="round"/><path d="M${x1} ${y1} C${x1 - 10} ${y1 + 140} ${x2 + 40} 560 ${x2} 640" fill="none" stroke="#fff" stroke-opacity=".2" stroke-width="2"/><rect x="${x1 - 9}" y="${y1 - 16}" width="18" height="30" rx="5" fill="#c39447"/>`;
  s += cord(418, 116, 330, "#b23a2e") + cord(182, 316, 240, "#3d6b52");
  art.innerHTML = `<svg class="swb-board" viewBox="0 0 600 640" role="presentation">${s}</svg>`;
})();
