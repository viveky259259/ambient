#!/usr/bin/env node
// Builds the homepage design-test themes from site/themes/<id>/meta.json.
//
//   node scripts/build-themes.mjs              every theme: fonts, then the list in loader.js and manifest.json
//   node scripts/build-themes.mjs almanac iris  only these themes' fonts (safe to run while others work on other themes)
//   node scripts/build-themes.mjs --list        only the list (no network)
//
// Fonts are self-hosted, so a visitor's browser never contacts Google: the script fetches each family's Latin
// woff2 files from Google Fonts once, into site/themes/fonts/, and writes site/themes/<id>/fonts.css.
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const themesDir = join(root, "site/themes");
const fontsDir = join(themesDir, "fonts");
const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";

const args = process.argv.slice(2);
const listOnly = args.includes("--list");
const only = args.filter((a) => !a.startsWith("--"));

// A theme counts once it has meta.json, theme.css and fonts.css; one still being written is left out of the list.
const themes = readdirSync(themesDir)
  .filter((d) => existsSync(join(themesDir, d, "meta.json")))
  .filter((id) => {
    const ready = existsSync(join(themesDir, id, "theme.css"));
    if (!ready) console.warn(`${id}: no theme.css yet, left out`);
    return ready;
  })
  .map((id) => {
    const meta = JSON.parse(readFileSync(join(themesDir, id, "meta.json"), "utf8"));
    return { id, ...meta, motif: existsSync(join(themesDir, id, "motif.js")) };
  })
  .sort((a, b) => (a.order ?? 99) - (b.order ?? 99) || a.id.localeCompare(b.id));

/** One family's @font-face rules, Latin subset only, pointing at local copies. */
async function family({ family, axes = "wght@400" }) {
  const url = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(family).replace(/%20/g, "+")}:${axes}&display=swap`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`${family} (${axes}): Google Fonts answered ${res.status}`);
  const css = await res.text();
  const blocks = css.split(/(?=\/\* [a-z-]+ \*\/)/).filter((b) => b.startsWith("/* latin */"));
  if (!blocks.length) throw new Error(`${family}: no Latin subset`);
  let out = "";
  for (const block of blocks) {
    const src = block.match(/url\((https:[^)]+\.woff2)\)/)?.[1];
    if (!src) continue;
    const name = `${family.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${createHash("sha1").update(src).digest("hex").slice(0, 8)}.woff2`;
    const file = join(fontsDir, name);
    if (!existsSync(file) || statSync(file).size === 0) {
      const font = await fetch(src, { headers: { "User-Agent": UA } });
      if (!font.ok) throw new Error(`${family}: font file answered ${font.status}`);
      writeFileSync(file, Buffer.from(await font.arrayBuffer()));
    }
    out += block.replace("/* latin */\n", "").replace(src, `/themes/fonts/${name}`);
  }
  return out;
}

if (!listOnly) {
  mkdirSync(fontsDir, { recursive: true });
  for (const t of themes.filter((t) => !only.length || only.includes(t.id))) {
    let css = `/* ${t.name}: self-hosted Latin subsets, written by scripts/build-themes.mjs. */\n`;
    for (const f of t.fonts ?? []) css += await family(f);
    writeFileSync(join(themesDir, t.id, "fonts.css"), css);
    console.log(`${t.id}: ${(t.fonts ?? []).map((f) => f.family).join(", ") || "system fonts"}`);
  }
}

if (!only.length || listOnly) {
  const listed = themes.filter((t) => {
    const ok = existsSync(join(themesDir, t.id, "fonts.css"));
    if (!ok) console.warn(`${t.id}: no fonts.css yet (run node scripts/build-themes.mjs ${t.id}), left out`);
    return ok;
  });
  themes.length = 0;
  themes.push(...listed);
  // The loader needs only what it uses before paint; the gallery and the report read manifest.json.
  const slim = themes.map((t) => {
    const o = { id: t.id, hero: t.hero || "stack" };
    if (t.copy) o.copy = t.copy;
    if (!t.motif) o.motif = false;
    if (t.off) o.off = true;
    return o;
  });
  const loaderPath = join(themesDir, "loader.js");
  const loader = readFileSync(loaderPath, "utf8");
  const next = loader.replace(/\/\* @themes \*\/[\s\S]*?\/\* @end \*\//, `/* @themes */\n  const THEMES = ${JSON.stringify(slim)};\n  /* @end */`);
  if (next === loader && !loader.includes(JSON.stringify(slim))) throw new Error("loader.js: markers not found");
  writeFileSync(loaderPath, next);
  const manifest = themes.map(({ id, name, set, inspiration, hero, off, order }) => ({ id, name, set, inspiration, hero, off: !!off, order }));
  writeFileSync(join(themesDir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");

  const families = [...new Set(themes.flatMap((t) => (t.fonts ?? []).map((f) => f.family)))].sort();
  writeFileSync(join(fontsDir, "README.md"), `# Theme fonts\n\nLatin subsets of these families, copied from Google Fonts by \`scripts/build-themes.mjs\`. Each is free to use and redistribute under the SIL Open Font License 1.1 or the Apache License 2.0; the licence and authors of each are on its page at https://fonts.google.com/specimen/<Family+Name>.\n\n${families.map((f) => `- ${f}`).join("\n")}\n`);
  console.log(`list: ${themes.length} themes (${themes.filter((t) => !t.off).length} in the test)`);
}
