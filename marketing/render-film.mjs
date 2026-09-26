// Renders film/film.html frame by frame with Chrome and encodes it with the narration.
//
//   node render-film.mjs 16x9                   out/film/ambient-16x9.mp4 (also 1x1, 9x16)
//   node render-film.mjs 16x9 --stills 3,12,22  out/film/stills/16x9-<t>.png at those seconds
//
// Needs out/film/timeline.json and narration.wav from film/timeline.py.
import { chromium } from "playwright";
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const ratio = process.argv[2] || "16x9";
const sizes = { "16x9": [1920, 1080], "1x1": [1080, 1080], "9x16": [1080, 1920] };
if (!sizes[ratio]) throw new Error(`Unknown ratio ${ratio}`);
const [width, height] = sizes[ratio];
const stillsArg = process.argv.indexOf("--stills");
const stills = stillsArg > 0 ? process.argv[stillsArg + 1].split(",").map(Number) : null;

const timeline = JSON.parse(readFileSync("out/film/timeline.json", "utf8"));
const browser = await chromium.launch({ channel: "chrome" });
const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
await page.addInitScript((tl) => { window.TIMELINE = tl; }, timeline);
await page.goto(`file://${resolve("film/film.html")}?ratio=${ratio}`);
await page.evaluate(() => window.filmReady);

async function frameAt(t) {
  await page.evaluate((t) => window.renderAt(t), t);
  return page.screenshot({ type: "png", clip: { x: 0, y: 0, width, height } });
}

if (stills) {
  mkdirSync("out/film/stills", { recursive: true });
  for (const t of stills) {
    const png = await frameAt(t);
    const path = `out/film/stills/${ratio}-${t}.png`;
    (await import("node:fs")).writeFileSync(path, png);
    console.log("wrote", path);
  }
  await browser.close();
  process.exit(0);
}

const fps = timeline.fps;
const frames = Math.round(timeline.duration * fps);
const out = `out/film/ambient-${ratio}.mp4`;
const ffmpeg = spawn("ffmpeg", [
  "-y", "-loglevel", "error",
  "-f", "image2pipe", "-framerate", String(fps), "-i", "-",
  "-i", "out/film/narration.wav",
  "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
  "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
  "-shortest", out,
], { stdio: ["pipe", "inherit", "inherit"] });

const started = Date.now();
for (let i = 0; i < frames; i++) {
  const png = await frameAt(i / fps);
  if (!ffmpeg.stdin.write(png)) await new Promise((r) => ffmpeg.stdin.once("drain", r));
  if (i % 150 === 0) console.log(`${ratio}: frame ${i}/${frames} (${((Date.now() - started) / 1000).toFixed(0)} s)`);
}
ffmpeg.stdin.end();
await new Promise((r, j) => ffmpeg.on("close", (code) => (code === 0 ? r() : j(new Error(`ffmpeg exited ${code}`)))));
await browser.close();
console.log("wrote", out);
