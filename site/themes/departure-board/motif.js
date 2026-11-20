// Departure board's hero art: agent sessions as rows of split-flap characters, most urgent first. The flaps spin
// into place on load; the top row's status follows the demo (data-mood on <html>) and flips when it changes.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const W = [5, 11, 12, 12, 9];
  const ST = { working: ["WORKING", ""], waiting: ["NEEDS YOU", "var(--waiting)"], done: ["DONE", "var(--done)"], error: ["ERROR", "var(--error)"] };
  const rows = [
    ["14:22", "CLAUDE CODE", "API-SERVER", "TMUX PANE %3", "waiting"],
    ["14:19", "CODEX", "WEB-CHECKOUT", "CODEX APP", "working"],
    ["14:17", "GEMINI CLI", "DOCS", "ITERM2 TAB 4", "done"],
    ["14:11", "CLAUDE CODE", "BILLING", "CLAUDE APP", "error"],
    ["14:08", "CLAUDE CODE", "STUDIO.LOCAL", "OVER SSH", "working"],
    ["14:02", "CODEX", "INFRA", "VS CODE", "done"],
  ];
  const tiles = (n) => "<span></span>".repeat(n);
  art.innerHTML = `<div class="db-board">
    <div class="db-hd"><span>Time</span><span>Agent</span><span>Project</span><span>Where</span><span>Status</span></div>
    ${rows.map(() => `<div class="db-row">${W.map((w, i) => `<div class="db-col${i === 4 ? " st" : ""}">${tiles(w)}</div>`).join("")}</div>`).join("")}
  </div>`;
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const CH = "ABCDEFGHIJKLMNOPRSTUVWXYZ0123456789:%";
  // Write text into a column, flipping each tile through a few random characters first.
  const put = (col, text, colour) => {
    if (colour !== undefined) col.style.setProperty("--c", colour || "#f6f3ea");
    [...col.children].forEach((t, i) => {
      const c = text[i] || " ";
      if (still || t.textContent === c) { t.textContent = c; return; }
      let n = 3 + ((i * 7) % 6);
      const spin = setInterval(() => {
        t.textContent = --n > 0 ? CH[(Math.random() * CH.length) | 0] : c;
        if (n <= 0) clearInterval(spin);
      }, 70);
    });
  };
  const rowEls = art.querySelectorAll(".db-row");
  rows.forEach((r, ri) => {
    const cols = rowEls[ri].children;
    for (let i = 0; i < 4; i++) put(cols[i], r[i]);
    put(cols[4], ST[r[4]][0], ST[r[4]][1]);
  });
  const top = rowEls[0].children[4];
  new MutationObserver(() => {
    const s = ST[document.documentElement.dataset.mood];
    if (s) put(top, s[0].padEnd(9), s[1]);
  }).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
