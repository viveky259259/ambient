// Ink tearoom's hero art: an ensō brushed in sumi ink, left open at the top right. In the opening sits a single
// light in the demo's state colour (--state), and a vermilion seal is pressed below it.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  art.innerHTML = `
    <svg class="ink-art" viewBox="0 0 520 520" role="presentation">
      <defs>
        <filter id="ink-rough" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency=".035" numOctaves="3" seed="4"/><feDisplacementMap in="SourceGraphic" scale="18"/></filter>
        <filter id="ink-dry"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" seed="2"/><feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -1.6 1.05"/><feComposite in="SourceGraphic" operator="in"/></filter>
      </defs>
      <g filter="url(#ink-dry)"><g filter="url(#ink-rough)" fill="none" stroke="#1d1b18" stroke-linecap="round">
        <path d="M328 78 A196 196 0 1 0 441 216" stroke-width="40"/>
        <path d="M328 78 A196 196 0 0 0 180 84" stroke-width="22" opacity=".85"/>
        <path d="M442 224 A196 196 0 0 1 430 304" stroke-width="13" opacity=".7"/>
      </g></g>
      <circle class="ring" cx="404" cy="134" r="16" stroke-width="1.5"/>
      <circle class="light" cx="404" cy="134" r="9"/>
      <g transform="rotate(-3 446 446)">
        <rect x="414" y="414" width="62" height="62" rx="5" fill="#c8361d"/>
        <circle cx="445" cy="445" r="17" fill="none" stroke="#f1ede2" stroke-width="5" stroke-dasharray="88 20" stroke-linecap="round"/>
      </g>
    </svg>`;
})();
