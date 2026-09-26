// Renders stills/*.html to PNGs at each page's own size: node render-stills.mjs [name…]
import { chromium } from "playwright";
import { readdirSync } from "node:fs";
import { basename, resolve } from "node:path";

const sizes = { og: [1200, 630] };
const names = process.argv.slice(2).length ? process.argv.slice(2)
  : readdirSync("stills").filter((f) => f.endsWith(".html")).map((f) => basename(f, ".html"));

const browser = await chromium.launch({ channel: "chrome" });
for (const name of names) {
  const [width, height] = sizes[name] ?? [1200, 630];
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  await page.goto("file://" + resolve("stills", name + ".html"));
  await page.evaluate(() => document.getAnimations().forEach((a) => { a.currentTime = 600; a.pause(); }));
  await page.waitForTimeout(300);
  const out = resolve("out", name + ".png");
  await page.screenshot({ path: out });
  console.log("wrote", out);
  await page.close();
}
await browser.close();
