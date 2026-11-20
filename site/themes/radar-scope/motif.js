// Radar scope's hero art: range rings, a turning sweep and agent sessions as tagged blips in their state's colour.
// The first track follows the demo (--state and data-mood on <html>); the sweep stands still under reduced motion.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const word = { working: "WORKING", waiting: "NEEDS YOU", done: "DONE", error: "ERROR" };
  // [x, y, colour, line 1, line 2, line 3] in a 600 × 600 scope.
  const tracks = [
    [380, 190, "", "CLD01 · API-SERVER", "TMUX %3 · 00:42", ""],
    [190, 300, "var(--codex)", "CDX02 · WEB-CHECKOUT", "CODEX APP", "WORKING"],
    [350, 420, "var(--done)", "GEM03 · DOCS", "ITERM2 TAB 4", "DONE"],
    [150, 160, "var(--error)", "CLD04 · BILLING", "CLAUDE APP", "ERROR"],
    [250, 500, "var(--claude)", "CLD05 · STUDIO", "OVER SSH", "WORKING"],
  ];
  let rings = "";
  for (let r = 60; r < 300; r += 60) rings += `<circle cx="300" cy="300" r="${r}" fill="none" stroke="#2f7f8a" stroke-opacity=".5"/>`;
  const blip = ([x, y, c, a, b, s], i) => {
    const f = i === 0 ? 'class="rs-cur"' : `fill="${c}"`;
    const t = i === 0 ? 'class="rs-cur"' : `fill="${c}"`;
    return `<g class="rs-blip" style="animation-delay:${(-((Math.atan2(y - 300, x - 300) / Math.PI + 1) * 3)).toFixed(2)}s">
      <circle cx="${x}" cy="${y}" r="7" ${f} style="filter:drop-shadow(0 0 6px ${c || "var(--state, var(--waiting))"})"/>
      <line x1="${x + 18}" y1="${y - 26}" x2="${x + 18}" y2="${y + 18}" stroke-width="1.5" ${t.replace("fill", "stroke").replace('class="rs-cur"', 'style="stroke:var(--state, var(--waiting))"')}/>
      <text x="${x + 26}" y="${y - 14}" ${t}>${a}</text><text x="${x + 26}" y="${y + 2}" ${t}>${b}</text>
      <text x="${x + 26}" y="${y + 18}" ${t} ${i === 0 ? 'id="rs-s"' : ""}>${s}</text></g>`;
  };
  art.innerHTML = `<div class="rs-scope"><div class="rs-sweep"></div>
    <svg viewBox="0 0 600 600" role="presentation">${rings}
      <line x1="300" y1="0" x2="300" y2="600" stroke="#2f7f8a" stroke-opacity=".45"/><line x1="0" y1="300" x2="600" y2="300" stroke="#2f7f8a" stroke-opacity=".45"/>
      ${tracks.map(blip).join("")}</svg></div>`;
  const s = document.getElementById("rs-s");
  const set = () => { s.textContent = word[document.documentElement.dataset.mood] || "WORKING"; };
  set();
  new MutationObserver(set).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
