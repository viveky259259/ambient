// Bauhaus forms' hero art: a composition of elementary forms (a blue circle, a yellow half-disc, a black bar and a
// red square) with Ambient's island below it, its orb in the demo's current state colour (--state on <html>).
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  art.innerHTML = `
    <svg class="bhf-forms" viewBox="0 0 600 600" role="presentation">
      <circle class="sun" cx="290" cy="250" r="230" fill="#2a4ba8"/>
      <path d="M210 330 h380 a190 190 0 0 1 -380 0z" fill="#f0b323" style="mix-blend-mode:multiply"/>
      <rect x="40" y="318" width="420" height="18" fill="#151515" transform="rotate(-38 40 327)"/>
      <rect x="470" y="20" width="100" height="100" fill="#d0392b"/>
      <circle cx="96" cy="96" r="22" fill="none" stroke="#151515" stroke-width="5"/>
      <path d="M60 530 h220 v18 a26 26 0 0 1 -26 26 h-168 a26 26 0 0 1 -26 -26z" fill="#151515"/>
      <circle class="orb" cx="92" cy="555" r="11"/>
      <rect x="120" y="551" width="96" height="8" rx="4" fill="#efe8d8" opacity=".55"/>
      <rect x="306" y="540" width="140" height="6" fill="#151515"/>
      <rect x="306" y="556" width="96" height="6" fill="#151515"/>
    </svg>`;
})();
