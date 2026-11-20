// Engine telegraph's hero art: a brass engine-order telegraph whose four orders are Ambient's states. The handle
// swings to the demo's current state and that sector lights up (data-mood on <html>, set by main.js).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const K = "#1c1509";
  const W = [
    ["working", "WORKING", "--claude", "ORB BREATHES", -120],
    ["waiting", "NEEDS YOU", "--waiting", "AMBER PULSE", -60],
    ["done", "DONE", "--done", "GREEN TILL SEEN", 0],
    ["error", "ERROR", "--error", "RED + REASON", 60],
  ];
  const P = (a, r) => { a = ((a - 90) * Math.PI) / 180; return `${(Math.cos(a) * r).toFixed(1)} ${(Math.sin(a) * r).toFixed(1)}`; };
  let h = "";
  W.forEach(([mood, name, c, sub, a], i) => {
    const b = a + 60;
    h += `<g style="--c:var(${c})"><path class="sec" data-m="${mood}" d="M${P(a, 150)} L${P(a, 360)} A360 360 0 0 1 ${P(b, 360)} L${P(b, 150)} A150 150 0 0 0 ${P(a, 150)}Z" style="fill:var(--c)" fill-opacity=".16" stroke="${K}" stroke-width="3"/>`;
    h += `<path d="M${P(a, 312)} A312 312 0 0 1 ${P(b, 312)} L${P(b, 360)} A360 360 0 0 0 ${P(a, 360)}Z" style="fill:var(--c)" stroke="${K}" stroke-width="2"/></g>`;
    h += `<path id="eot-a${i}" d="M${P(a, 248)} A248 248 0 0 1 ${P(b, 248)}" fill="none"/><path id="eot-b${i}" d="M${P(a, 196)} A196 196 0 0 1 ${P(b, 196)}" fill="none"/>`;
    h += `<text font-family="Marcellus SC, serif" font-size="38" letter-spacing="3" fill="${K}"><textPath href="#eot-a${i}" startOffset="50%" text-anchor="middle">${name}</textPath></text>`;
    h += `<text font-family="Fira Code, monospace" font-weight="600" font-size="14" letter-spacing="1.5" fill="${K}"><textPath href="#eot-b${i}" startOffset="50%" text-anchor="middle">${sub}</textPath></text>`;
  });
  art.innerHTML = `<svg class="eot" viewBox="-410 -410 820 1010" role="presentation">
    <defs><linearGradient id="eot-br" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f1d896"/><stop offset=".5" stop-color="#b08a3d"/><stop offset="1" stop-color="#e0c074"/></linearGradient>
    <linearGradient id="eot-col" x1="0" x2="1"><stop offset="0" stop-color="#8a6a2a"/><stop offset=".45" stop-color="#ecd08d"/><stop offset="1" stop-color="#7d5f24"/></linearGradient></defs>
    <path d="M-70 330 L-100 600 L100 600 L70 330Z" fill="url(#eot-col)"/>
    <circle r="400" fill="url(#eot-br)"/><circle r="368" fill="#5b4416"/><circle r="360" fill="#f4ecd8"/>
    ${h}
    <circle r="360" fill="none" stroke="${K}" stroke-width="3"/><circle r="150" fill="#f4ecd8" stroke="${K}" stroke-width="2"/>
    <text y="-84" text-anchor="middle" font-family="Fira Code, monospace" font-size="13" letter-spacing="3" fill="${K}">MOST URGENT SHOWS</text>
    <text y="248" text-anchor="middle" font-family="Marcellus SC, serif" font-size="40" letter-spacing="8" fill="${K}">AMBIENT</text>
    <text y="282" text-anchor="middle" font-family="Fira Code, monospace" font-size="14" letter-spacing="4" fill="${K}">YAML.CAFE</text>
    <g class="arm" style="filter:drop-shadow(6px 10px 8px rgba(0,0,0,.45))"><rect x="-9" y="-420" width="18" height="60" fill="url(#eot-col)" stroke="#5b4416" stroke-width="2"/><rect x="-22" y="-500" width="44" height="96" rx="22" fill="#2a1a10" stroke="#cba659" stroke-width="3"/><path d="M0 -296 L-20 -356 L20 -356Z" fill="${K}" stroke="#f4ecd8" stroke-width="2"/></g>
    <circle r="46" fill="url(#eot-br)" stroke="#5b4416" stroke-width="2"/><circle r="14" fill="#5b4416"/>
  </svg>`;
  const arm = art.querySelector(".arm");
  const deg = { working: -90, waiting: -30, done: 30, error: 90 };
  const sync = () => {
    const m = document.documentElement.dataset.mood || "waiting";
    arm.style.transform = `rotate(${deg[m] ?? -30}deg)`;
    art.querySelectorAll(".sec").forEach((s) => s.setAttribute("fill-opacity", s.dataset.m === m ? ".95" : ".16"));
  };
  sync();
  new MutationObserver(sync).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
