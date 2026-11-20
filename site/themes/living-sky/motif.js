// Living sky's hero art: the sun setting into a harbour, and two boats whose sails and wakes glow in their
// session's state. The left boat follows the demo (--state and data-mood on <html>); the right is Codex, working.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const word = { working: "working", waiting: "needs you", done: "done", error: "error" };
  let glints = "";
  for (let i = 0; i < 9; i++) {
    const y = 140 + i * 24, w = 150 - i * 12 + (i % 2) * 30;
    glints += `<rect x="${720 - w / 2}" y="${y}" width="${w}" height="${3 + i * 0.4}" rx="2" fill="#ffe3b8" opacity="${(0.55 - i * 0.05).toFixed(2)}"/>`;
  }
  let lines = "";
  for (let y = 150; y < 380; y += 18) lines += `<line x1="0" y1="${y}" x2="1440" y2="${y}" stroke="#ffffff" stroke-opacity="0.05"/>`;
  const boat = (x, cls, sail, wake, id) => `
    <rect x="${x - 7}" y="214" width="14" height="150" fill="url(#${wake})" opacity="0.8" filter="url(#lsb)"/>
    <g class="ls-boat ${cls}">
      <path d="M${x} 130 L${x} 204 L${x + 40} 204 Z" class="${sail}"/>
      <path d="M${x - 4} 140 L${x - 4} 204 L${x - 30} 204 Z" class="${sail}" opacity="0.75"/>
      <path d="M${x - 36} 208 H${x + 46} Q${x + 36} 222 ${x + 22} 222 H${x - 22} Q${x - 30} 222 ${x - 36} 208 Z" fill="#0d1226"/>
    </g>
    <text class="ls-lab" x="${x + 4}" y="116" text-anchor="middle" ${id ? `id="${id}"` : ""}></text>`;
  art.innerHTML = `<svg class="ls-sea" viewBox="0 0 1440 380" preserveAspectRatio="xMidYMax slice" role="presentation">
    <defs>
      <linearGradient id="lsh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f8d9a8" stop-opacity="0"/><stop offset="1" stop-color="#f8d9a8"/></linearGradient>
      <linearGradient id="lsw" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a3156"/><stop offset="1" stop-color="#19203f"/></linearGradient>
      <linearGradient id="lsa" x1="0" y1="0" x2="0" y2="1"><stop offset="0" class="ls-state-stop"/><stop offset="1" class="ls-state-stop" stop-opacity="0"/></linearGradient>
      <linearGradient id="lsc" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#10a37f"/><stop offset="1" stop-color="#10a37f" stop-opacity="0"/></linearGradient>
      <filter id="lsb"><feGaussianBlur stdDeviation="5"/></filter>
      <clipPath id="lsk"><rect width="1440" height="140"/></clipPath>
    </defs>
    <rect y="40" width="1440" height="100" fill="url(#lsh)"/>
    <circle class="ls-sun" cx="720" cy="150" r="104" clip-path="url(#lsk)"/>
    <rect y="140" width="1440" height="240" fill="url(#lsw)"/>
    <rect y="139" width="1440" height="2" fill="#ffe3b8" opacity="0.5"/>
    ${lines}${glints}
    ${boat(470, "b1", "ls-state", "lsa", "ls-a")}
    ${boat(970, "b2", "ls-codex", "lsc", "")}
  </svg>`;
  art.querySelector(".b2 path").setAttribute("fill", "#5fd3b0");
  art.querySelectorAll(".b2 path")[1].setAttribute("fill", "#5fd3b0");
  art.querySelectorAll(".ls-lab")[1].textContent = "Codex · working";
  const a = document.getElementById("ls-a");
  const set = () => { a.textContent = "Claude · " + (word[document.documentElement.dataset.mood] || "working"); };
  set();
  new MutationObserver(set).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
