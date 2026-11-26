// Diner ticket rail's hero art: the counter's service bell, its knob in the demo's current state colour (--state on
// <html>, set by main.js), ringing now and then, over a short rail of order tickets, one per agent session.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const ink = "#2a1b16";
  const zig = (x, y, w, h) => {
    let d = `M${x} ${y} h${w} v${h}`;
    for (let i = 0; i < 10; i++) d += ` l${-w / 20} 8 l${-w / 20} -8`;
    return d + "z";
  };
  const tickets = [
    [40, -2.5, "#d97757", "No. 14", "claude"],
    [178, 1.5, "#f2a516", "No. 15", "codex"],
    [316, -1, "#2fa75e", "No. 16", "gemini"],
  ];
  let t = "";
  for (const [x, r, c, no, who] of tickets) {
    t += `<g transform="rotate(${r} ${x + 52} 300)">
      <path d="${zig(x, 296, 104, 118)}" fill="#fffdf4" stroke="${ink}" stroke-width="2"/>
      <text x="${x + 10}" y="318" font-family="Courier Prime, monospace" font-size="13" fill="${ink}">${no}</text>
      <line x1="${x + 10}" y1="326" x2="${x + 94}" y2="326" stroke="${ink}" stroke-width="1.5" stroke-dasharray="4 3"/>
      <circle cx="${x + 30}" cy="352" r="15" fill="${c}" stroke="${ink}" stroke-width="2.5"/>
      <text x="${x + 10}" y="394" font-family="Courier Prime, monospace" font-weight="700" font-size="14" fill="${ink}">${who}</text></g>`;
  }
  art.innerHTML = `
    <svg class="dnr-bell" viewBox="0 0 460 440" role="presentation">
      <ellipse cx="230" cy="232" rx="140" ry="17" fill="${ink}"/>
      <path d="M110 222 Q110 100 230 100 Q350 100 350 222Z" fill="#d9dcdd" stroke="${ink}" stroke-width="4"/>
      <path d="M140 210 Q144 128 214 116" fill="none" stroke="#fff" stroke-width="10" stroke-linecap="round"/>
      <rect x="218" y="70" width="24" height="32" fill="#8d9296" stroke="${ink}" stroke-width="4"/>
      <circle class="knob" cx="230" cy="60" r="17" stroke="${ink}" stroke-width="4"/>
      <g class="ding" stroke="#c9302a" stroke-width="5" stroke-linecap="round">
        <path d="M104 80 L80 58"/><path d="M128 52 L114 24"/><path d="M356 80 L380 58"/><path d="M332 52 L346 24"/>
      </g>
      <rect x="0" y="276" width="460" height="24" fill="url(#dnr-steel)" stroke="${ink}" stroke-width="2"/>
      <defs><linearGradient id="dnr-steel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4f4f2"/><stop offset=".45" stop-color="#a9adb0"/><stop offset=".55" stop-color="#5d6266"/><stop offset="1" stop-color="#d7d9da"/></linearGradient></defs>
      ${t}
    </svg>`;
})();
