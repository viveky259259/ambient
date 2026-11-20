// Session score's hero art: four agent sessions as lanes on a timeline. Hatched bars are working, amber is needs
// you, green done, red error; the "now" line carries a small notch whose orb shows the demo's state (--state).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  // [left %, width %, kind, colour, label] on a lane that runs to "now" at 72%.
  const lanes = [
    ["Claude Code", "api-server · tmux %3", [[0, 33, "w", "--claude"], [33.8, 6, "q", 0, "permission"], [40.6, 24, "w", "--claude"], [65.4, 6.4, "q last", 0, "needs you"]]],
    ["Codex", "web-checkout · Codex app", [[9, 40, "w", "--codex"], [49.8, 2.6, "d", 0, "done"], [56, 15.8, "w", "--codex"]]],
    ["Gemini CLI", "docs · iTerm2 tab 4", [[20, 18, "w", "--gemini"], [38.8, 2.6, "e", 0, "error"], [45, 15, "w", "--gemini"], [60.8, 2.6, "d", 0, "done"]]],
    ["Claude Code", "studio.local · over ssh", [[30, 41.8, "w", "--claude"]]],
  ];
  const times = ["14:02", "14:06", "14:10", "14:14", "14:18", "14:22", "Now", "", ""];
  const row = ([who, where, segs]) => `<div class="ss-tr"><div class="ss-who"><b>${who}</b><span>${where}</span></div><div class="ss-lane">${segs
    .map(([l, w, k, c, t]) => `<i class="${k}" style="left:${l}%;width:${w}%;${c ? `--c:var(${c})` : ""}">${t ? `<em>${t}</em>` : ""}</i>`).join("")}</div></div>`;
  art.innerHTML = `<div class="ss-score">
    <div class="ss-axis"><span></span><div>${times.map((t) => `<span>${t || "—"}</span>`).join("")}</div></div>
    ${lanes.map(row).join("")}
    <div class="ss-now"></div>
    <div class="ss-leg"><span><u style="background:repeating-linear-gradient(115deg,#6b6655 0 3px,transparent 3px 8px);border:1.5px solid #6b6655"></u>Working</span><span><u style="background:var(--waiting)"></u>Needs you</span><span><u style="background:var(--done)"></u>Done</span><span><u style="background:var(--error)"></u>Error</span></div>
  </div>`;
})();
