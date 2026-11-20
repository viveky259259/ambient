// Punch cards' hero art: a deck of four manila cards, one per state, each punched with its own name in the
// card code. The card for the demo's current state (data-mood on <html>, set by main.js) slides out of the deck.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const C = [
    ["working", "Working", "--claude", "An orb in the agent's colour breathes.", "WORKING THE AGENT IS THINKING"],
    ["waiting", "Needs you", "--waiting", "An amber pulse.", "NEEDS YOU WAITING FOR AN ANSWER"],
    ["done", "Done", "--done", "Green, until you look at the session.", "DONE THE TURN FINISHED"],
    ["error", "Error", "--error", "Red, with the reason one hover away.", "ERROR THE TURN FAILED"],
  ];
  // Card code: a digit punches its own row; a letter punches a zone row (12, 11, 0) and a digit row.
  const rows = (ch) => {
    const c = ch.charCodeAt(0);
    if (ch >= "0" && ch <= "9") return [+ch + 2];
    if (ch >= "A" && ch <= "I") return [0, c - 62];
    if (ch >= "J" && ch <= "R") return [1, c - 71];
    if (ch >= "S" && ch <= "Z") return [2, c - 79];
    return [];
  };
  const W = 600, H = 172, cols = 40, px = 13.5, x0 = 30, py = 8.3, y0 = 70;
  let digits = "";
  for (let r = 0; r < 10; r++) digits += `<text x="3.4" y="${y0 + (r + 2) * py + 3}" class="dg" text-anchor="middle">${r}</text>`;
  const defs = `<defs><pattern id="pc-col" width="${px}" height="${H}" patternUnits="userSpaceOnUse" x="${x0 - 0.2}">${digits}</pattern></defs>`;
  let deck = "";
  C.forEach(([mood, name, c, desc, code], i) => {
    let holes = "";
    [...code.padEnd(cols)].slice(0, cols).forEach((ch, k) => rows(ch).forEach((r) => {
      holes += `<rect x="${(x0 + k * px).toFixed(1)}" y="${(y0 + r * py - 3.5).toFixed(1)}" width="7" height="7" fill="#0b3037"/>`;
    }));
    const rot = [-0.8, 0.6, -0.5, 0.9][i];
    deck += `<g class="crd" data-m="${mood}" style="--c:var(${c})"><g class="face" transform="translate(30 ${12 + i * 180}) rotate(${rot} ${W / 2} ${H / 2})">
      <path d="M26 0H${W}V${H}H0V26Z" fill="#ecdcb0"/>
      <path d="M26 0H${W}V12H14Z" style="fill:var(--c)"/>
      <rect x="${x0 - 4}" y="${y0 - 6}" width="${cols * px}" height="${12 * py + 4}" fill="url(#pc-col)"/>
      ${holes}
      <text class="nm" x="30" y="56" style="fill:color-mix(in srgb, var(--c) 62%, #10242a)">${name}</text>
      <text class="ds" x="${W - 22}" y="50" text-anchor="end">${desc}</text>
    </g></g>`;
  });
  art.innerHTML = `<svg class="pc" viewBox="0 0 640 730" role="presentation">${defs}${deck}</svg>`;
  const sync = () => {
    const m = document.documentElement.dataset.mood || "working";
    art.querySelectorAll(".crd").forEach((g) => g.classList.toggle("on", g.dataset.m === m));
  };
  sync();
  new MutationObserver(sync).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
