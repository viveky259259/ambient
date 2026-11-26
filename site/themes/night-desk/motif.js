// Night desk's hero art: the notch's island, opened, with three sessions and a legend of the four states.
// The top row follows the demo's current state (--state and data-mood on <html>, via theme.css).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const leg = [["01", "Working", "var(--claude)"], ["02", "Needs you", "var(--waiting)"], ["03", "Done", "var(--done)"], ["04", "Error", "var(--error)"]];
  art.innerHTML = `<div class="nd-art">
    <div class="nd-island">
      <div class="nd-row on"><i></i><b>Claude Code</b><em>api-server</em><span></span></div>
      <div class="nd-row"><i style="background:var(--codex)"></i><b>Codex</b><em>web-checkout</em><span>WORKING</span></div>
      <div class="nd-row"><i style="background:var(--done)"></i><b>Gemini CLI</b><em>docs</em><span>DONE</span></div>
    </div>
    <div class="nd-legend">${leg.map(([n, t, c]) => `<div><small>${n}</small><h4><i style="background:${c}"></i>${t}</h4></div>`).join("")}</div>
  </div>`;
})();
