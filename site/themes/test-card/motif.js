// Test card's hero art: a generic test pattern. A black circle on the grid holds a grey step wedge, the name, and
// four colour bars, one per state; a marker sits over the bar of the demo's current state (data-mood on <html>).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const greys = ["#000", "#2a2a2a", "#555", "#808080", "#aaa", "#d5d5d5", "#fff", "#d5d5d5", "#aaa", "#808080", "#555", "#2a2a2a", "#000"];
  const wedge = (y, h, rev) => greys.map((g, i) => `<rect x="${i * 1000 / 13}" y="${y}" width="${1000 / 13 + 0.5}" height="${h}" fill="${rev ? greys[(i + 6) % 13] : g}"/>`).join("");
  const B = [["working", "WORKING", "--claude"], ["waiting", "NEEDS YOU", "--waiting"], ["done", "DONE", "--done"], ["error", "ERROR", "--error"]];
  const bx = 100, bw = 200;
  let bars = "";
  B.forEach(([, name, c], i) => {
    const x = bx + i * bw;
    bars += `<rect x="${x}" y="560" width="${bw}" height="230" style="fill:var(${c})"/>` +
      `<text class="bl" x="${x + 18}" y="596" fill="#0a0a0b" font-size="14">BAR ${i + 1}</text>` +
      `<text class="bn" x="${x + 18}" y="${name.length > 6 ? 640 : 640}" fill="#0a0a0b" font-size="19">${name}</text>`;
  });
  art.innerHTML = `<svg class="tcd" viewBox="0 0 1000 1000" role="presentation">
    <defs><clipPath id="tcd-c"><circle cx="500" cy="500" r="472"/></clipPath></defs>
    <circle cx="500" cy="500" r="486" fill="#0a0a0b"/><circle cx="500" cy="500" r="479" fill="none" stroke="#f4f4f1" stroke-width="8"/>
    <g clip-path="url(#tcd-c)">
      <rect width="1000" height="1000" fill="#0a0a0b"/>
      ${wedge(250, 70)}
      <text x="500" y="200" text-anchor="middle" class="bl" fill="#f4f4f1" font-size="20" letter-spacing="5">FREE · NATIVE macOS · OPEN SOURCE</text>
      <text x="500" y="470" text-anchor="middle" fill="#f4f4f1" font-size="104" font-weight="900" letter-spacing="-4">ambient</text>
      <rect x="0" y="560" width="${bx}" height="230" style="fill:var(--claude)"/><rect x="${bx + 4 * bw}" y="560" width="${bx}" height="230" style="fill:var(--error)"/>
      ${bars}
      ${wedge(790, 46, true)}
      <text x="500" y="900" text-anchor="middle" class="bl" fill="#f4f4f1" font-size="20" letter-spacing="5">ONE COLOUR AT THE NOTCH</text>
    </g>
    <path class="mk" d="M-22 0h44l-22 30z" fill="#f4f4f1" stroke="#0a0a0b" stroke-width="4" transform="translate(200 528)"/>
  </svg>`;
  const mk = art.querySelector(".mk");
  const idx = { working: 0, waiting: 1, done: 2, error: 3 };
  const sync = () => {
    const i = idx[document.documentElement.dataset.mood] ?? 0;
    mk.style.transform = `translate(${bx + i * bw + bw / 2}px, 524px)`;
  };
  mk.removeAttribute("transform");
  sync();
  new MutationObserver(sync).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
