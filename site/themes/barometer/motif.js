// Barometer's hero art: an aneroid dial in a brass bezel. Four bands round the enamel, lettered on the arc in
// Ambient's state order, and a blued needle that swings to the demo's current state (theme.css turns it from
// data-mood on <html>, set by main.js). With reduced motion the needle simply points; nothing animates.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const ink = "#17251f";
  const P = (a, r) => [500 + r * Math.sin((a * Math.PI) / 180), 500 - r * Math.cos((a * Math.PI) / 180)];
  const f = (n) => n.toFixed(1);
  let tk = "";
  for (let a = -120; a <= 120; a += 2) {
    const big = a % 10 === 0, [x1, y1] = P(a, 410), [x2, y2] = P(a, big ? 384 : 397);
    tk += `<line x1="${f(x1)}" y1="${f(y1)}" x2="${f(x2)}" y2="${f(y2)}" stroke-width="${big ? 2.4 : 1}"/>`;
  }
  let bands = "";
  [[-120, -62, "#b8322f"], [-58, -2, "#d98a00"], [2, 58, "#2f6fb3"], [62, 120, "#2e8b57"]].forEach(([a0, a1, c]) => {
    const [x0, y0] = P(a0, 300), [x1, y1] = P(a1, 300);
    bands += `<path d="M${f(x0)} ${f(y0)} A300 300 0 0 1 ${f(x1)} ${f(y1)}" stroke="${c}"/>`;
  });
  const words = [["13.6%", "ERROR", "the turn failed"], ["38%", "NEEDS YOU", "waiting for an answer"], ["62%", "WORKING", "thinking, running tools"], ["86.4%", "DONE", "the turn finished"]];
  const outer = words.map(([o, w]) => `<text><textPath href="#bar-arcT" startOffset="${o}" text-anchor="middle">${w}</textPath></text>`).join("");
  const inner = words.map(([o, , w]) => `<text><textPath href="#bar-arcIn" startOffset="${o}" text-anchor="middle">${w}</textPath></text>`).join("");
  art.innerHTML = `
  <svg class="bar-dial" viewBox="0 0 1000 1000" role="presentation">
    <defs>
      <radialGradient id="bar-en" cx="42%" cy="36%" r="75%"><stop offset="0" stop-color="#fffdf5"/><stop offset=".8" stop-color="#f3ecd9"/><stop offset="1" stop-color="#e2d8bd"/></radialGradient>
      <linearGradient id="bar-br" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e6cf8f"/><stop offset=".35" stop-color="#a9843a"/><stop offset=".6" stop-color="#f1dea6"/><stop offset="1" stop-color="#7c5e22"/></linearGradient>
      <path id="bar-arcT" d="M223.1 693.9 A338 338 0 1 1 776.9 693.9"/>
      <path id="bar-arcIn" d="M296.9 642.2 A248 248 0 1 1 703.1 642.2"/>
    </defs>
    <circle cx="514" cy="524" r="470" fill="${ink}" opacity=".16"/>
    <circle cx="500" cy="500" r="476" fill="url(#bar-br)"/><circle cx="500" cy="500" r="446" fill="#5d4718"/><circle cx="500" cy="500" r="440" fill="url(#bar-en)"/>
    <g stroke="${ink}">${tk}</g>
    <g fill="none" stroke-width="26">${bands}</g>
    <g font-size="42" fill="${ink}" letter-spacing="5">${outer}</g>
    <g class="it" font-size="21" fill="#33473e">${inner}</g>
    <text x="500" y="640" text-anchor="middle" font-style="italic" font-size="54" fill="${ink}">ambient</text>
    <text class="mono" x="500" y="676" text-anchor="middle" font-size="13" letter-spacing="4" fill="#33473e">ANEROID · FOR MACOS 14+</text>
    <text class="mono" x="500" y="770" text-anchor="middle" font-size="15" letter-spacing="5" fill="#33473e">CLAUDE CODE · CODEX · GEMINI CLI</text>
    <g transform="rotate(61 500 500)"><line x1="500" y1="500" x2="500" y2="150" stroke="#a9843a" stroke-width="3"/><circle cx="500" cy="150" r="9" fill="none" stroke="#a9843a" stroke-width="3"/></g>
    <g class="bar-needle"><polygon points="493,560 507,560 503,206 500,180 497,206" fill="#1c2f5a"/><circle cx="500" cy="590" r="16" fill="none" stroke="#1c2f5a" stroke-width="5"/></g>
    <circle cx="500" cy="500" r="30" fill="url(#bar-br)"/><circle cx="500" cy="500" r="9" fill="${ink}"/>
  </svg>`;
})();
