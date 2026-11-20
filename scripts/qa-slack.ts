// Posts a QA run's summary to Slack (#ambient-qa) through an incoming webhook.
//
//   node scripts/qa-slack.ts            print the message for the latest run (nothing is sent)
//   node scripts/qa-slack.ts --send     send it
//   node scripts/qa-slack.ts --run build/qa-results/<time> [--send]
//
// The webhook URL is read from this Mac's login Keychain, never from a file:
//   security add-generic-password -U -s ambient-qa-slack-webhook -a "$USER" -w
// (paste the URL Slack gave for #ambient-qa when asked). AMBIENT_QA_DASHBOARD_URL, if set, is
// linked from the message.

import { spawnSync } from "node:child_process";
import { basename, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadRuns, type Run } from "./qa-dashboard.ts";
import type { Result } from "./qa-run.ts";

const KEYCHAIN_SERVICE = "ambient-qa-slack-webhook";
const DEFAULT_DASHBOARD = "https://docket.tail823fd6.ts.net/p/ambient/d/build/qa-dashboard/index.html";

const bad = (r: Result) => r.status === "fail" || r.status === "error";

/** Compares a run with each case's previous result in older runs. */
export function changes(run: Run, older: Run[]) {
  const previous = (id: string) => older.flatMap((o) => o.results.filter((r) => r.id === id))[0];
  const failing = run.results.filter(bad);
  return {
    newlyFailing: failing.filter((r) => {
      const p = previous(r.id);
      return !p || !bad(p);
    }),
    stillFailing: failing.filter((r) => {
      const p = previous(r.id);
      return p && bad(p);
    }),
    fixed: run.results.filter((r) => r.status === "pass" && (() => {
      const p = previous(r.id);
      return p && bad(p);
    })()),
    gapFixed: run.results.filter((r) => r.status === "gap-fixed"),
  };
}

export function message(run: Run, older: Run[], dashboard: string) {
  const n = (s: Result["status"]) => run.results.filter((r) => r.status === s).length;
  const c = changes(run, older);
  const failCount = n("fail") + n("error");
  const icon = failCount ? ":red_circle:" : ":large_green_circle:";
  const head =
    `${icon} *Ambient QA* · ${run.info.version ?? ""} build ${run.info.build ?? "?"} · \`${run.info.commit ?? "?"}\`\n` +
    `${run.results.length} scripted cases: *${n("pass")} passed*, *${failCount} failed*, ${n("known-gap")} known gaps` +
    (run.info.selection && run.info.selection !== "all scripted cases" ? ` (${run.info.selection})` : "");
  const list = (title: string, rs: Result[]) =>
    rs.length
      ? `*${title}*\n` +
        rs
          .slice(0, 10)
          .map((r) => `• \`${r.id}\` ${r.priority} ${r.title}`)
          .join("\n") +
        (rs.length > 10 ? `\n…and ${rs.length - 10} more` : "")
      : "";
  const sections = [
    list("Newly failing", c.newlyFailing),
    list("Still failing", c.stillFailing),
    list("Fixed since last run", c.fixed),
    list("Known gaps now passing (update the case)", c.gapFixed),
  ].filter(Boolean);
  const text = `${head}\n${sections.join("\n")}`.trim();
  return {
    text,
    blocks: [
      { type: "section", text: { type: "mrkdwn", text: head } },
      ...sections.map((s) => ({ type: "section", text: { type: "mrkdwn", text: s } })),
      {
        type: "context",
        elements: [
          {
            type: "mrkdwn",
            text: `<${dashboard}|Dashboard> · ${run.info.started} UTC on ${run.info.host ?? "the QA Mac"} · cases needing a person are not in this run`,
          },
        ],
      },
    ],
  };
}

async function main(argv: string[]): Promise<number> {
  const runs = loadRuns();
  const at = argv.indexOf("--run");
  const wanted = at >= 0 ? basename(argv[at + 1] ?? "") : undefined;
  const index = wanted ? runs.findIndex((r) => r.dir === wanted) : 0;
  if (index < 0 || !runs[index]) {
    console.error(wanted ? `No run ${wanted} in build/qa-results.` : "No runs in build/qa-results yet.");
    return 2;
  }
  const payload = message(runs[index], runs.slice(index + 1), process.env.AMBIENT_QA_DASHBOARD_URL ?? DEFAULT_DASHBOARD);
  if (!argv.includes("--send")) {
    console.log(payload.text);
    console.log("\n(dry run: pass --send to post it to Slack)");
    return 0;
  }
  const key = spawnSync("security", ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"], { encoding: "utf8" });
  const url = key.stdout.trim();
  if (key.status !== 0 || !url.startsWith("https://hooks.slack.com/")) {
    console.error(
      `No Slack webhook in the Keychain. Add the one for #ambient-qa with:\n  security add-generic-password -U -s ${KEYCHAIN_SERVICE} -a "$USER" -w`,
    );
    return 2;
  }
  const res = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload) });
  if (!res.ok) {
    console.error(`Slack refused the message: ${res.status} ${await res.text()}`);
    return 1;
  }
  console.log(`Posted run ${runs[index].dir} to Slack.`);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}

