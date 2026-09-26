(() => {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const dmg = document.body.dataset.dmg;

  // Storage can be unavailable (private windows, blocked site data); never let it break the page.
  const store = {
    get(key) { try { return localStorage.getItem(key); } catch { return null; } },
    set(key, value) { try { localStorage.setItem(key, value); } catch { /* ignore */ } },
  };

  // MARK: - Hero island

  const hero = document.querySelector(".hero");
  const island = document.getElementById("island-demo");
  if (hero && island) {
    const el = (id) => document.getElementById(id);
    const scenes = [
      { color: "var(--claude)", open: false, timer: "2m", wing: "breathe", hold: 3000, caption: "Claude is working on api-server" },
      { color: "var(--waiting)", open: true, glyph: "pulse", title: "api-server", tag: "CLAUDE", tagColor: "var(--claude)",
        msg: "Needs permission · Bash: rm -rf build", elapsed: "2m", hold: 4200, caption: "api-server needs your permission" },
      { color: "var(--claude)", open: false, timer: "3m", wing: "breathe", hold: 2600, caption: "Claude is back at work" },
      { color: "var(--done)", open: true, glyph: "check", title: "api-server", tag: "CLAUDE", tagColor: "var(--claude)",
        msg: "All 42 tests pass. Ready for review.", elapsed: "4m", hold: 4200, caption: "api-server is done: all 42 tests pass" },
      { color: "var(--error)", open: true, glyph: "bang", title: "docs", tag: "GEMINI", tagColor: "var(--gemini)",
        msg: "Quota exceeded — retry in 2 minutes", elapsed: "1m", hold: 4200, caption: "docs stopped: quota exceeded" },
      { color: "var(--done)", open: false, timer: "✓", wing: "", hold: 2400, caption: "All done" },
    ];

    const show = (s) => {
      hero.style.setProperty("--state", s.color);
      hero.style.setProperty("--glow", s.color);
      island.classList.toggle("open", s.open);
      el("island-caption").textContent = s.caption;
      if (s.open) {
        const orb = el("bloom-orb");
        orb.className = "orb big " + s.glyph;
        el("bloom-title").textContent = s.title;
        const tag = el("bloom-tag");
        tag.textContent = s.tag;
        tag.style.color = s.tagColor;
        tag.style.background = `color-mix(in srgb, ${s.tagColor} 18%, transparent)`;
        el("bloom-msg").textContent = s.msg;
        el("bloom-elapsed").textContent = s.elapsed;
      } else {
        el("wing-orb").className = "orb " + s.wing;
        el("wing-timer").textContent = s.timer;
      }
    };

    if (reduceMotion) {
      show(scenes[1]);
    } else {
      let i = 0;
      const next = () => {
        show(scenes[i]);
        const hold = scenes[i].hold;
        i = (i + 1) % scenes.length;
        setTimeout(next, hold);
      };
      next();
    }

    const clock = document.getElementById("clock");
    const tick = () => { clock.textContent = new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }); };
    tick();
    setInterval(tick, 30_000);
  }

  // MARK: - Dock glow chips

  const stage = document.getElementById("dock-stage");
  document.querySelectorAll("[data-dock]").forEach((chip) => {
    chip.addEventListener("click", () => {
      stage.style.setProperty("--dock", chip.dataset.dock);
      document.querySelectorAll("[data-dock]").forEach((c) => c.setAttribute("aria-pressed", String(c === chip)));
    });
  });

  // MARK: - Download and waitlist

  const sheet = document.getElementById("download-sheet");
  const form = sheet.querySelector("form");
  const formView = document.getElementById("sheet-form");
  const doneView = document.getElementById("sheet-done");
  const error = document.getElementById("wl-error");
  const submit = document.getElementById("wl-submit");
  const nameInput = document.getElementById("wl-name");
  const emailInput = document.getElementById("wl-email");

  const startDownload = () => {
    const a = document.createElement("a");
    a.href = dmg;
    a.download = "";
    document.body.appendChild(a);
    a.click();
    a.remove();
  };

  const showDone = () => {
    formView.classList.add("hidden");
    doneView.classList.remove("hidden");
  };

  const open = () => {
    if (store.get("ambient-waitlist") === "joined") {
      showDone();
      startDownload();
    }
    if (typeof sheet.showModal === "function") sheet.showModal(); else sheet.setAttribute("open", "");
    if (!formView.classList.contains("hidden")) nameInput.focus();
  };

  document.querySelectorAll("[data-download]").forEach((b) => b.addEventListener("click", open));
  sheet.querySelector("[data-close]").addEventListener("click", () => sheet.close());
  sheet.addEventListener("click", (e) => { if (e.target === sheet) sheet.close(); });

  const setError = (message, input) => {
    error.textContent = message;
    [nameInput, emailInput].forEach((i) => i.setAttribute("aria-invalid", String(i === input)));
    if (input) input.focus();
  };
  [nameInput, emailInput].forEach((i) => i.addEventListener("input", () => {
    error.textContent = "";
    i.setAttribute("aria-invalid", "false");
  }));

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const name = nameInput.value.trim();
    const email = emailInput.value.trim();
    if (!name) return setError("Enter your name.", nameInput);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return setError("Enter a valid email address.", emailInput);

    submit.disabled = true;
    submit.textContent = "Joining…";
    try {
      const body = new URLSearchParams(new FormData(form)).toString();
      const res = await fetch("/", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body });
      if (!res.ok) throw new Error(String(res.status));
      store.set("ambient-waitlist", "joined");
      showDone();
      startDownload();
    } catch {
      setError("Couldn't join the waitlist. Check your connection and try again.");
    } finally {
      submit.disabled = false;
      submit.textContent = "Join and download";
    }
  });
})();
