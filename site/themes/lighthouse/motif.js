// Lighthouse's hero art: a lamp at the notch, its turning beam and its rings. The lamp and the beam take the demo's
// current state colour (--state on <html>, via theme.css); the beam stands still under reduced motion.
(() => {
  const art = document.getElementById("motif");
  if (!art) return;
  art.innerHTML = '<div class="lh-beam"></div><div class="lh-rings"></div><div class="lh-notch"></div>';
})();
