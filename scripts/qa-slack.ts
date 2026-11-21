// Posts a QA run's summary to Slack (#ambient-qa) as the Ocean Slack app ("Ocean Assurance").
//
//   node scripts/qa-slack.ts            print the message for the latest run (nothing is sent)
//   node scripts/qa-slack.ts --send     send it
//   node scripts/qa-slack.ts --run build/qa-results/<time> [--send]
//
// It uses the one Ocean Slack app every Ocean tool posts through, not a webhook of its own: the
// app's bot token is read from ~/.config/ocean-slack/slack-bot-token (0600, never printed). The app
// must be in the channel (/invite @Ocean Assurance). AMBIENT_QA_SLACK_CHANNEL overrides the channel
// name; AMBIENT_QA_DASHBOARD_URL, if set, is linked from the message.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadRuns, type Run } from "./qa-dashboard.ts";
import type { Result } from "./qa-run.ts";

const TOKEN_FILE = join(homedir(), ".config/ocean-slack/slack-bot-token");
const CHANNEL = process.env.AMBIENT_QA_SLACK_CHANNEL ?? "#ambient-qa";
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
  const what = run.info.context ? ` · ${run.info.context}` : "";
  const head =
    `${icon} *Ambient QA*${what} · ${run.info.version ?? ""} build ${run.info.build ?? "?"} · \`${run.info.commit ?? "?"}\`\n` +
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
            text: `<${dashboard}|Dashboard>${run.info.runUrl ? ` · <${run.info.runUrl}|Run log>` : ""} · ${run.info.started} UTC on ${run.info.host ?? "the QA Mac"} · cases needing a person are not in this run`,
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
  let token: string;
  try {
    token = readFileSync(TOKEN_FILE, "utf8").trim();
  } catch {
    console.error(`No Ocean Slack bot token at ${TOKEN_FILE}.`);
    return 2;
  }
  if (!token.startsWith("xoxb-")) {
    console.error(`${TOKEN_FILE} does not hold a bot token (xoxb-…).`);
    return 2;
  }
  const slack = async (method: string, body?: object) => {
    const res = await fetch(`https://slack.com/api/${method}`, {
      method: body ? "POST" : "GET",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json; charset=utf-8" },
      body: body ? JSON.stringify(body) : undefined,
    });
    return (await res.json()) as { ok: boolean; error?: string; channels?: { id: string; name: string; is_member: boolean }[] };
  };
  const name = CHANNEL.replace(/^#/, "");
  const list = await slack("conversations.list?types=public_channel,private_channel&exclude_archived=true&limit=1000");
  const channel = list.channels?.find((c) => c.name === name);
  if (!list.ok || !channel) {
    console.error(
      list.ok
        ? `The Ocean Slack app can't see #${name}. Create it in the app's workspace, or, if it is private, invite the app: /invite @Ocean Assurance`
        : `Slack refused to list channels: ${list.error}`,
    );
    return 2;
  }
  if (!channel.is_member) {
    console.error(`The Ocean Slack app is not in #${name}. In Slack, open #${name} and type: /invite @Ocean Assurance`);
    return 2;
  }
  const posted = await slack("chat.postMessage", { channel: channel.id, ...payload, unfurl_links: false });
  if (!posted.ok) {
    console.error(`Slack refused the message: ${posted.error}`);
    return 1;
  }
  console.log(`Posted run ${runs[index].dir} to #${name}.`);
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}

