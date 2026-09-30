// Page speed from real visits (Core Web Vitals), recorded in Umami like the rest of the site's analytics:
// no cookies, no personal data, nothing when the browser sends Do Not Track.
(() => {
  if (!window.webVitals) return;
  const device = () => (innerWidth < 768 ? "mobile" : innerWidth < 1100 ? "tablet" : "desktop");
  const page = location.pathname;
  const queue = [];
  const flush = () => {
    if (!window.umami) return;
    while (queue.length) { try { window.umami.track("web-vital", queue.shift()); } catch { /* ignore */ } }
  };
  // Umami loads on its own schedule; hold measurements until it's there, and send what's waiting when the page hides.
  const timer = setInterval(() => { flush(); if (window.umami && !queue.length) clearInterval(timer); }, 1000);
  addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden") flush(); });
  const report = (metric) => {
    queue.push({
      metric: metric.name,
      // CLS is unitless; everything else is milliseconds.
      value: metric.name === "CLS" ? Math.round(metric.value * 1000) / 1000 : Math.round(metric.value),
      rating: metric.rating,
      page,
      device: device(),
    });
    flush();
  };
  const { onLCP, onINP, onCLS, onFCP, onTTFB } = window.webVitals;
  onLCP(report); onINP(report); onCLS(report); onFCP(report); onTTFB(report);
})();
