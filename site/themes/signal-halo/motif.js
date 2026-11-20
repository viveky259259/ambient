// Signal halo's hero art: rings of the hook events Ambient hears, curving out from the notch. The words for the
// four states are coloured; the current state's (data-mood on <html>, set by main.js) is set in bold by theme.css.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const ev = ["claude · PreToolUse · Bash", "codex · Stop", "gemini · Notification", "ambient hook claude", "session api-server",
    "PostToolUse · Edit", "needs you", "~/.ambient/ambient.sock", "done", "working", "tmux pane %3", "codex · PermissionRequest",
    "iTerm2 tab 4", "state=waiting", "15 ms", "claude · Stop", "error", "ambient open"];
  const cls = { "needs you": "q", done: "d", error: "e", working: "w" };
  let s = "", k = 0;
  for (let r = 150, i = 0; r < 1150; r += 44, i++) {
    const o = Math.max(0.16, 0.62 - i * 0.022).toFixed(2);
    s += `<path id="sh${i}" d="M ${720 - r} 4 A ${r} ${r} 0 0 0 ${720 + r} 4" fill="none"/>` +
      `<text font-size="${(12 + i * 0.35).toFixed(1)}" opacity="${o}"><textPath href="#sh${i}" startOffset="${(i * 37) % 60}">`;
    let len = 0;
    while (len < r * 3.3) {
      const w = ev[(k++ * 7 + i * 3) % ev.length];
      s += cls[w] ? `<tspan class="${cls[w]}">${w}</tspan>  ` : `${w}   `;
      len += (w.length + 5) * 8;
    }
    s += "</textPath></text>";
  }
  art.innerHTML = `<svg class="sh-halo" viewBox="0 0 1440 1150" role="presentation">${s}</svg>` +
    `<div class="sh-notch"><i></i><b></b></div>`;
})();
