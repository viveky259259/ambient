// Prism's hero art: an optical bench on paper. Three agents' beams (in their own colours) pass a lens, meet at a
// slit, and a glass block splits them into Ambient's four state colours on a screen. The band for the demo's
// current state (data-mood on <html>, set by main.js) is lit; the others dim. Static, so reduced motion is a still.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const ink = "#111216";
  const css = getComputedStyle(document.documentElement);
  const v = (n, f) => css.getPropertyValue(n).trim() || f;
  const agents = [["CLAUDE CODE", v("--claude", "#d1653f"), 150], ["CODEX", v("--codex", "#0e8f6f"), 235], ["GEMINI CLI", v("--gemini", "#3f78e6"), 320]];
  const bands = [["ERROR", "#dd3344", "#b3202f", 100], ["NEEDS YOU", "#e59a12", "#8f5a00", 185], ["DONE", "#23a35d", "#14733f", 270], ["WORKING", "#5b63e6", "#3a41b8", 355]];
  const fx = 530, fy = 235; // focus at the slit
  let s = `<defs><linearGradient id="prm-glass" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#cfd8e6" stop-opacity=".75"/><stop offset=".5" stop-color="#eef2f7" stop-opacity=".35"/><stop offset="1" stop-color="#b9c4d6" stop-opacity=".7"/></linearGradient></defs>`;
  // bench rail and millimetre ticks
  s += `<rect x="30" y="408" width="1140" height="9" fill="${ink}"/>`;
  let t = "";
  for (let x = 30, i = 0; x <= 1170; x += 12, i++) t += `<line x1="${x}" y1="417" x2="${x}" y2="${i % 5 ? 423 : 430}"/>`;
  s += `<g stroke="${ink}" stroke-width="1">${t}</g>`;
  // carriers and posts
  const post = (x, top) => `<line x1="${x}" y1="${top}" x2="${x}" y2="398" stroke="${ink}" stroke-width="3"/><rect x="${x - 22}" y="396" width="44" height="12" fill="${ink}"/>`;
  // incoming beams, then converging to the slit
  agents.forEach(([name, c, y], i) => {
    s += `<line x1="40" y1="${y}" x2="330" y2="${y}" stroke="${c}" stroke-width="5"/>`;
    s += `<line x1="330" y1="${y}" x2="${fx}" y2="${fy}" stroke="${c}" stroke-width="3.5" opacity=".9"/>`;
    s += `<text class="prm-small" x="40" y="${y - 14}" font-size="15" letter-spacing="2" fill="${ink}">${name}</text>`;
    s += `<polygon points="300,${y - 7} 314,${y} 300,${y + 7}" fill="${c}"/>`;
  });
  // the lens
  s += post(330, 345) + `<path d="M330 118 Q372 235 330 352 Q288 235 330 118Z" fill="url(#prm-glass)" stroke="${ink}" stroke-width="1.6"/><line x1="330" y1="118" x2="330" y2="352" stroke="${ink}" stroke-opacity=".25" stroke-dasharray="3 5"/>`;
  s += `<text class="prm-small" x="330" y="102" text-anchor="middle" font-size="13" letter-spacing="1.5" fill="#474955">LENS · f 200</text>`;
  // the combined beam from slit to block
  s += `<line x1="${fx}" y1="${fy}" x2="660" y2="${fy}" stroke="${ink}" stroke-width="5"/>`;
  // the slit
  s += post(fx, 360) + `<rect x="${fx - 6}" y="110" width="12" height="${fy - 4 - 110}" fill="${ink}"/><rect x="${fx - 6}" y="${fy + 4}" width="12" height="${360 - fy - 4}" fill="${ink}"/>`;
  s += `<text class="prm-small" x="${fx}" y="96" text-anchor="middle" font-size="13" letter-spacing="1.5" fill="#474955">SLIT · THE NOTCH</text>`;
  // dispersed bands to the screen
  bands.forEach(([n, c, dk, y], i) => {
    const y0 = fy - 9 + i * 6;
    s += `<polygon class="prm-band prm-b${i}" points="760,${y0} 760,${y0 + 5} 1040,${y + 26} 1040,${y - 26}" fill="${c}"/>`;
    s += `<text class="prm-small" x="1068" y="${y - 6}" font-size="12" letter-spacing="1.6" fill="#474955">λ 0${i + 1}</text><text x="1068" y="${y + 16}" font-size="19" font-weight="500" letter-spacing="1.2" fill="${dk}">${n}</text>`;
  });
  // the glass block (a rectangle, slightly turned), drawn over the start of the fan
  s += post(710, 300) + `<g transform="rotate(-14 710 235)"><rect x="652" y="180" width="116" height="110" fill="url(#prm-glass)" stroke="${ink}" stroke-width="1.6"/><line x1="664" y1="192" x2="756" y2="192" stroke="#fff" stroke-width="3" opacity=".8"/></g>`;
  s += `<text class="prm-small" x="710" y="148" text-anchor="middle" font-size="13" letter-spacing="1.5" fill="#474955">GLASS BLOCK</text>`;
  // the screen
  s += post(1046, 392) + `<rect x="1040" y="62" width="12" height="330" fill="${ink}"/>`;
  s += `<text class="prm-small" x="30" y="458" font-size="13" letter-spacing="1.6" fill="#474955">FIG. 01 — AGENT HOOKS IN, ONE COLOUR OUT. EACH HOOK FINISHES IN ABOUT 15 MS.</text>`;
  art.innerHTML = `<svg class="prm-bench" viewBox="0 0 1200 470" role="presentation">${s}</svg>`;
})();
