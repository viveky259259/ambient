// Road signs' hero art: the four states as roadside signs on posts, above a strip of verge and road. The sign for
// the demo's current state (data-mood on <html>, set by main.js) blinks like a warning lamp. Two arrangements:
// a row for wide screens and a 2 x 2 grid for phones (theme.css shows one).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const K = "#12161c";
  const face = {
    working: `<circle cx="100" cy="100" r="96" style="fill:var(--claude)" stroke="#fff" stroke-width="7"/><circle cx="100" cy="100" r="99" fill="none" stroke="${K}" stroke-width="2"/><circle cx="100" cy="100" r="54" fill="none" stroke="#fff" stroke-width="8" stroke-dasharray="20 14"/><circle cx="100" cy="100" r="30" fill="#fff"/>`,
    waiting: `<rect x="30" y="30" width="140" height="140" rx="14" transform="rotate(45 100 100)" style="fill:var(--waiting)" stroke="${K}" stroke-width="7"/><rect x="92" y="52" width="16" height="64" fill="${K}"/><rect x="92" y="130" width="16" height="16" fill="${K}"/>`,
    done: `<rect x="6" y="26" width="188" height="150" rx="16" style="fill:var(--done)" stroke="#fff" stroke-width="7"/><rect x="3" y="23" width="194" height="156" rx="18" fill="none" stroke="${K}" stroke-width="2"/><path d="M52 102l34 34 64-70" fill="none" stroke="#fff" stroke-width="18"/>`,
    error: `<polygon points="62,6 138,6 194,62 194,138 138,194 62,194 6,138 6,62" style="fill:var(--error)" stroke="#fff" stroke-width="8"/><polygon points="61,3 139,3 197,61 197,139 139,197 61,197 3,139 3,61" fill="none" stroke="${K}" stroke-width="2"/><path d="M66 66l68 68M134 66l-68 68" stroke="#fff" stroke-width="18"/>`,
  };
  const S = [
    ["working", "Working", "The orb breathes.", "#a9472a"],
    ["waiting", "Needs you", "An amber pulse.", "#9a5d00"],
    ["done", "Done", "Green until you look.", "#0e7a47"],
    ["error", "Error", "Red, with the reason.", "#c41d23"],
  ];
  const post = (cx, top, bottom) => `<rect x="${cx - 7}" y="${top}" width="14" height="${bottom - top}" fill="url(#rds-pole)"/>`;
  const plate = (cx, y, w, [, name, sub, col]) =>
    `<rect x="${cx - w / 2}" y="${y}" width="${w}" height="92" rx="12" fill="#fff" stroke="${K}" stroke-width="4"/>` +
    `<text class="pl" x="${cx - w / 2 + 18}" y="${y + 40}" fill="${col}">${name}</text><text class="ps" x="${cx - w / 2 + 18}" y="${y + 70}">${sub}</text>`;
  const sign = (mood, cx, cy, size) => `<g class="sg" data-m="${mood}" transform="translate(${cx - size / 2} ${cy - size / 2}) scale(${size / 200})">${face[mood]}</g>`;
  const ground = (w, y) => `<rect x="0" y="${y}" width="${w}" height="12" fill="#5d8a4e"/><rect x="0" y="${y + 12}" width="${w}" height="60" fill="#33383d"/><line x1="0" x2="${w}" y1="${y + 42}" y2="${y + 42}" stroke="#f4f1e3" stroke-width="8" stroke-dasharray="70 60"/>`;
  const defs = `<defs><linearGradient id="rds-pole"><stop offset="0" stop-color="#7d868d"/><stop offset=".45" stop-color="#c8cfd4"/><stop offset="1" stop-color="#6f777d"/></linearGradient></defs>`;
  let wide = "", tall = "";
  S.forEach((s, i) => {
    const cx = 140 + i * 280;
    wide += post(cx, 150, 330) + sign(s[0], cx, 96, 150) + plate(cx, 192, 236, s);
    const tx = i % 2 ? 450 : 150, ty = i < 2 ? 0 : 290;
    tall += post(tx, ty + 120, ty + 300) + sign(s[0], tx, ty + 70, 130) + plate(tx, ty + 150, 260, s);
  });
  art.innerHTML =
    `<svg class="rds rds-wide" viewBox="0 0 1120 400" role="presentation">${defs}${wide}${ground(1120, 328)}</svg>` +
    `<svg class="rds rds-tall" viewBox="0 0 600 640" role="presentation">${defs.replace(/rds-pole/g, "rds-pole2")}${tall.replace(/rds-pole/g, "rds-pole2")}${ground(600, 580)}</svg>`;
  const sync = () => {
    const m = document.documentElement.dataset.mood || "working";
    art.querySelectorAll(".sg").forEach((g) => g.classList.toggle("on", g.dataset.m === m));
  };
  sync();
  new MutationObserver(sync).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
