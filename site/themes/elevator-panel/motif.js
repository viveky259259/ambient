// Elevator panel's hero art: the car's arched black panel. The floor dial's needle and the lit call button follow
// the demo's state (data-mood on <html>, set by main.js); the most urgent floor is the top one.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const floors = [
    ["waiting", "4", "Needs you", "An amber pulse.", "--waiting", 54],
    ["error", "3", "Error", "Red, with the reason one hover away.", "--error", 18],
    ["done", "2", "Done", "Green, until you look at the session.", "--done", -18],
    ["working", "1", "Working", "An orb in the agent's colour breathes.", "--claude", -54],
  ];
  const cx = 260, cy = 250;
  let dial = "", rows = "";
  floors.forEach(([mood, n, name, sub, c, deg], i) => {
    const a = ((deg - 90) * Math.PI) / 180, x = cx + Math.cos(a) * 150, y = cy + Math.sin(a) * 150;
    dial += `<g style="--c:var(${c})"><circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="20" fill="#0d0e10" stroke-width="2.5" style="stroke:var(--c)"/><text x="${x.toFixed(1)}" y="${(y + 7).toFixed(1)}" text-anchor="middle" font-size="20" font-weight="700" style="fill:var(--c)">${n}</text></g>`;
    const ry = 388 + i * 92;
    rows += `<g class="fl" data-m="${mood}" style="--c:var(${c})">
      <circle class="halo" cx="96" cy="${ry}" r="54" fill="url(#elv-glow)" style="color:var(--c)"/>
      <circle cx="96" cy="${ry}" r="38" fill="none" stroke="#2a2c2e" stroke-width="2"/>
      <circle cx="96" cy="${ry}" r="35" fill="none" stroke-width="3.5" style="stroke:var(--c)"/>
      <circle class="bulb" cx="96" cy="${ry}" r="30" fill="url(#elv-btn)" stroke="#8c9092" stroke-width="3"/>
      <text class="num" x="96" y="${ry + 17}" text-anchor="middle">${n}</text>
      <text class="lab" x="160" y="${ry - 4}" style="fill:var(--c)">${name.toUpperCase()}</text>
      <text class="sub" x="160" y="${ry + 22}">${sub}</text></g>`;
  });
  art.innerHTML = `<svg class="elv" viewBox="0 0 520 760" role="presentation">
    <defs>
      <radialGradient id="elv-btn" cx="40%" cy="30%"><stop offset="0" stop-color="#3b3e42"/><stop offset=".75" stop-color="#0c0d0e"/></radialGradient>
      <radialGradient id="elv-glow"><stop offset=".4" stop-color="currentColor" stop-opacity=".55"/><stop offset="1" stop-color="currentColor" stop-opacity="0"/></radialGradient>
      <linearGradient id="elv-car" x1="0" y1="0" x2=".3" y2="1"><stop offset="0" stop-color="#1b1d20"/><stop offset="1" stop-color="#08090a"/></linearGradient>
    </defs>
    <path d="M8 752V268A252 252 0 0 1 512 268V752Z" fill="url(#elv-car)" stroke="#a9acae" stroke-width="12"/>
    <path d="M2 758V268A258 258 0 0 1 518 268V758Z" fill="none" stroke="#6d7173" stroke-width="2"/>
    <path d="M70 ${cy}A190 190 0 0 1 450 ${cy}" fill="none" stroke="#8c9092" stroke-width="2"/>
    <path d="M96 ${cy}A164 164 0 0 1 424 ${cy}" fill="none" stroke="#3a3d40" stroke-width="26"/>
    ${dial}
    <g class="needle"><path d="M${cx - 7} ${cy}L${cx} ${cy - 168}L${cx + 7} ${cy}Z" fill="#ffae1a" style="fill:var(--state,#ffae1a)"/></g>
    <circle cx="${cx}" cy="${cy}" r="20" fill="#cdd0d1"/><circle cx="${cx}" cy="${cy}" r="7" fill="#17191b"/>
    ${rows}
    <text class="cap" x="260" y="728" text-anchor="middle">MOST URGENT FLOOR SHOWS FIRST</text>
  </svg>`;
  const needle = art.querySelector(".needle");
  const angle = Object.fromEntries(floors.map((f) => [f[0], f[5]]));
  const sync = () => {
    const m = document.documentElement.dataset.mood || "waiting";
    needle.style.transform = `rotate(${angle[m] ?? 54}deg)`;
    art.querySelectorAll(".fl").forEach((g) => g.classList.toggle("lit", g.dataset.m === m));
  };
  sync();
  new MutationObserver(sync).observe(document.documentElement, { attributes: true, attributeFilter: ["data-mood"] });
})();
