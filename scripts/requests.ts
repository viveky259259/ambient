// The feature-request board from the terminal, using the Netlify CLI's login and the linked site.
import { getStore } from "@netlify/blobs";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { Store } from "../netlify/edge-functions/lib/requests-api.ts";
import { isStatus, type BoardItem } from "../netlify/edge-functions/lib/requests-core.ts";
import { createdSince, listBoard, merge, printable, pruneLimits, purge, remove, setStatus } from "./requests-admin.ts";

const root = join(import.meta.dirname, "..");
const lastSeenFile = join(root, ".netlify", "requests-last-seen");
const usage = "Usage: requests.sh new | list | remove <id> | merge <id> <into> | status <id> <open|planned|in-progress|shipped> | purge <id> | prune [--all]";

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

function credentials() {
  const siteID = JSON.parse(readFileSync(join(root, ".netlify", "state.json"), "utf8")).siteId as string | undefined;
  let token = process.env.NETLIFY_AUTH_TOKEN;
  if (!token) {
    const config = JSON.parse(readFileSync(join(homedir(), "Library/Preferences/netlify/config.json"), "utf8"));
    token = config.users?.[config.userId]?.auth?.token;
  }
  if (!siteID || !token) fail("Run `netlify login` and `netlify link` first.");
  return { siteID, token };
}

function print(items: BoardItem[]) {
  if (!items.length) return console.log("No requests.");
  for (const i of items) {
    console.log(`${String(i.votes).padStart(4)}  ${i.id}  ${i.status.padEnd(11)}  ${printable(i.title)}`);
    if (i.details) console.log(`${" ".repeat(29)}${printable(i.details)}`);
  }
}

const [command, a, b] = process.argv.slice(2);
const need = (value: string | undefined) => value ?? fail(usage);
const store = getStore({ name: "requests", ...credentials() }) as unknown as Store;

try {
  await run();
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}

async function run() {
  switch (command) {
    case "new": {
      const since = existsSync(lastSeenFile) ? readFileSync(lastSeenFile, "utf8").trim() : "1970-01-01T00:00:00.000Z";
      const fresh = createdSince(await listBoard(store), since);
      console.log(fresh.length ? `${fresh.length} new since ${since}:` : `Nothing new since ${since}.`);
      if (fresh.length) print(fresh);
      writeFileSync(lastSeenFile, new Date().toISOString());
      await pruneLimits(store, new Date());
      break;
    }
    case "list":
      print(await listBoard(store));
      break;
    case "remove":
      await remove(store, need(a));
      console.log(`Removed ${a}.`);
      break;
    case "merge":
      await merge(store, need(a), need(b));
      console.log(`Merged ${a} into ${b}.`);
      break;
    case "status":
      if (!isStatus(b)) fail(usage);
      await setStatus(store, need(a), b);
      console.log(`${a} is now ${b}.`);
      break;
    case "purge":
      await purge(store, need(a));
      console.log(`Deleted ${a} and its votes.`);
      break;
    case "prune":
      console.log(`Deleted ${await pruneLimits(store, new Date(), a === "--all")} limit records.`);
      break;
    default:
      fail(usage);
  }
}
