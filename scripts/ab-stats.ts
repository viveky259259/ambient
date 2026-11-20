// The homepage design test's results, from the keys in the "ab-views" and "downloads" Netlify Blobs stores.
// scripts/ab-report.sh fetches the keys and runs this; the maths is here so it can be tested.
//
//   node --import tsx scripts/ab-stats.ts VIEWS.json DOWNLOADS.json [--since YYYY-MM-DD] [--target 1000]
import { readFileSync } from "node:fs";
import { downloadVariant } from "../netlify/edge-functions/lib/ab-core.ts";

export type Row = { variant: string; visitors: number; downloads: number; rate: number; low: number; high: number };
export type Summary = { rows: Row[]; visitors: number; downloads: number; chi2: number; df: number; p: number };

/** Wilson score interval for a proportion (95% by default). */
export function wilson(successes: number, trials: number, z = 1.96): [number, number] {
  if (trials === 0) return [0, 0];
  const p = successes / trials;
  const d = 1 + (z * z) / trials;
  const centre = (p + (z * z) / (2 * trials)) / d;
  const half = (z * Math.sqrt((p * (1 - p)) / trials + (z * z) / (4 * trials * trials))) / d;
  return [Math.max(0, centre - half), Math.min(1, centre + half)];
}

function lnGamma(x: number): number {
  const c = [76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5];
  let y = x;
  const t = x + 5.5 - (x + 0.5) * Math.log(x + 5.5);
  let s = 1.000000000190015;
  for (const ci of c) s += ci / ++y;
  return -t + Math.log((2.5066282746310005 * s) / x);
}

/** Upper regularised incomplete gamma Q(a, x). */
function gammaQ(a: number, x: number): number {
  if (x <= 0) return 1;
  if (x < a + 1) {
    let sum = 1 / a, term = sum;
    for (let n = 1; n < 500; n++) { term *= x / (a + n); sum += term; if (Math.abs(term) < Math.abs(sum) * 1e-12) break; }
    return 1 - sum * Math.exp(-x + a * Math.log(x) - lnGamma(a));
  }
  let b = x + 1 - a, c = 1e300, d = 1 / b, h = d;
  for (let i = 1; i < 500; i++) {
    const an = -i * (i - a);
    b += 2;
    d = an * d + b; if (Math.abs(d) < 1e-300) d = 1e-300;
    c = b + an / c; if (Math.abs(c) < 1e-300) c = 1e-300;
    d = 1 / d;
    const delta = d * c;
    h *= delta;
    if (Math.abs(delta - 1) < 1e-12) break;
  }
  return Math.exp(-x + a * Math.log(x) - lnGamma(a)) * h;
}

/** Chi-square test of independence on downloads vs. visitors who didn't download, across variants. */
export function chiSquare(rows: { visitors: number; downloads: number }[]): { chi2: number; df: number; p: number } {
  const live = rows.filter((r) => r.visitors > 0);
  const n = live.reduce((s, r) => s + Math.max(r.visitors, r.downloads), 0);
  const yes = live.reduce((s, r) => s + r.downloads, 0);
  if (live.length < 2 || yes === 0 || yes === n) return { chi2: 0, df: Math.max(0, live.length - 1), p: 1 };
  let chi2 = 0;
  for (const r of live) {
    const total = Math.max(r.visitors, r.downloads);
    const expYes = (total * yes) / n, expNo = (total * (n - yes)) / n;
    chi2 += (r.downloads - expYes) ** 2 / expYes + (total - r.downloads - expNo) ** 2 / expNo;
  }
  const df = live.length - 1;
  return { chi2, df, p: gammaQ(df / 2, chi2 / 2) };
}

export function summarize(viewKeys: string[], downloadKeys: string[], variants: string[] = [], since = ""): Summary {
  const visitors = new Map<string, number>(variants.map((v) => [v, 0]));
  const downloads = new Map<string, number>(variants.map((v) => [v, 0]));
  for (const key of viewKeys) {
    const [day, variant] = key.split("/");
    if (!variant || day < since) continue;
    visitors.set(variant, (visitors.get(variant) ?? 0) + 1);
  }
  for (const key of downloadKeys) {
    const variant = downloadVariant(key);
    if (!variant || key.slice(0, 10) < since) continue;
    downloads.set(variant, (downloads.get(variant) ?? 0) + 1);
    if (!visitors.has(variant)) visitors.set(variant, 0);
  }
  const rows: Row[] = [...visitors.keys()].map((variant) => {
    const v = visitors.get(variant) ?? 0, d = downloads.get(variant) ?? 0;
    const [low, high] = wilson(d, Math.max(v, d));
    return { variant, visitors: v, downloads: d, rate: v ? d / v : 0, low, high };
  });
  rows.sort((a, b) => b.rate - a.rate || b.downloads - a.downloads || a.variant.localeCompare(b.variant));
  return {
    rows,
    visitors: rows.reduce((s, r) => s + r.visitors, 0),
    downloads: rows.reduce((s, r) => s + r.downloads, 0),
    ...chiSquare(rows),
  };
}

const pct = (x: number) => `${(x * 100).toFixed(1)}%`;

export function render(s: Summary, target: number, control = "almanac"): string {
  const out: string[] = [];
  out.push(`Design test: ${s.visitors} visitors, ${s.downloads} downloads from the homepage button (target ${target}).`);
  out.push(s.downloads >= target ? "The target is reached." : `${target - s.downloads} downloads to go.`);
  out.push("");
  out.push(`${"variant".padEnd(24)}${"visitors".padStart(9)}${"downloads".padStart(11)}${"rate".padStart(8)}   95% range`);
  for (const r of s.rows) {
    out.push(`${r.variant.padEnd(24)}${String(r.visitors).padStart(9)}${String(r.downloads).padStart(11)}${pct(r.rate).padStart(8)}   ${pct(r.low)}–${pct(r.high)}`);
  }
  out.push("");
  out.push(`Chi-square across ${s.df + 1} variants: ${s.chi2.toFixed(1)} on ${s.df} df, p = ${s.p < 0.0001 ? "<0.0001" : s.p.toFixed(4)}.`);
  const leader = s.rows.find((r) => r.visitors > 0);
  const base = s.rows.find((r) => r.variant === control);
  if (s.p >= 0.05 || !leader) {
    out.push("No design is clearly ahead yet: the differences are within what chance alone produces.");
  } else if (base && leader.variant !== control && leader.low > base.high) {
    out.push(`${leader.variant} converts better than ${control}, and their ranges don't overlap.`);
  } else {
    out.push(`The designs differ, but ${leader.variant}'s range still overlaps others; keep the top few and test again.`);
  }
  return out.join("\n");
}

function keys(file: string): string[] {
  const data = JSON.parse(readFileSync(file, "utf8"));
  const blobs = Array.isArray(data) ? data : data.blobs ?? [];
  return blobs.map((b: unknown) => (typeof b === "string" ? b : (b as { key: string }).key));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [views, downloads, ...rest] = process.argv.slice(2);
  const flag = (name: string) => { const i = rest.indexOf(name); return i >= 0 ? rest[i + 1] : undefined; };
  let variants: string[] = [];
  try {
    variants = JSON.parse(readFileSync(new URL("../site/themes/manifest.json", import.meta.url), "utf8"))
      .filter((t: { off: boolean }) => !t.off).map((t: { id: string }) => t.id);
  } catch { /* the manifest is optional */ }
  const summary = summarize(keys(views), keys(downloads), variants, flag("--since") ?? "");
  console.log(render(summary, Number(flag("--target") ?? 1000)));
}
