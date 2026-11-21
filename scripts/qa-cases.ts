// QA cases: parse qa/cases/*.md, pick the cases a change touches, and check the suite.
//
//   node scripts/qa-cases.ts select --base origin/main [--format text|markdown|json] [--with-p0]
//   node scripts/qa-cases.ts select --files a.swift b.swift
//   node scripts/qa-cases.ts check
//
// The case format is defined in qa/README.md. No dependencies beyond Node.

import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export type Priority = "P0" | "P1" | "P2";
export type CaseType = "manual" | "automated" | "both";

export interface QACase {
  id: string;
  title: string;
  file: string;
  line: number;
  priority: Priority;
  type: CaseType;
  covers: string[];
  automatedBy: string[];
  needs: string;
  knownGap: boolean;
}

export interface ParseResult {
  cases: QACase[];
  errors: string[];
}

/** Folders whose files must each be covered by at least one case. */
export const CODE_ROOTS = ["Sources/", "Drivers/", "Voice/Sources/", "Resources/"];

const HEADING = /^###\s+([A-Z]{2,5}-\d{3})\s+·\s+(.+?)\s*$/;
const FIELD = /^-\s+\*\*(Priority|Type|Covers|Automated by|Needs):\*\*\s*(.*)$/;
const PRIORITIES = new Set(["P0", "P1", "P2"]);
const TYPES = new Set(["manual", "automated", "both"]);

function backticked(text: string): string[] {
  return [...text.matchAll(/`([^`]+)`/g)].map((m) => m[1].trim()).filter(Boolean);
}

export function parseCases(markdown: string, file: string): ParseResult {
  const cases: QACase[] = [];
  const errors: string[] = [];
  const lines = markdown.split("\n");
  let current: (Partial<QACase> & { seen: Set<string> }) | null = null;

  const finish = () => {
    if (!current) return;
    const where = `${file}:${current.line} ${current.id}`;
    for (const f of ["Priority", "Type", "Covers", "Automated by", "Needs"]) {
      if (!current.seen.has(f)) errors.push(`${where}: missing **${f}:**`);
    }
    if (current.seen.has("Covers") && current.covers!.length === 0) {
      errors.push(`${where}: **Covers:** names no path in backticks`);
    }
    const { seen: _seen, ...rest } = current;
    cases.push({
      priority: "P2",
      type: "manual",
      covers: [],
      automatedBy: [],
      needs: "",
      knownGap: false,
      ...rest,
    } as QACase);
    current = null;
  };

  lines.forEach((text, i) => {
    const heading = HEADING.exec(text);
    if (heading) {
      finish();
      current = { id: heading[1], title: heading[2], file, line: i + 1, seen: new Set() };
      return;
    }
    if (/^#{1,3}\s/.test(text)) {
      finish();
      if (/^###\s/.test(text)) errors.push(`${file}:${i + 1}: level-3 heading is not a case id: ${text}`);
      return;
    }
    if (!current) return;
    if (/^\*\*Known gap:\*\*/.test(text.trim()) || /^-\s+\*\*Known gap:\*\*/.test(text)) {
      current.knownGap = true;
      return;
    }
    const field = FIELD.exec(text);
    if (!field) return;
    const [, name, value] = field;
    current.seen.add(name);
    const where = `${file}:${i + 1} ${current.id}`;
    if (name === "Priority") {
      if (!PRIORITIES.has(value.trim())) errors.push(`${where}: priority "${value}" is not P0, P1 or P2`);
      current.priority = value.trim() as Priority;
    } else if (name === "Type") {
      if (!TYPES.has(value.trim())) errors.push(`${where}: type "${value}" is not manual, automated or both`);
      current.type = value.trim() as CaseType;
    } else if (name === "Covers") {
      current.covers = backticked(value);
    } else if (name === "Automated by") {
      current.automatedBy = value.trim() === "none" ? [] : backticked(value);
    } else {
      current.needs = value.trim();
    }
  });
  finish();
  return { cases, errors };
}

/** `*` stays inside one folder, `**` crosses folders, a trailing `/` means the whole folder. */
export function globToRegExp(glob: string): RegExp {
  const g = glob.endsWith("/") ? `${glob}**` : glob;
  let out = "";
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === "*" && g[i + 1] === "*") {
      if (g[i + 2] === "/") {
        out += "(?:.*/)?";
        i += 2;
      } else {
        out += ".*";
        i += 1;
      }
    } else if (c === "*") out += "[^/]*";
    else if (c === "?") out += "[^/]";
    else out += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  }
  return new RegExp(`^${out}$`);
}

export function matches(globs: string[], file: string): string | undefined {
  return globs.find((g) => globToRegExp(g).test(file));
}

export function isCode(file: string): boolean {
  return CODE_ROOTS.some((root) => file.startsWith(root));
}

export interface Selection {
  selected: { qaCase: QACase; files: string[]; reason: "changed" | "P0" }[];
  uncovered: string[];
  ignored: string[];
}

export function select(cases: QACase[], changed: string[], withP0 = false): Selection {
  const selected: Selection["selected"] = [];
  const covered = new Set<string>();
  for (const qaCase of cases) {
    const files = changed.filter((f) => matches(qaCase.covers, f));
    files.forEach((f) => covered.add(f));
    if (files.length) selected.push({ qaCase, files, reason: "changed" });
    else if (withP0 && qaCase.priority === "P0") selected.push({ qaCase, files: [], reason: "P0" });
  }
  const order = { P0: 0, P1: 1, P2: 2 };
  selected.sort(
    (a, b) => order[a.qaCase.priority] - order[b.qaCase.priority] || a.qaCase.id.localeCompare(b.qaCase.id),
  );
  return {
    selected,
    uncovered: changed.filter((f) => isCode(f) && !covered.has(f)),
    ignored: changed.filter((f) => !isCode(f) && !covered.has(f)),
  };
}

export interface CheckInput {
  cases: QACase[];
  parseErrors: string[];
  repoFiles: string[];
  testSource: string;
}

export function check({ cases, parseErrors, repoFiles, testSource }: CheckInput): string[] {
  const errors = [...parseErrors];
  const seen = new Map<string, QACase>();
  for (const c of cases) {
    const prior = seen.get(c.id);
    if (prior) errors.push(`${c.file}:${c.line}: duplicate id ${c.id} (first at ${prior.file}:${prior.line})`);
    seen.set(c.id, c);
    for (const glob of c.covers) {
      if (!repoFiles.some((f) => globToRegExp(glob).test(f))) {
        errors.push(`${c.file}:${c.line} ${c.id}: Covers \`${glob}\` matches no file in the repository`);
      }
    }
    for (const name of c.automatedBy) {
      const leaf = name.split(/[./]/).filter(Boolean).pop()!.replace(/\(.*$/, "");
      if (!new RegExp(`\\b${leaf.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(testSource)) {
        errors.push(`${c.file}:${c.line} ${c.id}: Automated by \`${name}\` is not found in Tests/`);
      }
    }
  }
  const globs = cases.flatMap((c) => c.covers);
  for (const f of repoFiles.filter(isCode)) {
    if (!matches(globs, f)) errors.push(`no QA case covers ${f}`);
  }
  return errors;
}

// ---- command line ----------------------------------------------------------------------------

const ROOT = resolve(fileURLToPath(import.meta.url), "../..");
const CASES_DIR = join(ROOT, "qa/cases");

function git(...args: string[]): string {
  return execFileSync("git", args, { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
}

function loadCases(): ParseResult {
  const all: ParseResult = { cases: [], errors: [] };
  for (const name of readdirSync(CASES_DIR).filter((n) => n.endsWith(".md")).sort()) {
    const file = relative(ROOT, join(CASES_DIR, name));
    const { cases, errors } = parseCases(readFileSync(join(CASES_DIR, name), "utf8"), file);
    all.cases.push(...cases);
    all.errors.push(...errors);
  }
  return all;
}

/** Swift tests under Tests/, plus the speaker driver's C tests (Drivers/AmbientSpeaker/Tests.c). */
function readTests(): string {
  return git("ls-files", "Tests", "Drivers")
    .split("\n")
    .filter((f) => (f.startsWith("Tests/") && f.endsWith(".swift")) || /^Drivers\/.*\/Tests[^/]*\.c$/.test(f))
    .map((f) => readFileSync(join(ROOT, f), "utf8"))
    .join("\n");
}

function render(sel: Selection, format: string): string {
  if (format === "json") {
    return JSON.stringify(
      {
        selected: sel.selected.map(({ qaCase, files, reason }) => ({ ...qaCase, reason, files })),
        uncovered: sel.uncovered,
        ignored: sel.ignored,
      },
      null,
      2,
    );
  }
  const out: string[] = [];
  const manual = sel.selected.filter((s) => s.qaCase.type !== "automated").length;
  if (format === "markdown") {
    // In CI the summary is shown outside the repository, so links there need the full blob URL.
    const { GITHUB_SERVER_URL: server, GITHUB_REPOSITORY: repo, GITHUB_SHA: sha } = process.env;
    const link = (c: QACase) => (server && repo && sha ? `${server}/${repo}/blob/${sha}/${c.file}#L${c.line}` : `${c.file}#L${c.line}`);
    out.push(`## QA cases for this change`, "");
    out.push(
      `${sel.selected.length} cases (${manual} need a person). Picked because the change touches the code each case covers.`,
      "",
    );
    out.push("| Case | Priority | Type | Why |", "|---|---|---|---|");
    for (const { qaCase: c, files, reason } of sel.selected) {
      const why = reason === "P0" ? "every release (P0)" : files.map((f) => `\`${f}\``).join(", ");
      const gap = c.knownGap ? " (known gap)" : "";
      out.push(`| [${c.id}](${link(c)}) ${c.title}${gap} | ${c.priority} | ${c.type} | ${why} |`);
    }
    out.push("", `### Changed, no QA case`, "");
    out.push(sel.uncovered.length ? sel.uncovered.map((f) => `- \`${f}\``).join("\n") : "None.");
    out.push(
      "",
      "These cases are what the change reaches through the files each case names. They are not a complete list, and passing them does not mean the change is safe.",
    );
    return out.join("\n");
  }
  out.push(`${sel.selected.length} QA cases (${manual} need a person):`);
  for (const { qaCase: c, files, reason } of sel.selected) {
    out.push(`  ${c.id}  ${c.priority} ${c.type.padEnd(9)} ${c.title}${c.knownGap ? "  [known gap]" : ""}`);
    out.push(`         ${reason === "P0" ? "P0, every release" : files.join(", ")}`);
  }
  out.push("", `Changed, no QA case (${sel.uncovered.length}):`);
  sel.uncovered.forEach((f) => out.push(`  ${f}`));
  if (sel.ignored.length) out.push("", `Not product code, ignored: ${sel.ignored.length} files`);
  return out.join("\n");
}

function main(argv: string[]): number {
  const [command, ...rest] = argv;
  const flag = (name: string) => {
    const i = rest.indexOf(name);
    return i >= 0 ? rest[i + 1] : undefined;
  };
  const { cases, errors } = loadCases();

  if (command === "check") {
    const problems = check({
      cases,
      parseErrors: errors,
      repoFiles: git("ls-files").split("\n").filter(Boolean),
      testSource: readTests(),
    });
    const byPriority = (p: Priority) => cases.filter((c) => c.priority === p).length;
    console.log(
      `${cases.length} cases: ${byPriority("P0")} P0, ${byPriority("P1")} P1, ${byPriority("P2")} P2; ` +
        `${cases.filter((c) => c.type !== "automated").length} need a person; ${cases.filter((c) => c.knownGap).length} known gaps.`,
    );
    problems.forEach((p) => console.log(`  ✘ ${p}`));
    console.log(problems.length ? `${problems.length} problems.` : "No problems.");
    return problems.length ? 1 : 0;
  }

  if (command === "select") {
    let changed: string[];
    const filesAt = rest.indexOf("--files");
    if (filesAt >= 0) changed = rest.slice(filesAt + 1).filter((a) => !a.startsWith("--"));
    else {
      const base = flag("--base") ?? "origin/main";
      const head = flag("--head") ?? "HEAD";
      changed = git("diff", "--name-only", `${base}...${head}`).split("\n").filter(Boolean);
    }
    console.log(render(select(cases, changed, rest.includes("--with-p0")), flag("--format") ?? "text"));
    return 0;
  }

  console.error("usage: node scripts/qa-cases.ts select [--base REF] [--head REF] [--files F...] [--format text|markdown|json] [--with-p0]\n       node scripts/qa-cases.ts check");
  return 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
