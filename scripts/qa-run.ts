// Runs the scripted QA cases (qa/run/cases/<ID>.sh) on this Mac, each in its own throwaway home,
// against build/AmbientQA.app. See qa/run/README.md.
//
//   node scripts/qa-run.ts                     every scripted case
//   node scripts/qa-run.ts SET-001 EVT-036     these cases
//   node scripts/qa-run.ts --area SET          one area
//   node scripts/qa-run.ts --changed origin/main   the scripted cases `qa-cases select` picks
//   --keep        keep every case's folder, not only failed ones
//   --skip-slow   leave out cases marked `# slow: yes` (the merge run does)

import { spawn, spawnSync } from "node:child_process";
import { connect } from "node:net";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseCases, select, type QACase } from "./qa-cases.ts";

const ROOT = resolve(fileURLToPath(import.meta.url), "../..");
/** Where runs are kept. CI sets QA_RESULTS_DIR outside the checkout, which every job wipes. */
export const RESULTS_DIR = process.env.QA_RESULTS_DIR || join(ROOT, "build/qa-results");
const RUN_DIR = join(ROOT, "qa/run/cases");
const APP = join(ROOT, "build/AmbientQA.app");
const APP_BIN = join(APP, "Contents/MacOS/AmbientQA");
const DEFAULTS_DOMAIN = "com.viveky259259.Ambient.qa";
// App cases share one settings domain and one screen, so only one runs at a time, across runners.
const LOCK = "/tmp/ambient-qa.lock";

export interface Script {
  id: string;
  path: string;
  needsApp: boolean;
  timeout: number;
  /** `# checks: part`: the script checks only some of the case's expected results; a person checks the rest. */
  partial: boolean;
  /** `# slow: yes`: takes minutes (waits on a timer in the app); left out by --skip-slow. */
  slow: boolean;
}

/** build/qa-results/<time>/run.json: what was run, on which code, where. */
export interface RunInfo {
  started: string;
  finished: string;
  commit: string;
  branch: string;
  version: string;
  build: string;
  host: string;
  selection: string;
  totalCases: number;
  scriptedCases: number;
  /** What the run is for, e.g. "main" or "PR #48 · feat/agent-history" (QA_CONTEXT). */
  context?: string;
  /** The CI run's log (QA_RUN_URL). */
  runUrl?: string;
}

export type Status ="pass" | "fail" | "known-gap" | "gap-fixed" | "error";

export interface Result {
  id: string;
  title: string;
  priority: string;
  status: Status;
  partial: boolean;
  seconds: number;
  output: string;
  folder?: string;
}

/** Header lines: `# needs-app: yes|no` (default no), `# timeout: SECONDS` (default 60), `# checks: all|part` (default all). */
export function parseScript(id: string, path: string, text: string): Script {
  const needsApp = /^#\s*needs-app:\s*yes\s*$/m.test(text);
  const t = /^#\s*timeout:\s*(\d+)\s*$/m.exec(text);
  const partial = /^#\s*checks:\s*part\s*$/m.test(text);
  const slow = /^#\s*slow:\s*yes\s*$/m.test(text);
  return { id, path, needsApp, timeout: t ? Number(t[1]) : 60, partial, slow };
}

/** A script failing on a case marked Known gap is expected; one passing means the gap may be fixed. */
export function classify(exitCode: number | null, knownGap: boolean): Status {
  if (exitCode === 0) return knownGap ? "gap-fixed" : "pass";
  if (exitCode === 1) return knownGap ? "known-gap" : "fail";
  return "error";
}

function loadCases(): Map<string, QACase> {
  const dir = join(ROOT, "qa/cases");
  const map = new Map<string, QACase>();
  for (const n of readdirSync(dir).filter((f) => f.endsWith(".md"))) {
    for (const c of parseCases(readFileSync(join(dir, n), "utf8"), `qa/cases/${n}`).cases) map.set(c.id, c);
  }
  return map;
}

function loadScripts(): Script[] {
  if (!existsSync(RUN_DIR)) return [];
  return readdirSync(RUN_DIR)
    .filter((f) => /^[A-Z]{2,5}-\d{3}\.sh$/.test(f))
    .sort()
    .map((f) => parseScript(f.slice(0, -3), join(RUN_DIR, f), readFileSync(join(RUN_DIR, f), "utf8")));
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function listening(socket: string): Promise<boolean> {
  return new Promise((res) => {
    const c = connect(socket);
    c.once("connect", () => (c.destroy(), res(true)));
    c.once("error", () => res(false));
  });
}

/** Operations on other processes, replaced in tests. */
export interface ProcessOps {
  alive(pid: number): boolean;
  /** The process's command line, empty when it can't be read. */
  command(pid: number): string;
  kill(pid: number, signal: NodeJS.Signals): void;
  sleep(ms: number): Promise<void>;
}

const systemOps: ProcessOps = {
  alive(pid) {
    try {
      process.kill(pid, 0);
      return true;
    } catch (e) {
      return (e as NodeJS.ErrnoException).code === "EPERM";
    }
  },
  command: (pid) => spawnSync("ps", ["-o", "command=", "-p", String(pid)], { encoding: "utf8" }).stdout?.trim() ?? "",
  kill: (pid, signal) => process.kill(pid, signal),
  sleep,
};

/** The QA app's executable, from any checkout: runners on this Mac share the lock but not the checkout. */
export function isQAApp(command: string): boolean {
  return /\/AmbientQA\.app\/Contents\/MacOS\/AmbientQA(\s|$)/.test(command.trim());
}

function readLockFile(dir: string, name: string): string {
  try {
    return readFileSync(join(dir, name), "utf8").trim();
  } catch {
    return "";
  }
}

/** Stops a QA app and the process group it leads: politely, then for good after three seconds. */
async function stopApp(pid: number, ops: ProcessOps): Promise<void> {
  const signal = (s: NodeJS.Signals) => {
    try {
      ops.kill(-pid, s);
    } catch {
      try {
        ops.kill(pid, s);
      } catch {}
    }
  };
  signal("SIGTERM");
  for (let i = 0; i < 15 && ops.alive(pid); i++) await ops.sleep(200);
  if (ops.alive(pid)) signal("SIGKILL");
}

/**
 * Clears the lock when the runner holding it has died, as when CI cancels a job: stops the QA app that runner
 * started, which would otherwise keep running with its broken test settings, and removes that case's folder.
 * False while the runner is alive.
 */
export async function clearStaleLock(dir: string, ops: ProcessOps = systemOps): Promise<boolean> {
  if (!existsSync(dir)) return true;
  const owner = Number(readLockFile(dir, "pid")) || 0;
  if (owner && ops.alive(owner)) return false;
  const app = Number(readLockFile(dir, "app")) || 0;
  // A pid can be reused: only an AmbientQA is stopped.
  if (app && ops.alive(app) && isQAApp(ops.command(app))) await stopApp(app, ops);
  const folder = readLockFile(dir, "folder");
  if (/^\/tmp\/aq\.[A-Za-z0-9]+$/.test(folder)) rmSync(folder, { recursive: true, force: true });
  rmSync(dir, { recursive: true, force: true });
  return true;
}

/** Takes the lock, noting this runner and the case's folder so another runner can clean up if this one dies. */
async function lock(folder: string): Promise<() => void> {
  for (;;) {
    try {
      mkdirSync(LOCK);
      writeFileSync(join(LOCK, "pid"), String(process.pid));
      writeFileSync(join(LOCK, "folder"), folder);
      held = true;
      return () => {
        held = false;
        rmSync(LOCK, { recursive: true, force: true });
      };
    } catch {
      // A lock left by a runner that died is taken over.
      if (await clearStaleLock(LOCK)) continue;
      await sleep(500);
    }
  }
}

/** The QA app this runner started and the lock it holds, for stopping them when the runner is cancelled. */
let runningApp: number | undefined;
let held = false;

/** CI cancels a job with SIGINT, then SIGTERM. Stop the app first: it runs in its own process group. */
function stopOnSignal() {
  for (const s of ["SIGINT", "SIGTERM", "SIGHUP"] as const) {
    process.once(s, () => {
      if (runningApp) {
        try {
          process.kill(-runningApp, "SIGKILL");
        } catch {}
      }
      if (held) rmSync(LOCK, { recursive: true, force: true });
      process.exit(130);
    });
  }
}

async function runOne(script: Script, qaCase: QACase, keep: boolean): Promise<Result> {
  const started = Date.now();
  // Short path: macOS caps Unix socket paths at 104 bytes.
  const folder = mkdtempSync("/tmp/aq.");
  const home = join(folder, "home");
  const ambientHome = join(folder, "a");
  mkdirSync(home);
  const env = {
    PATH: process.env.PATH ?? "/usr/bin:/bin",
    LANG: "en_US.UTF-8",
    TMPDIR: process.env.TMPDIR ?? "/tmp",
    USER: process.env.USER ?? "",
    HOME: home,
    AMBIENT_HOME: ambientHome,
    QA_ROOT: folder,
    QA_APP: APP,
    QA_REPO: ROOT,
    QA_CASE: script.id,
  } as Record<string, string>;

  let release = () => {};
  let app: ReturnType<typeof spawn> | undefined;
  let output = "";
  let code: number | null = null;
  try {
    if (script.needsApp) {
      release = await lock(folder);
      spawnSync("defaults", ["delete", DEFAULTS_DOMAIN], { stdio: "ignore" });
      app = spawn(APP_BIN, [], { env, detached: true, stdio: ["ignore", "ignore", "ignore"] });
      env.QA_APP_PID = String(app.pid);
      runningApp = app.pid;
      if (app.pid) writeFileSync(join(LOCK, "app"), String(app.pid));
      const socket = join(ambientHome, "ambient.sock");
      const end = Date.now() + 15_000;
      while (!(await listening(socket))) {
        if (Date.now() > end) throw new Error("the QA app did not open its socket within 15 s");
        await sleep(200);
      }
    }
    const run = spawnSync("/bin/zsh", [script.path], {
      env,
      cwd: folder,
      encoding: "utf8",
      timeout: script.timeout * 1000,
      maxBuffer: 16 * 1024 * 1024,
    });
    output = `${run.stdout ?? ""}${run.stderr ?? ""}`;
    code = run.error ? null : run.status;
    if (run.error) output += `\n${run.signal === "SIGTERM" ? `timed out after ${script.timeout}s` : run.error.message}`;
  } catch (e) {
    output += `\n${(e as Error).message}`;
    code = null;
  } finally {
    if (app?.pid) {
      try {
        process.kill(-app.pid, "SIGTERM");
      } catch {}
      for (let i = 0; i < 15 && app.exitCode === null && app.signalCode === null; i++) await sleep(200);
      try {
        process.kill(-app.pid, "SIGKILL");
      } catch {}
      runningApp = undefined;
    }
    release();
  }
  const status = classify(code, qaCase.knownGap);
  const keepFolder = keep || status === "fail" || status === "error";
  if (!keepFolder) rmSync(folder, { recursive: true, force: true });
  return {
    id: script.id,
    title: qaCase.title,
    priority: qaCase.priority,
    status,
    partial: script.partial,
    seconds: (Date.now() - started) / 1000,
    output: output.trim(),
    folder: keepFolder ? folder : undefined,
  };
}

const MARK: Record<Status, string> = {
  pass: "✔ pass",
  fail: "✘ FAIL",
  "known-gap": "◌ known gap",
  "gap-fixed": "? gap fixed",
  error: "! ERROR",
};

function summary(results: Result[], started: string): string {
  const count = (s: Status) => results.filter((r) => r.status === s).length;
  const lines = [
    `# Ambient QA run, ${started}`,
    "",
    `${results.length} scripted cases on this Mac: ${count("pass")} passed, ${count("fail")} failed, ` +
      `${count("error")} errors, ${count("known-gap")} known gaps confirmed, ${count("gap-fixed")} known gaps now passing.`,
    "",
    "Cases marked *part* are scripted only in part; a person still checks the rest of their expected results.",
    "",
    "| Case | Priority | Result | Checked | Seconds |",
    "|---|---|---|---|---|",
    ...results.map(
      (r) => `| ${r.id} ${r.title} | ${r.priority} | ${MARK[r.status]} | ${r.partial ? "part" : "all"} | ${r.seconds.toFixed(1)} |`,
    ),
  ];
  const bad = results.filter((r) => r.status !== "pass");
  if (bad.length) {
    lines.push("", "## Details");
    for (const r of bad) {
      lines.push("", `### ${r.id} · ${MARK[r.status]}`, "", "```", r.output.slice(-2000) || "(no output)", "```");
      if (r.folder) lines.push(`Folder kept: \`${r.folder}\``);
    }
  }
  return lines.join("\n");
}

async function main(argv: string[]): Promise<number> {
  if (process.platform !== "darwin") {
    console.error("QA cases run on macOS.");
    return 2;
  }
  const keep = argv.includes("--keep");
  const areaAt = argv.indexOf("--area");
  const area = areaAt >= 0 ? argv[areaAt + 1] : undefined;
  const changedAt = argv.indexOf("--changed");
  const ids = argv.filter((a, i) => /^[A-Z]{2,5}-\d{3}$/.test(a) && argv[i - 1] !== "--area");

  const cases = loadCases();
  let scripts = loadScripts();
  for (const s of scripts) {
    if (!cases.has(s.id)) {
      console.error(`${s.path}: no case ${s.id} in qa/cases`);
      return 2;
    }
  }
  if (ids.length) scripts = scripts.filter((s) => ids.includes(s.id));
  if (area) scripts = scripts.filter((s) => s.id.startsWith(`${area}-`));
  if (argv.includes("--skip-slow")) scripts = scripts.filter((s) => !s.slow);
  if (changedAt >= 0) {
    const base = argv[changedAt + 1] ?? "origin/main";
    const changed = spawnSync("git", ["diff", "--name-only", `${base}...HEAD`], { cwd: ROOT, encoding: "utf8" })
      .stdout.split("\n")
      .filter(Boolean);
    const picked = new Set(select([...cases.values()], changed).selected.map((s) => s.qaCase.id));
    scripts = scripts.filter((s) => picked.has(s.id));
  }
  if (!scripts.length) {
    console.log("No scripted cases match.");
    return 0;
  }
  if (scripts.some((s) => s.needsApp) && !existsSync(APP_BIN)) {
    console.error("No build/AmbientQA.app. Run scripts/build-app.sh, then qa/run/make-qa-app.sh.");
    return 2;
  }

  // An app a cancelled run left behind keeps showing its test's alerts in the menu bar until it's stopped.
  await clearStaleLock(LOCK);
  stopOnSignal();
  const started = new Date().toISOString().replace(/\..*/, "").replace("T", " ");
  const results: Result[] = [];
  for (const s of scripts) {
    const r = await runOne(s, cases.get(s.id)!, keep);
    results.push(r);
    console.log(`${MARK[r.status].padEnd(12)} ${r.id}${r.partial ? " (part)" : ""}  ${r.title}  (${r.seconds.toFixed(1)}s)`);
    if (r.status === "fail" || r.status === "error") {
      console.log(r.output.split("\n").slice(-6).map((l) => `             ${l}`).join("\n"));
    }
  }
  const out = join(RESULTS_DIR, started.replace(/[ :]/g, "-"));
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "results.json"), JSON.stringify(results, null, 2));
  const plist = join(APP, "Contents/Info.plist");
  const plistValue = (key: string) =>
    existsSync(plist)
      ? spawnSync("/usr/libexec/PlistBuddy", ["-c", `Print :${key}`, plist], { encoding: "utf8" }).stdout.trim()
      : "";
  const gitOut = (...a: string[]) => spawnSync("git", a, { cwd: ROOT, encoding: "utf8" }).stdout.trim();
  const run: RunInfo = {
    started,
    finished: new Date().toISOString().replace(/\..*/, "").replace("T", " "),
    commit: gitOut("rev-parse", "--short", "HEAD"),
    branch: gitOut("rev-parse", "--abbrev-ref", "HEAD"),
    version: plistValue("CFBundleShortVersionString"),
    build: plistValue("CFBundleVersion"),
    host: spawnSync("scutil", ["--get", "ComputerName"], { encoding: "utf8" }).stdout.trim(),
    selection: argv.filter((a) => a !== "--keep").join(" ") || "all scripted cases",
    totalCases: cases.size,
    scriptedCases: loadScripts().length,
    context: process.env.QA_CONTEXT || undefined,
    runUrl: process.env.QA_RUN_URL || undefined,
  };
  writeFileSync(join(out, "run.json"), JSON.stringify(run, null, 2));
  writeFileSync(join(out, "summary.md"), summary(results, started));
  console.log(`\nResults: ${join(out, "summary.md")}`);
  return results.some((r) => r.status === "fail" || r.status === "error") ? 1 : 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}
