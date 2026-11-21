// Builds the QA dashboard: one self-contained page from qa/cases, qa/run/cases and every run in
// build/qa-results (or $QA_RESULTS_DIR). Optionally publishes it to the Docket hub (private to the tailnet).
//
//   node scripts/qa-dashboard.ts             write build/qa-dashboard/index.html
//   node scripts/qa-dashboard.ts --publish   and publish it with `docket publish`

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseCases, type QACase } from "./qa-cases.ts";
import { parseScript, RESULTS_DIR, type Result, type RunInfo, type Status } from "./qa-run.ts";

const ROOT = resolve(fileURLToPath(import.meta.url), "../..");
const RESULTS = RESULTS_DIR;
const OUT = join(ROOT, "build/qa-dashboard");

export interface Run {
  dir: string;
  info: Partial<RunInfo> & { started: string };
  results: Result[];
}

export interface CaseRow {
  qaCase: QACase;
  area: string;
  scripted: "all" | "part" | "";
  history: { status: Status; run: Run }[]; // newest first
}

export const AREAS: Record<string, string> = {
  SET: "Setup",
  EVT: "Events",
  PRM: "Permissions",
  ISL: "Island",
  ALR: "Alerts",
  DCK: "Dock",
  PET: "Pet",
  WAL: "Wallpaper",
  SPK: "Read aloud",
  SPM: "Speaker & mic",
  RMT: "Remote",
  MEM: "Memory",
  BRD: "Board",
  APP: "App",
};

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);

export function loadRuns(dir = RESULTS): Run[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((d) => existsSync(join(dir, d, "results.json")))
    .map((d) => {
      const info = existsSync(join(dir, d, "run.json"))
        ? JSON.parse(readFileSync(join(dir, d, "run.json"), "utf8"))
        : { started: d.replace(/^(\d{4}-\d\d-\d\d)-(\d\d)-(\d\d)-(\d\d)$/, "$1 $2:$3:$4") };
      return { dir: d, info, results: JSON.parse(readFileSync(join(dir, d, "results.json"), "utf8")) };
    })
    .sort((a, b) => b.info.started.localeCompare(a.info.started));
}

export function buildRows(cases: QACase[], scripts: Map<string, "all" | "part">, runs: Run[]): CaseRow[] {
  return cases.map((qaCase) => ({
    qaCase,
    area: qaCase.id.split("-")[0],
    scripted: scripts.get(qaCase.id) ?? "",
    history: runs.flatMap((run) => run.results.filter((r) => r.id === qaCase.id).map((r) => ({ status: r.status, run }))),
  }));
}

/** The latest result decides; a case never run (or not scripted) has none. */
export const latest = (row: CaseRow): Status | undefined => row.history[0]?.status;

/** How many runs in a row, newest first, have had this status. */
export function streak(row: CaseRow): number {
  const s = latest(row);
  let n = 0;
  while (n < row.history.length && row.history[n].status === s) n++;
  return n;
}

const LABEL: Record<Status, string> = {
  pass: "Pass",
  fail: "Fail",
  "known-gap": "Known gap",
  "gap-fixed": "Gap fixed?",
  error: "Error",
};

function dot(s: Status | undefined, title = ""): string {
  return `<span class="dot ${s ?? "none"}" title="${esc(title || (s ? LABEL[s] : "Not run"))}"></span>`;
}

export function render(rows: CaseRow[], runs: Run[], now: string): string {
  const scripted = rows.filter((r) => r.scripted);
  const count = (s: Status) => rows.filter((r) => latest(r) === s).length;
  const notRun = scripted.filter((r) => !latest(r)).length;
  const manual = rows.filter((r) => r.scripted !== "all").length;
  const lastFull = runs.find((r) => r.info.context === "main") ?? runs.find((r) => r.info.selection === "all scripted cases") ?? runs[0];
  const failing = rows.filter((r) => latest(r) === "fail" || latest(r) === "error");
  const tiles = [
    ["Cases", rows.length, "in qa/cases"],
    ["Scripted", scripted.length, `${scripted.filter((r) => r.scripted === "part").length} only in part`],
    ["Passing", count("pass"), "latest result"],
    ["Failing", count("fail") + count("error"), `${count("error")} script errors`],
    ["Known gaps", count("known-gap"), `${count("gap-fixed")} now passing`],
    ["For a person", manual, "not scripted, or only in part"],
  ];

  const areaRows = Object.entries(AREAS).map(([key, name]) => {
    const a = rows.filter((r) => r.area === key);
    const n = (s: Status) => a.filter((r) => latest(r) === s).length;
    const sc = a.filter((r) => r.scripted).length;
    const parts = [
      ["pass", n("pass")],
      ["fail", n("fail") + n("error")],
      ["known-gap", n("known-gap") + n("gap-fixed")],
      ["none", a.length - n("pass") - n("fail") - n("error") - n("known-gap") - n("gap-fixed")],
    ] as const;
    const bar = parts
      .filter(([, v]) => v > 0)
      .map(([c, v]) => `<span class="seg ${c}" style="flex:${v}" title="${v}"></span>`)
      .join("");
    return `<tr><td>${esc(name)} <span class="muted">${key}</span></td><td class="num">${a.length}</td><td class="num">${sc}</td><td class="num">${n("pass")}</td><td class="num">${n("fail") + n("error")}</td><td class="num">${n("known-gap")}</td><td class="bar"><span class="stack">${bar}</span></td></tr>`;
  });

  const failingHtml = failing.length
    ? `<table><thead><tr><th>Case</th><th>Priority</th><th>Runs failing</th><th>Last output</th></tr></thead><tbody>${failing
        .sort((a, b) => a.qaCase.priority.localeCompare(b.qaCase.priority))
        .map((r) => {
          const out = r.history[0].run.results.find((x) => x.id === r.qaCase.id)?.output ?? "";
          return `<tr><td><b>${r.qaCase.id}</b> ${esc(r.qaCase.title)}</td><td><span class="pri ${r.qaCase.priority}">${r.qaCase.priority}</span></td><td class="num">${streak(r)}</td><td><details><summary>${esc(out.split("\n").filter((l) => l.startsWith("FAIL")).pop() ?? out.split("\n").pop() ?? "")}</summary><pre>${esc(out.slice(-3000))}</pre></details></td></tr>`;
        })
        .join("")}</tbody></table>`
    : `<p class="ok">Nothing failing in the latest results.</p>`;

  const caseSections = Object.entries(AREAS).map(([key, name]) => {
    const a = rows.filter((r) => r.area === key);
    const body = a
      .map((r) => {
        const hist = r.history.slice(0, 12).map((h) => dot(h.status, `${LABEL[h.status]} · ${h.run.info.started} UTC · ${h.run.info.commit ?? ""}`)).join("");
        const st = latest(r);
        return `<tr><td><b>${r.qaCase.id}</b> ${esc(r.qaCase.title)}${r.qaCase.knownGap ? ' <span class="tag">known gap</span>' : ""}</td><td><span class="pri ${r.qaCase.priority}">${r.qaCase.priority}</span></td><td>${r.scripted || '<span class="muted">person</span>'}</td><td>${st ? `<span class="res ${st}">${LABEL[st]}</span>` : '<span class="muted">—</span>'}</td><td class="hist">${hist}</td></tr>`;
      })
      .join("");
    const sc = a.filter((r) => r.scripted).length;
    return `<details class="area"><summary><b>${esc(name)}</b> <span class="muted">${a.length} cases · ${sc} scripted</span></summary><table><thead><tr><th>Case</th><th>Priority</th><th>Checked by</th><th>Latest</th><th>Recent runs (newest left)</th></tr></thead><tbody>${body}</tbody></table></details>`;
  });

  const runRows = runs
    .slice(0, 40)
    .map((run) => {
      const n = (s: Status) => run.results.filter((r) => r.status === s).length;
      return `<tr><td>${esc(run.info.started)}</td><td>${esc(run.info.commit ?? "")}</td><td>${esc(run.info.build ?? "")}</td><td>${run.info.runUrl ? `<a href="${esc(run.info.runUrl)}">${esc(run.info.context ?? "CI")}</a>` : esc(run.info.context ?? "local")}<br><span class="muted">${esc(run.info.selection ?? "")}</span></td><td class="num">${run.results.length}</td><td class="num">${n("pass")}</td><td class="num">${n("fail") + n("error")}</td><td class="num">${n("known-gap")}</td></tr>`;
    })
    .join("");

  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ambient QA</title>
<style>
:root{--bg:#fbfaf7;--fg:#1d1d1b;--muted:#6b6a64;--line:#e4e1d8;--card:#fff;--pass:#2f8f5b;--fail:#c8423a;--gap:#c98a1b;--none:#c9c6bd;--accent:#3a5bc7}
@media (prefers-color-scheme:dark){:root{--bg:#151514;--fg:#ecebe6;--muted:#9a988f;--line:#2e2d2a;--card:#1d1d1b;--pass:#4cb57d;--fail:#e8655c;--gap:#e0a83c;--none:#4a4843;--accent:#8aa4ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Inter",system-ui,sans-serif}
main{max-width:1180px;margin:0 auto;padding:28px 16px 64px}h1{font-size:26px;margin:0 0 4px}h2{font-size:18px;margin:36px 0 12px}
.muted{color:var(--muted)}.sub{color:var(--muted);margin:0 0 20px}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px}
.tile{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px 16px}.tile .v{font-size:28px;font-weight:650}.tile .k{font-weight:600}.tile .n{color:var(--muted);font-size:13px}
.tile.fail .v{color:var(--fail)}.tile.pass .v{color:var(--pass)}.tile.gap .v{color:var(--gap)}
.wrap,details.area{overflow-x:auto}table{min-width:680px;width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden;font-size:14px}
th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}th{font-size:12px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);font-weight:600}
td.num{text-align:right;font-variant-numeric:tabular-nums}td.bar{width:30%}
.stack{display:flex;height:10px;border-radius:5px;overflow:hidden;background:var(--none)}.seg.pass{background:var(--pass)}.seg.fail{background:var(--fail)}.seg.known-gap{background:var(--gap)}.seg.none{background:var(--none)}
.dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:3px;background:var(--none)}.dot.pass{background:var(--pass)}.dot.fail,.dot.error{background:var(--fail)}.dot.known-gap,.dot.gap-fixed{background:var(--gap)}
.res{font-weight:600}.res.pass{color:var(--pass)}.res.fail,.res.error{color:var(--fail)}.res.known-gap,.res.gap-fixed{color:var(--gap)}
.pri{font-size:12px;font-weight:700;padding:1px 6px;border-radius:4px;border:1px solid var(--line)}.pri.P0{color:var(--fail);border-color:var(--fail)}
.tag{font-size:11px;padding:1px 6px;border-radius:4px;background:var(--line);color:var(--muted)}
details.area{margin:8px 0}details.area>summary{cursor:pointer;padding:10px 12px;background:var(--card);border:1px solid var(--line);border-radius:10px}details.area[open]>summary{margin-bottom:8px}
pre{white-space:pre-wrap;font-size:12px;max-height:280px;overflow:auto;background:var(--bg);padding:8px;border-radius:6px}
summary{cursor:pointer}.ok{color:var(--pass);font-weight:600}td.hist{white-space:nowrap}
</style></head><body><main>
<h1>Ambient QA</h1>
<p class="sub">${lastFull ? `Latest run ${esc(lastFull.info.started)} UTC on ${esc(lastFull.info.host ?? "this Mac")} · Ambient ${esc(lastFull.info.version ?? "")} build ${esc(lastFull.info.build ?? "")} · commit ${esc(lastFull.info.commit ?? "")}` : "No runs yet"} · page built ${esc(now)} UTC</p>
<div class="tiles">${tiles
    .map(([k, v, n], i) => `<div class="tile ${["", "", "pass", "fail", "gap", ""][i]}"><div class="k">${k}</div><div class="v">${v}</div><div class="n">${n}</div></div>`)
    .join("")}</div>
<p class="muted">${notRun ? `${notRun} scripted cases have not run yet. ` : ""}Results are each case's latest; scripted cases run on this Mac against a separate QA copy of the app in a throwaway home. Cases marked <i>person</i>, and the rest of those checked only in part, need someone at a real Mac.</p>
<h2>Failing now</h2><div class="wrap">${failingHtml}</div>
<h2>By area</h2><div class="wrap"><table><thead><tr><th>Area</th><th>Cases</th><th>Scripted</th><th>Pass</th><th>Fail</th><th>Known gap</th><th>Latest results</th></tr></thead><tbody>${areaRows.join("")}</tbody></table></div>
<h2>Every case</h2>${caseSections.join("")}
<h2>Runs</h2><div class="wrap"><table><thead><tr><th>Started (UTC)</th><th>Commit</th><th>Build</th><th>For</th><th>Cases</th><th>Pass</th><th>Fail</th><th>Known gap</th></tr></thead><tbody>${runRows}</tbody></table></div>
</main></body></html>
`;
}

function main(argv: string[]): number {
  const casesDir = join(ROOT, "qa/cases");
  const cases = readdirSync(casesDir)
    .filter((n) => n.endsWith(".md"))
    .flatMap((n) => parseCases(readFileSync(join(casesDir, n), "utf8"), `qa/cases/${n}`).cases);
  const runDir = join(ROOT, "qa/run/cases");
  const scripts = new Map<string, "all" | "part">();
  if (existsSync(runDir)) {
    for (const f of readdirSync(runDir).filter((f) => /^[A-Z]{2,5}-\d{3}\.sh$/.test(f))) {
      const s = parseScript(f.slice(0, -3), join(runDir, f), readFileSync(join(runDir, f), "utf8"));
      scripts.set(s.id, s.partial ? "part" : "all");
    }
  }
  const runs = loadRuns();
  const html = render(buildRows(cases, scripts, runs), runs, new Date().toISOString().replace(/\..*/, "").replace("T", " "));
  mkdirSync(OUT, { recursive: true });
  const file = join(OUT, "index.html");
  writeFileSync(file, html);
  console.log(`Wrote ${file}`);
  if (argv.includes("--publish")) {
    // The project defaults to this git repository's ("ambient"); no Docket config change is needed.
    const pub = spawnSync("docket", ["publish", file, "--category", "technical", "--title", "Ambient QA"], {
      cwd: ROOT,
      encoding: "utf8",
    });
    process.stdout.write(pub.stdout ?? "");
    process.stderr.write(pub.stderr ?? "");
    if (pub.status !== 0) return 1;
  }
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
