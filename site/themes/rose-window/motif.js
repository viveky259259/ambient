// Rose window's hero art: rings of leaded glass in jewel colours with Ambient's four state colours set among
// them, a blurred copy behind for the light, and a centre that glows in the demo's state colour (--state).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  const C = ["#1f3f9a", "#6a2c8f", "#12366b", "#8f1f3a", "#1c6b5a", "#2a55c0"], S = ["#f5a524", "#d97757", "#3fb950", "#f85149"];
  const pt = (r, a) => `${(r * Math.cos(a)).toFixed(1)} ${(r * Math.sin(a)).toFixed(1)}`;
  const wedge = (r0, r1, a0, a1, f) => `<path d="M${pt(r0, a0)} L${pt(r1, a0)} A${r1} ${r1} 0 0 1 ${pt(r1, a1)} L${pt(r0, a1)} A${r0} ${r0} 0 0 0 ${pt(r0, a0)}Z" fill="${f}"/>`;
  let h = "";
  [[70, 160, 8], [160, 270, 16], [270, 360, 16], [360, 420, 32]].forEach(([r0, r1, n], ri) => {
    for (let i = 0; i < n; i++) {
      const a0 = (i / n) * 6.2832 - 1.5708 + (ri % 2 ? 3.1416 / n : 0), a1 = a0 + 6.2832 / n;
      let f = C[(i * 5 + ri * 3) % C.length];
      if (ri === 1 && i % 4 === 0) f = S[(i / 4) % 4];
      if (ri === 2 && i % 4 === 2) f = S[((i - 2) / 4 + 1) % 4];
      if (ri === 3 && i % 8 === 0) f = "#e6c27a";
      h += wedge(r0, r1, a0, a1, f);
    }
  });
  for (let i = 0; i < 8; i++) h += `<circle cx="${pt(215, (i / 8) * 6.2832).replace(" ", '" cy="')}" r="26" fill="${i % 2 ? "#e6c27a" : "#f0e8d8"}"/>`;
  const heart = `<circle class="heart" r="70"/><circle r="34" fill="#fff3d6" opacity=".85"/>`;
  art.innerHTML = `
    <svg class="ros-art" viewBox="-440 -440 880 880" role="presentation">
      <g class="glow"><g class="wheel">${h}</g>${heart}</g>
      <g class="wheel" stroke="#07060a" stroke-width="7" stroke-linejoin="round">${h}</g>
      <g stroke="#07060a" stroke-width="7">${heart}</g>
      <circle r="424" fill="none" stroke="#07060a" stroke-width="14"/>
      <circle r="433" fill="none" stroke="#e6c27a" stroke-width="1.5" opacity=".5"/>
    </svg>`;
})();
