// Till receipt's hero art: a printed till receipt that itemises four sessions by state. Its "most urgent" line
// follows the demo's state (data-mood and --state on <html>, set by main.js).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const W = 460, H = 800, L = 34, R = W - 34;
  let y = 0, s = "";
  const t = (x, yy, str, cls = "", anchor = "start") => `<text x="${x}" y="${yy}" class="${cls}" text-anchor="${anchor}">${str}</text>`;
  const row = (a, b, cls = "") => { y += 24; s += t(L, y, a, cls) + t(R, y, b, cls, "end"); };
  const hr = () => { y += 16; s += `<line x1="${L}" x2="${R}" y1="${y}" y2="${y}" stroke="#1a1a1a" stroke-width="2" stroke-dasharray="7 5"/>`; y += 4; };
  y = 96; s += t(W / 2, y, "AMBIENT", "h", "middle");
  y += 26; s += t(W / 2, y, "yaml.cafe", "", "middle");
  y += 22; s += t(W / 2, y, "YOUR MAC, AWARE OF YOUR AGENTS", "", "middle");
  hr(); row("SESSION", "STATE", "b");
  const items = [
    ["api-server", "Claude Code · terminal tab", "WORKING", "tw", ""],
    ["checkout", "Codex · the exact thread", "NEEDS YOU", "tn", " dk"],
    ["docs-site", "Gemini CLI · tmux pane", "DONE", "td", ""],
    ["migrations", "Claude Code · the exact chat", "ERROR", "te", ""],
  ];
  for (const [name, where, tag, c, dk] of items) {
    y += 30; s += t(L, y, name);
    const w = tag.length * 8.6 + 14;
    s += `<rect class="${c}" x="${R - w}" y="${y - 15}" width="${w}" height="21"/>` + t(R - 7, y, tag, "tl" + dk, "end");
    y += 17; s += t(L, y, where, "s");
  }
  hr(); row("SESSIONS", "4");
  y += 28;
  s += t(L, y, "MOST URGENT", "b") + `<rect class="now" x="${R - 128}" y="${y - 17}" width="128" height="24"/>` + `<text x="${R - 8}" y="${y}" class="tl" text-anchor="end" id="rcp-now">NEEDS YOU</text>`;
  hr(); row("ACCOUNT", "NONE"); row("TELEMETRY", "NONE"); row("HOOK TIME", "ABOUT 15 MS"); row("LICENSE", "MIT");
  hr(); y += 10; s += t(L, y + 14, "TOTAL", "big") + t(R, y + 14, "FREE", "big", "end"); y += 24;
  hr();
  y += 22; s += t(W / 2, y, "ONE CLICK BACK TO THE EXACT", "", "middle");
  y += 20; s += t(W / 2, y, "PLACE THE AGENT RUNS", "", "middle");
  let bars = "", x = 92, k = 7;
  while (x < W - 92) { k = (k * 73 + 11) % 97; const w = 1 + (k % 4); bars += `<rect x="${x}" y="${y + 16}" width="${w}" height="52" fill="#1a1a1a"/>`; x += w + 1 + ((k >> 2) % 4); }
  s += bars; y += 88; s += t(W / 2, y, "AMBIENT OPEN", "s sp", "middle");
  // Paper with a torn zigzag top and bottom.
  let top = "", bot = "";
  for (let i = 0; i <= 23; i++) { const px = (i * W) / 23; top += `${px.toFixed(1)},${i % 2 ? 10 : 0} `; bot = `${px.toFixed(1)},${i % 2 ? H - 10 : H} ` + bot; }
  art.innerHTML = `<svg class="rcp" viewBox="0 0 ${W} ${H}" role="presentation"><polygon points="${top}${bot}" fill="#fbfaf4"/>${s}</svg>`;
  const label = { working: "WORKING", waiting: "NEEDS YOU", done: "DONE", error: "ERROR" };
  const now = document.getElementById("rcp-now");
  const sync = () => {
    const m = document.documentElement.dataset.mood || "waiting";
    now.textContent = label[m] || "WORKING";
    now.setAttribute("class", m === "waiting" ? "tl dk" : "tl");
  };
  sync();
  new MutationObserver(sync).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
