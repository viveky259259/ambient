// Stage cue lights' hero art: a lighting bar over an empty stage, four cue lights in the state colours, each beam
// on a performer's mark. The beam for the demo's current state burns brightest (data-mood on <html>, see theme.css).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const cues = [["working", "#d97757"], ["waiting", "#ffb62e"], ["done", "#3fd476"], ["error", "#ff5a45"]];
  let defs = `<linearGradient id="stg-fl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a1a10"/><stop offset="1" stop-color="#0d0806"/></linearGradient>`;
  let s = `<polygon points="70,380 1030,380 1100,520 0,520" fill="url(#stg-fl)"/>`;
  for (let i = 0; i <= 14; i++) {
    const x = 70 + i * 68.6;
    s += `<line x1="${x.toFixed(1)}" y1="380" x2="${(550 + (x - 550) * 1.15).toFixed(1)}" y2="520" stroke="#000" stroke-width="1.5" opacity=".5"/>`;
  }
  s += `<rect x="40" y="18" width="1020" height="12" fill="#1c1b1e"/><rect x="40" y="18" width="1020" height="3" fill="#3a383d"/>`;
  cues.forEach(([mood, c], i) => {
    const x = 160 + i * 260;
    defs += `<linearGradient id="stg-b${i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${c}" stop-opacity=".75"/><stop offset="1" stop-color="${c}" stop-opacity=".14"/></linearGradient>`;
    defs += `<radialGradient id="stg-p${i}"><stop offset="0" stop-color="${c}" stop-opacity=".95"/><stop offset=".7" stop-color="${c}" stop-opacity=".45"/><stop offset="1" stop-color="${c}" stop-opacity="0"/></radialGradient>`;
    s += `<polygon class="beam m-${mood}" points="${x - 16},80 ${x + 16},80 ${x + 130},420 ${x - 130},420" fill="url(#stg-b${i})"/>`;
    s += `<ellipse class="pool m-${mood}" cx="${x}" cy="420" rx="150" ry="38" fill="url(#stg-p${i})"/>`;
    s += `<rect x="${x - 5}" y="30" width="10" height="18" fill="#3a383d"/><polygon points="${x - 22},44 ${x + 22},44 ${x + 30},84 ${x - 30},84" fill="#1c1b1e" stroke="#3a383d" stroke-width="2"/>`;
    s += `<ellipse cx="${x}" cy="84" rx="30" ry="7" fill="${c}"/><ellipse cx="${x}" cy="84" rx="16" ry="4" fill="#fff" opacity=".8"/>`;
    s += `<ellipse cx="${x}" cy="423" rx="30" ry="8" fill="#000" opacity=".45"/>`;
    s += `<path d="M${x - 22} 420 Q${x - 24} 326 ${x} 318 Q${x + 24} 326 ${x + 22} 420Z" fill="#09080a" opacity=".9"/><circle cx="${x}" cy="296" r="19" fill="#09080a" opacity=".9"/>`;
  });
  art.innerHTML = `<svg class="stg-rig" viewBox="0 0 1100 520" role="presentation"><defs>${defs}</defs>${s}</svg>`;
})();
