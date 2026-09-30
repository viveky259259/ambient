# Feature Requests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A public, no-account feature-request board at `https://yaml.cafe/requests/` (suggest, vote, statuses), moderated by a command, and reachable from the Ambient app's menu and settings.

**Architecture:** Pure board logic (`requests-core.ts`) is shared by one Netlify edge function (`/api/requests*`, storage in the Netlify Blobs store `requests`), a Node moderation CLI (`scripts/requests.sh`) and the tests. The page is static HTML with an ES-module script. The app only opens a URL in the default browser.

**Tech Stack:** Netlify Edge Functions (Deno), `@netlify/blobs` 11.1.1, TypeScript run by `tsx` 4.23.15 under Node 20's test runner, vanilla HTML/CSS/JS, Swift 6 with Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-30-feature-requests-design.md`

## Global Constraints

- Page URL `https://yaml.cafe/requests/`; header **What should Ambient bring you next?**; sub-line "Tell us what would make working with your agents better. Anyone can suggest or vote; no account needed."
- Title placeholder "What would you like Ambient to do for you?"; details placeholder "Why it matters to you (optional)"; button **Suggest it**; after posting "Thanks! It's on the board, with your vote."; similar hint "Is it one of these? Vote instead."
- Title 3–80 characters (graphemes), details up to 500; links (`https?://\S+`, `www\.\S+`) removed; whitespace collapsed.
- Limits per network per day: 3 posts, 50 votes. Trap field `website`; `elapsedMs` under 3,000 is automated. Automated posts get a fake 201 and nothing is stored.
- Statuses exactly `open`, `planned`, `in-progress`, `shipped`; labels Open, Planned, In progress, Shipped.
- Blobs store `requests`; keys `items/<id>`, `votes/<id>/<voter>`, `limits/<day>/<network>/<post|vote>/<uuid>`; `<id>` 8 base-36 chars.
- `<voter>` = first 32 hex of SHA-256(`REQUESTS_SECRET` + `:voter:` + voter ID); `<network>` = first 32 hex of SHA-256(`REQUESTS_SECRET` + `:` + day + `:` + client IP). No IP, cookie or email stored.
- `GET /api/requests` cached with `Netlify-CDN-Cache-Control: public, s-maxage=30, stale-while-revalidate=60`.
- App opens `https://yaml.cafe/requests/?from=app&v=<version>` with `NSWorkspace.shared.open`; the app makes no network requests.
- User text is rendered with `textContent` only. Page works at 375 px; Lighthouse 100 in all four categories.
- Another session edits `site/index.html`, `site/styles.css`, `site/scene.js`, `AppDelegate.swift`, `SettingsPane.swift`, `SettingsView.swift` and more. Stage **named files only** (`git add <paths>`), never `git add -A`/`-u`, and don't modify files outside each task's list. Commit on `main` (a branch would move the other session's checkout too).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Production deploys cost 15 Netlify credits each: at most two for this feature.

## Review Focus

- Titles with emoji or ZWJ sequences: "👩‍💻" counts as one character, so 80 of them are accepted and 81 rejected (test in Task 1).
- HTML or script typed as text (`<b>bold</b> <script>`) is stored as typed and shown literally, never interpreted (test in Task 1; browser check in Task 7).
- A merge cycle made by hand in the store (a→b, b→a) must not hang `GET`; both stay hidden (test in Task 1).
- A vote arriving for an item that was merged or removed after the page loaded: merged counts toward the target, removed answers 404 (tests in Task 2).
- Missing `REQUESTS_SECRET` or a failing Blobs store: the API answers JSON 500 with a readable message and the page says "The board couldn't load. Try again in a moment." (tests in Task 2; page check in Task 4).

---

### Task 1: Board logic

**Files:**
- Create: `netlify/edge-functions/lib/requests-core.ts`
- Test: `netlify/edge-functions/lib/requests-core.test.ts`
- Modify: `package.json`, `package-lock.json`

**Interfaces:**
- Consumes: nothing.
- Produces (all exported from `requests-core.ts`):
  - `type Status = "open" | "planned" | "in-progress" | "shipped"`, `STATUSES: readonly Status[]`
  - `interface Item { id: string; title: string; details: string; status: Status; created: string; source: "app" | "site"; version: string; removed?: boolean; mergedInto?: string }`
  - `interface BoardItem { id: string; title: string; details: string; status: Status; created: string; votes: number }`
  - `interface Submission { title: string; details: string; source: "app" | "site"; version: string }`
  - `type Result<T> = { ok: true; value: T } | { ok: false; error: string }`
  - `LIMITS = { post: 3, vote: 50 }`, `TITLE_MIN = 3`, `TITLE_MAX = 80`, `DETAILS_MAX = 500`, `MIN_ELAPSED_MS = 3000`
  - `length(s: string): number`, `cleanText(value: unknown): string`, `validateSubmission(body: unknown): Result<Submission>`, `looksAutomated(body: unknown): boolean`, `limitReached(count: number, kind: "post" | "vote"): boolean`, `isStatus(s: unknown): s is Status`, `newId(random?: () => number): string`, `rootOf(id: string, byId: Map<string, Item>): string`, `board(items: Item[], voteKeys: string[]): BoardItem[]`

- [ ] **Step 1: Add the test runner**

Edit `package.json` to exactly:

```json
{
  "name": "ambient-site-functions",
  "private": true,
  "type": "module",
  "description": "Dependencies for yaml.cafe's Netlify edge functions (netlify/edge-functions) and their tests.",
  "scripts": {
    "test": "node --import tsx --test netlify/edge-functions/lib/*.test.ts scripts/*.test.ts site/requests/*.test.mjs"
  },
  "dependencies": {
    "@netlify/blobs": "11.1.1"
  },
  "devDependencies": {
    "tsx": "4.23.15"
  }
}
```

Run: `npm install`
Expected: `package-lock.json` updated, `node_modules/tsx` present.

- [ ] **Step 2: Write the failing tests**

Create `netlify/edge-functions/lib/requests-core.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  board, cleanText, isStatus, length, limitReached, looksAutomated, newId, validateSubmission, type Item,
} from "./requests-core.ts";

const item = (id: string, extra: Partial<Item> = {}): Item => ({
  id, title: `Idea ${id}`, details: "", status: "open", created: "2026-10-01T00:00:00.000Z",
  source: "site", version: "", ...extra,
});

test("cleanText removes links, collapses whitespace and trims", () => {
  assert.equal(cleanText("  see https://evil.example/x and www.spam.test  now \n\n ok "), "see and now ok");
  assert.equal(cleanText(42), "");
});

test("cleanText keeps HTML as literal text", () => {
  assert.equal(cleanText("<b>bold</b> <script>x</script>"), "<b>bold</b> <script>x</script>");
});

test("length counts characters as people see them", () => {
  assert.equal(length("👩‍💻👍"), 2);
});

test("validateSubmission accepts a normal idea and normalizes source and version", () => {
  const result = validateSubmission({ title: "Show token usage", details: "per session", source: "app", version: "0.4.0" });
  assert.deepEqual(result, { ok: true, value: { title: "Show token usage", details: "per session", source: "app", version: "0.4.0" } });
  const odd = validateSubmission({ title: "Show token usage", source: "evil", version: "1; DROP" });
  assert.deepEqual(odd, { ok: true, value: { title: "Show token usage", details: "", source: "site", version: "" } });
});

test("validateSubmission rejects titles that are too short, too long or only a link", () => {
  assert.equal(validateSubmission({ title: "ab" }).ok, false);
  assert.equal(validateSubmission({ title: "https://spam.example/buy" }).ok, false);
  assert.equal(validateSubmission({ title: "x".repeat(81) }).ok, false);
  assert.equal(validateSubmission({ title: "ok title", details: "d".repeat(501) }).ok, false);
  assert.equal(validateSubmission(null).ok, false);
});

test("validateSubmission counts emoji as one character each", () => {
  assert.equal(validateSubmission({ title: "👩‍💻".repeat(80) }).ok, true);
  assert.equal(validateSubmission({ title: "👩‍💻".repeat(81) }).ok, false);
});

test("looksAutomated catches the trap field and fast or missing timing", () => {
  assert.equal(looksAutomated({ website: "http://x", elapsedMs: 9000 }), true);
  assert.equal(looksAutomated({ website: "", elapsedMs: 1200 }), true);
  assert.equal(looksAutomated({ website: "" }), true);
  assert.equal(looksAutomated({ website: "", elapsedMs: 3000 }), false);
});

test("limitReached, isStatus and newId", () => {
  assert.equal(limitReached(2, "post"), false);
  assert.equal(limitReached(3, "post"), true);
  assert.equal(limitReached(50, "vote"), true);
  assert.equal(isStatus("in-progress"), true);
  assert.equal(isStatus("done"), false);
  assert.match(newId(), /^[a-z0-9]{8}$/);
});

test("board counts each voter once and sorts by votes, then newest", () => {
  const items = [item("aaaaaaaa"), item("bbbbbbbb", { created: "2026-10-02T00:00:00.000Z" }), item("cccccccc")];
  const votes = ["votes/aaaaaaaa/v1", "votes/aaaaaaaa/v2", "votes/aaaaaaaa/v2", "votes/cccccccc/v1", "votes/zzzzzzzz/v9", "junk"];
  assert.deepEqual(board(items, votes).map((i) => [i.id, i.votes]), [["aaaaaaaa", 2], ["cccccccc", 1], ["bbbbbbbb", 0]]);
});

test("board hides removed and merged items and folds merged voters into the target once", () => {
  const items = [item("aaaaaaaa"), item("bbbbbbbb", { mergedInto: "aaaaaaaa" }), item("cccccccc", { removed: true })];
  const votes = ["votes/aaaaaaaa/v1", "votes/bbbbbbbb/v1", "votes/bbbbbbbb/v2", "votes/cccccccc/v3"];
  assert.deepEqual(board(items, votes), [{ id: "aaaaaaaa", title: "Idea aaaaaaaa", details: "", status: "open", created: "2026-10-01T00:00:00.000Z", votes: 2 }]);
});

test("board survives a merge cycle made by hand", () => {
  const items = [item("aaaaaaaa", { mergedInto: "bbbbbbbb" }), item("bbbbbbbb", { mergedInto: "aaaaaaaa" }), item("cccccccc")];
  assert.deepEqual(board(items, ["votes/aaaaaaaa/v1"]).map((i) => i.id), ["cccccccc"]);
});
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `node --import tsx --test netlify/edge-functions/lib/requests-core.test.ts`
Expected: FAIL, `Cannot find module ... requests-core.ts`.

- [ ] **Step 4: Write the implementation**

Create `netlify/edge-functions/lib/requests-core.ts`:

```ts
// Pure logic for the feature-request board: no I/O and no Netlify APIs, so the edge function,
// the moderation script and the tests all share it.

export type Status = "open" | "planned" | "in-progress" | "shipped";
export const STATUSES: readonly Status[] = ["open", "planned", "in-progress", "shipped"];

export interface Item {
  id: string;
  title: string;
  details: string;
  status: Status;
  created: string;
  source: "app" | "site";
  version: string;
  removed?: boolean;
  mergedInto?: string;
}

export interface BoardItem {
  id: string;
  title: string;
  details: string;
  status: Status;
  created: string;
  votes: number;
}

export interface Submission {
  title: string;
  details: string;
  source: "app" | "site";
  version: string;
}

export type Result<T> = { ok: true; value: T } | { ok: false; error: string };

export const LIMITS = { post: 3, vote: 50 } as const;
export const TITLE_MIN = 3;
export const TITLE_MAX = 80;
export const DETAILS_MAX = 500;
export const MIN_ELAPSED_MS = 3000;

const LINKS = /https?:\/\/\S+|www\.\S+/gi;
const VERSION = /^\d+(\.\d+){0,3}$/;
const graphemes = new Intl.Segmenter("en", { granularity: "grapheme" });

const fields = (body: unknown): Record<string, unknown> =>
  body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : {};

/** Characters as people count them: "👩‍💻" is one. */
export const length = (s: string): number => [...graphemes.segment(s)].length;

/** Removes links, collapses whitespace and trims. Anything that isn't a string becomes "". */
export function cleanText(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.replace(LINKS, " ").replace(/\s+/g, " ").trim();
}

export function validateSubmission(body: unknown): Result<Submission> {
  const b = fields(body);
  const title = cleanText(b.title);
  const details = cleanText(b.details);
  if (length(title) < TITLE_MIN) return { ok: false, error: `Give your idea a title of at least ${TITLE_MIN} characters.` };
  if (length(title) > TITLE_MAX) return { ok: false, error: `Keep the title to ${TITLE_MAX} characters; there's room for more in the details.` };
  if (length(details) > DETAILS_MAX) return { ok: false, error: `Keep the details to ${DETAILS_MAX} characters.` };
  const version = typeof b.version === "string" && VERSION.test(b.version) ? b.version : "";
  return { ok: true, value: { title, details, source: b.source === "app" ? "app" : "site", version } };
}

/** The hidden trap field was filled, or the form went faster than a person types. */
export function looksAutomated(body: unknown): boolean {
  const b = fields(body);
  if (typeof b.website === "string" && b.website.trim() !== "") return true;
  return !(typeof b.elapsedMs === "number" && b.elapsedMs >= MIN_ELAPSED_MS);
}

export const limitReached = (count: number, kind: keyof typeof LIMITS): boolean => count >= LIMITS[kind];

export const isStatus = (s: unknown): s is Status => typeof s === "string" && (STATUSES as readonly string[]).includes(s);

export function newId(random: () => number = Math.random): string {
  let id = "";
  for (let i = 0; i < 8; i++) id += Math.floor(random() * 36).toString(36);
  return id;
}

/** Where an item's votes land: follows mergedInto, stopping at a missing target, a cycle or 10 hops. */
export function rootOf(id: string, byId: Map<string, Item>): string {
  const seen = new Set<string>();
  let current = id;
  while (!seen.has(current) && seen.size < 10) {
    seen.add(current);
    const next = byId.get(current)?.mergedInto;
    if (!next || !byId.has(next)) return current;
    current = next;
  }
  return current;
}

/** The public board: visible items, each voter counted once, merged duplicates folded in, most votes first. */
export function board(items: Item[], voteKeys: string[]): BoardItem[] {
  const byId = new Map(items.map((i) => [i.id, i]));
  const voters = new Map<string, Set<string>>();
  for (const key of voteKeys) {
    const [prefix, id, voter] = key.split("/");
    if (prefix !== "votes" || !id || !voter || !byId.has(id)) continue;
    const root = rootOf(id, byId);
    if (!voters.has(root)) voters.set(root, new Set());
    voters.get(root)!.add(voter);
  }
  return items
    .filter((i) => !i.removed && !i.mergedInto)
    .map(({ id, title, details, status, created }) => ({ id, title, details, status, created, votes: voters.get(id)?.size ?? 0 }))
    .sort((a, b) => b.votes - a.votes || b.created.localeCompare(a.created));
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `node --import tsx --test netlify/edge-functions/lib/requests-core.test.ts`
Expected: all PASS. (`npm test` covers every test folder and works from Task 4 on, once each folder has a test.)

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json netlify/edge-functions/lib/requests-core.ts netlify/edge-functions/lib/requests-core.test.ts
git commit -m "feat(site): feature-request board logic with tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The API (edge function)

**Files:**
- Create: `netlify/edge-functions/lib/requests-api.ts`, `netlify/edge-functions/lib/memory-store.ts`, `netlify/edge-functions/requests.ts`
- Test: `netlify/edge-functions/lib/requests-api.test.ts`
- Modify: `netlify/edge-functions/markdown.ts` (config `excludedPath` only)

**Interfaces:**
- Consumes: everything from Task 1's `requests-core.ts`.
- Produces:
  - `requests-api.ts`: `interface Store { get(key: string, options: { type: "json" }): Promise<unknown>; setJSON(key: string, value: unknown): Promise<unknown>; set(key: string, value: string): Promise<unknown>; delete(key: string): Promise<unknown>; list(options: { prefix: string }): Promise<{ blobs: { key: string }[] }> }`, `interface Deps { store: Store; secret: string | undefined; ip: string; now: Date }`, `handle(request: Request, deps: Deps): Promise<Response>`, `loadItems(store: Store): Promise<Item[]>`
  - `memory-store.ts`: `class MemoryStore implements Store` with a public `data: Map<string, string>`
  - HTTP: `GET /api/requests` → `200 { items: BoardItem[] }`; `POST /api/requests` → `201 { item: BoardItem }` | `400|429|500 { error: string }`; `POST|DELETE /api/requests/<id>/vote` → `200 { votes: number }` | `400|404|429 { error }`

- [ ] **Step 1: Write the in-memory store used by tests**

Create `netlify/edge-functions/lib/memory-store.ts`:

```ts
// A Netlify Blobs stand-in for tests: the same calls, kept in a Map.
import type { Store } from "./requests-api.ts";

export class MemoryStore implements Store {
  data = new Map<string, string>();
  async get(key: string) { const value = this.data.get(key); return value === undefined ? null : JSON.parse(value); }
  async setJSON(key: string, value: unknown) { this.data.set(key, JSON.stringify(value)); }
  async set(key: string, value: string) { this.data.set(key, value); }
  async delete(key: string) { this.data.delete(key); }
  async list({ prefix }: { prefix: string }) {
    return { blobs: [...this.data.keys()].filter((k) => k.startsWith(prefix)).sort().map((key) => ({ key })) };
  }
}
```

- [ ] **Step 2: Write the failing tests**

Create `netlify/edge-functions/lib/requests-api.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { handle, type Deps } from "./requests-api.ts";
import { MemoryStore } from "./memory-store.ts";

const NOW = new Date("2026-10-01T12:00:00Z");
const deps = (extra: Partial<Deps> = {}): Deps => ({ store: new MemoryStore(), secret: "test-secret", ip: "203.0.113.7", now: NOW, ...extra });
const call = (d: Deps, method: string, path: string, body?: unknown) =>
  handle(new Request(`https://yaml.cafe${path}`, {
    method, headers: { "Content-Type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body),
  }), d);
const idea = (extra: Record<string, unknown> = {}) => ({
  title: "Show token usage per session", details: "", source: "site", version: "", voter: "voter-aaaa-1111", website: "", elapsedMs: 5000, ...extra,
});
const keys = (d: Deps) => [...(d.store as MemoryStore).data.keys()];

test("GET starts empty and is cached at the edge for 30 seconds", async () => {
  const res = await call(deps(), "GET", "/api/requests");
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { items: [] });
  assert.match(res.headers.get("Netlify-CDN-Cache-Control") ?? "", /s-maxage=30/);
});

test("POST adds a request carrying the poster's vote, and GET shows it", async () => {
  const d = deps();
  const res = await call(d, "POST", "/api/requests", idea({ details: "see https://evil.example now" }));
  assert.equal(res.status, 201);
  const { item } = await res.json();
  assert.equal(item.votes, 1);
  assert.equal(item.details, "see now");
  const board = await (await call(d, "GET", "/api/requests")).json();
  assert.deepEqual(board.items.map((i: { id: string; votes: number }) => [i.id, i.votes]), [[item.id, 1]]);
  assert.ok(keys(d).some((k) => k.startsWith(`votes/${item.id}/`) && !k.includes("voter-aaaa-1111")));
});

test("automated posts get a fake success and nothing is stored", async () => {
  const d = deps();
  assert.equal((await call(d, "POST", "/api/requests", idea({ website: "http://spam" }))).status, 201);
  assert.equal((await call(d, "POST", "/api/requests", idea({ elapsedMs: 800 }))).status, 201);
  assert.deepEqual(keys(d), []);
});

test("invalid ideas and bodies get 400 with a readable message", async () => {
  const d = deps();
  const res = await call(d, "POST", "/api/requests", idea({ title: "ab" }));
  assert.equal(res.status, 400);
  assert.match((await res.json()).error, /at least 3 characters/);
  assert.equal((await call(d, "POST", "/api/requests", idea({ voter: "bad voter!" }))).status, 400);
  const raw = await handle(new Request("https://yaml.cafe/api/requests", { method: "POST", body: "not json" }), d);
  assert.equal(raw.status, 400);
});

test("a network gets 3 posts a day; another network isn't affected", async () => {
  const d = deps();
  for (let i = 0; i < 3; i++) assert.equal((await call(d, "POST", "/api/requests", idea({ title: `Idea number ${i}` }))).status, 201);
  const fourth = await call(d, "POST", "/api/requests", idea({ title: "Idea number 4" }));
  assert.equal(fourth.status, 429);
  assert.match((await fourth.json()).error, /suggested 3 things today/);
  assert.equal((await call({ ...d, ip: "198.51.100.9" }, "POST", "/api/requests", idea({ title: "Idea number 5" }))).status, 201);
});

test("voting is idempotent per voter and can be taken back", async () => {
  const d = deps();
  const { item } = await (await call(d, "POST", "/api/requests", idea())).json();
  const path = `/api/requests/${item.id}/vote`;
  assert.deepEqual(await (await call(d, "POST", path, { voter: "voter-bbbb-2222" })).json(), { votes: 2 });
  assert.deepEqual(await (await call(d, "POST", path, { voter: "voter-bbbb-2222" })).json(), { votes: 2 });
  assert.deepEqual(await (await call(d, "DELETE", path, { voter: "voter-bbbb-2222" })).json(), { votes: 1 });
});

test("a network gets 50 votes a day; repeat votes don't use it up", async () => {
  const d = deps();
  await d.store.setJSON("items/aaaaaaaa", { id: "aaaaaaaa", title: "Idea", details: "", status: "open", created: NOW.toISOString(), source: "site", version: "" });
  for (let i = 0; i < 50; i++) assert.equal((await call(d, "POST", "/api/requests/aaaaaaaa/vote", { voter: `voter-${i}-xxxx` })).status, 200);
  assert.equal((await call(d, "POST", "/api/requests/aaaaaaaa/vote", { voter: "voter-0-xxxx" })).status, 200);
  assert.equal((await call(d, "POST", "/api/requests/aaaaaaaa/vote", { voter: "voter-51-xxxx" })).status, 429);
});

test("votes for merged items count toward the target; removed or unknown items answer 404", async () => {
  const d = deps();
  const base = { details: "", status: "open", created: NOW.toISOString(), source: "site", version: "" };
  await d.store.setJSON("items/aaaaaaaa", { id: "aaaaaaaa", title: "Target", ...base });
  await d.store.setJSON("items/bbbbbbbb", { id: "bbbbbbbb", title: "Duplicate", mergedInto: "aaaaaaaa", ...base });
  await d.store.setJSON("items/cccccccc", { id: "cccccccc", title: "Gone", removed: true, ...base });
  assert.deepEqual(await (await call(d, "POST", "/api/requests/bbbbbbbb/vote", { voter: "voter-cccc-3333" })).json(), { votes: 1 });
  const board = await (await call(d, "GET", "/api/requests")).json();
  assert.deepEqual(board.items.map((i: { id: string; votes: number }) => [i.id, i.votes]), [["aaaaaaaa", 1]]);
  assert.equal((await call(d, "POST", "/api/requests/cccccccc/vote", { voter: "voter-cccc-3333" })).status, 404);
  assert.equal((await call(d, "POST", "/api/requests/zzzzzzzz/vote", { voter: "voter-cccc-3333" })).status, 404);
});

test("no IP address is ever stored", async () => {
  const d = deps();
  await call(d, "POST", "/api/requests", idea());
  const everything = keys(d).join("\n") + [...(d.store as MemoryStore).data.values()].join("\n");
  assert.equal(everything.includes("203.0.113.7"), false);
});

test("a missing secret or a failing store answers JSON 500", async () => {
  const noSecret = await call(deps({ secret: undefined }), "GET", "/api/requests");
  assert.equal(noSecret.status, 500);
  assert.ok((await noSecret.json()).error);
  const broken = new MemoryStore();
  broken.list = async () => { throw new Error("blobs down"); };
  const failing = await call(deps({ store: broken }), "GET", "/api/requests");
  assert.equal(failing.status, 500);
  assert.match((await failing.json()).error, /Try again/);
});

test("unknown paths and methods", async () => {
  assert.equal((await call(deps(), "PUT", "/api/requests")).status, 405);
  assert.equal((await call(deps(), "GET", "/api/requests/aaaaaaaa/vote")).status, 404);
});
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `node --import tsx --test netlify/edge-functions/lib/requests-api.test.ts`
Expected: FAIL, `Cannot find module ... requests-api.ts`.

- [ ] **Step 4: Write the API**

Create `netlify/edge-functions/lib/requests-api.ts`:

```ts
// The feature-request board's HTTP API. Storage and secrets come in as Deps, so the same code runs
// in the edge function (Netlify Blobs) and in tests (MemoryStore).
import {
  board, cleanText, LIMITS, limitReached, looksAutomated, newId, validateSubmission, type Item,
} from "./requests-core.ts";

export interface Store {
  get(key: string, options: { type: "json" }): Promise<unknown>;
  setJSON(key: string, value: unknown): Promise<unknown>;
  set(key: string, value: string): Promise<unknown>;
  delete(key: string): Promise<unknown>;
  list(options: { prefix: string }): Promise<{ blobs: { key: string }[] }>;
}

export interface Deps {
  store: Store;
  secret: string | undefined;
  ip: string;
  now: Date;
}

const VOTER = /^[A-Za-z0-9-]{8,64}$/;
const VOTE_PATH = /^\/api\/requests\/([a-z0-9]{8})\/vote$/;

const json = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers },
  });

async function hash(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

async function readBody(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = await request.json();
    return body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

const voterOf = (body: Record<string, unknown> | null): string | null =>
  body && typeof body.voter === "string" && VOTER.test(body.voter) ? body.voter : null;

export async function loadItems(store: Store): Promise<Item[]> {
  const { blobs } = await store.list({ prefix: "items/" });
  const items = await Promise.all(blobs.map((b) => store.get(b.key, { type: "json" })));
  return items.filter((i): i is Item => !!i && typeof i === "object" && typeof (i as Item).id === "string");
}

async function currentBoard(store: Store) {
  const [items, votes] = await Promise.all([loadItems(store), store.list({ prefix: "votes/" })]);
  return { items, board: board(items, votes.blobs.map((b) => b.key)) };
}

/** Records one use of today's allowance for this network, or says it's used up. */
async function useAllowance(deps: Deps, network: string, kind: keyof typeof LIMITS): Promise<boolean> {
  const prefix = `limits/${deps.now.toISOString().slice(0, 10)}/${network}/${kind}/`;
  const used = (await deps.store.list({ prefix })).blobs.length;
  if (limitReached(used, kind)) return false;
  await deps.store.set(prefix + crypto.randomUUID(), "1");
  return true;
}

async function post(request: Request, deps: Deps, secret: string, network: string): Promise<Response> {
  const body = await readBody(request);
  if (!body) return json(400, { error: "Send the idea as JSON." });
  if (looksAutomated(body)) {
    const title = cleanText(body.title) || "Thanks";
    return json(201, { item: { id: newId(), title, details: cleanText(body.details), status: "open", created: deps.now.toISOString(), votes: 1 } });
  }
  const checked = validateSubmission(body);
  if (!checked.ok) return json(400, { error: checked.error });
  const voter = voterOf(body);
  if (!voter) return json(400, { error: "Missing voter." });
  if (!(await useAllowance(deps, network, "post"))) {
    return json(429, { error: `You've suggested ${LIMITS.post} things today. Thank you! Try again tomorrow.` });
  }
  const item: Item = { id: newId(), ...checked.value, status: "open", created: deps.now.toISOString() };
  await deps.store.setJSON(`items/${item.id}`, item);
  await deps.store.set(`votes/${item.id}/${await hash(`${secret}:voter:${voter}`)}`, "1");
  const { id, title, details, status, created } = item;
  return json(201, { item: { id, title, details, status, created, votes: 1 } });
}

async function vote(request: Request, deps: Deps, secret: string, network: string, id: string): Promise<Response> {
  const voter = voterOf(await readBody(request));
  if (!voter) return json(400, { error: "Missing voter." });
  const target = await deps.store.get(`items/${id}`, { type: "json" }) as Item | null;
  if (!target || target.removed) return json(404, { error: "That request isn't on the board anymore." });
  const key = `votes/${id}/${await hash(`${secret}:voter:${voter}`)}`;
  if (request.method === "POST") {
    if ((await deps.store.get(key, { type: "json" })) === null) {
      if (!(await useAllowance(deps, network, "vote"))) {
        return json(429, { error: "That's a lot of votes for one day. Thank you! Try again tomorrow." });
      }
      await deps.store.set(key, "1");
    }
  } else {
    await deps.store.delete(key);
  }
  const { items, board: visible } = await currentBoard(deps.store);
  let root = id;
  const byId = new Map(items.map((i) => [i.id, i]));
  for (let hops = 0; byId.get(root)?.mergedInto && hops < 10; hops++) root = byId.get(root)!.mergedInto!;
  return json(200, { votes: visible.find((i) => i.id === root)?.votes ?? 0 });
}

async function route(request: Request, deps: Deps): Promise<Response> {
  if (!deps.secret) return json(500, { error: "The board isn't set up yet. Try again in a moment." });
  const secret = deps.secret;
  const path = new URL(request.url).pathname.replace(/\/+$/, "");
  const network = await hash(`${secret}:${deps.now.toISOString().slice(0, 10)}:${deps.ip}`);

  if (path === "/api/requests") {
    if (request.method === "GET") {
      const { board: items } = await currentBoard(deps.store);
      return json(200, { items }, {
        "Cache-Control": "public, max-age=0, must-revalidate",
        "Netlify-CDN-Cache-Control": "public, s-maxage=30, stale-while-revalidate=60",
      });
    }
    if (request.method === "POST") return post(request, deps, secret, network);
    return json(405, { error: "Method not allowed." }, { Allow: "GET, POST" });
  }
  const match = path.match(VOTE_PATH);
  if (match && (request.method === "POST" || request.method === "DELETE")) return vote(request, deps, secret, network, match[1]);
  return json(404, { error: "Not found." });
}

export async function handle(request: Request, deps: Deps): Promise<Response> {
  try {
    return await route(request, deps);
  } catch (error) {
    console.error("feature requests failed", error);
    return json(500, { error: "Something went wrong. Try again in a moment." });
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `node --import tsx --test netlify/edge-functions/lib/requests-api.test.ts`
Expected: all PASS.

- [ ] **Step 6: Wire the edge function and keep the Markdown function off `/api`**

Create `netlify/edge-functions/requests.ts`:

```ts
// The feature-request board's API at /api/requests (see lib/requests-api.ts). Votes and requests live
// in the Netlify Blobs store "requests"; REQUESTS_SECRET keys the one-way hashes for voters and networks.
import { getStore } from "@netlify/blobs";
import type { Config, Context } from "https://edge.netlify.com";
import { handle, type Store } from "./lib/requests-api.ts";

export default (request: Request, context: Context) =>
  handle(request, {
    store: getStore({ name: "requests", consistency: "strong" }) as unknown as Store,
    secret: Netlify.env.get("REQUESTS_SECRET"),
    ip: context.ip,
    now: new Date(),
  });

export const config: Config = { path: ["/api/requests", "/api/requests/*"], cache: "manual" };
```

In `netlify/edge-functions/markdown.ts`, change the config's `excludedPath` line from:

```ts
  excludedPath: ["/assets/*", "/downloads/*", "/*.css", "/*.js", "/*.txt", "/*.xml"],
```

to:

```ts
  excludedPath: ["/api/*", "/assets/*", "/downloads/*", "/*.css", "/*.js", "/*.txt", "/*.xml"],
```

- [ ] **Step 7: Run both test files**

Run: `node --import tsx --test netlify/edge-functions/lib/*.test.ts`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add netlify/edge-functions/lib/requests-api.ts netlify/edge-functions/lib/memory-store.ts netlify/edge-functions/lib/requests-api.test.ts netlify/edge-functions/requests.ts netlify/edge-functions/markdown.ts
git commit -m "feat(site): feature-request API on an edge function, with limits and a bot trap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Moderation command

**Files:**
- Create: `scripts/requests-admin.ts`, `scripts/requests.ts`, `scripts/requests.sh`
- Test: `scripts/requests-admin.test.ts`

**Interfaces:**
- Consumes: `Store`, `loadItems` (Task 2); `board`, `rootOf`, `isStatus`, `Item`, `BoardItem`, `Status` (Task 1); `MemoryStore` (Task 2, tests only).
- Produces: `scripts/requests-admin.ts` exports `listBoard(store: Store): Promise<BoardItem[]>`, `setStatus(store: Store, id: string, status: Status): Promise<void>`, `remove(store: Store, id: string): Promise<void>`, `merge(store: Store, from: string, into: string): Promise<void>`, `purge(store: Store, id: string): Promise<void>`, `createdSince(items: BoardItem[], iso: string): BoardItem[]`, `pruneLimits(store: Store, now: Date, all?: boolean): Promise<number>`. Command: `scripts/requests.sh new|list|remove <id>|merge <id> <into>|status <id> <status>|purge <id>|prune [--all]`.

- [ ] **Step 1: Write the failing tests**

Create `scripts/requests-admin.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { MemoryStore } from "../netlify/edge-functions/lib/memory-store.ts";
import { createdSince, listBoard, merge, pruneLimits, purge, remove, setStatus } from "./requests-admin.ts";

const seeded = async () => {
  const store = new MemoryStore();
  const base = { details: "", status: "open", source: "site", version: "" };
  await store.setJSON("items/aaaaaaaa", { id: "aaaaaaaa", title: "Token usage", created: "2026-10-01T10:00:00.000Z", ...base });
  await store.setJSON("items/bbbbbbbb", { id: "bbbbbbbb", title: "Show tokens", created: "2026-10-01T11:00:00.000Z", ...base });
  await store.set("votes/aaaaaaaa/v1", "1");
  await store.set("votes/bbbbbbbb/v1", "1");
  await store.set("votes/bbbbbbbb/v2", "1");
  return store;
};

test("setStatus and remove", async () => {
  const store = await seeded();
  await setStatus(store, "aaaaaaaa", "planned");
  await remove(store, "bbbbbbbb");
  assert.deepEqual((await listBoard(store)).map((i) => [i.id, i.status]), [["aaaaaaaa", "planned"]]);
  await assert.rejects(setStatus(store, "zzzzzzzz", "shipped"), /No request zzzzzzzz/);
});

test("merge folds votes into the target once per voter and refuses cycles", async () => {
  const store = await seeded();
  await merge(store, "bbbbbbbb", "aaaaaaaa");
  assert.deepEqual((await listBoard(store)).map((i) => [i.id, i.votes]), [["aaaaaaaa", 2]]);
  await assert.rejects(merge(store, "aaaaaaaa", "bbbbbbbb"), /already merged/);
  await assert.rejects(merge(store, "aaaaaaaa", "aaaaaaaa"), /itself/);
});

test("purge deletes a request and its votes", async () => {
  const store = await seeded();
  await purge(store, "bbbbbbbb");
  assert.deepEqual([...store.data.keys()].sort(), ["items/aaaaaaaa", "votes/aaaaaaaa/v1"]);
});

test("createdSince lists newer requests, oldest first", async () => {
  const items = await listBoard(await seeded());
  assert.deepEqual(createdSince(items, "2026-10-01T10:30:00.000Z").map((i) => i.id), ["bbbbbbbb"]);
});

test("pruneLimits drops days before yesterday, or everything with all", async () => {
  const store = new MemoryStore();
  await store.set("limits/2026-09-28/n/post/1", "1");
  await store.set("limits/2026-09-30/n/post/2", "1");
  await store.set("limits/2026-10-01/n/vote/3", "1");
  assert.equal(await pruneLimits(store, new Date("2026-10-01T12:00:00Z")), 1);
  assert.equal(await pruneLimits(store, new Date("2026-10-01T12:00:00Z"), true), 2);
  assert.deepEqual([...store.data.keys()], []);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --import tsx --test scripts/requests-admin.test.ts`
Expected: FAIL, `Cannot find module ... requests-admin.ts`.

- [ ] **Step 3: Write the moderation functions**

Create `scripts/requests-admin.ts`:

```ts
// Moderation for the feature-request board, over the same Store the edge function uses.
import { loadItems, type Store } from "../netlify/edge-functions/lib/requests-api.ts";
import { board, rootOf, type BoardItem, type Item, type Status } from "../netlify/edge-functions/lib/requests-core.ts";

async function find(store: Store, id: string): Promise<Item> {
  const item = await store.get(`items/${id}`, { type: "json" }) as Item | null;
  if (!item) throw new Error(`No request ${id}.`);
  return item;
}

export async function listBoard(store: Store): Promise<BoardItem[]> {
  const [items, votes] = await Promise.all([loadItems(store), store.list({ prefix: "votes/" })]);
  return board(items, votes.blobs.map((b) => b.key));
}

export async function setStatus(store: Store, id: string, status: Status): Promise<void> {
  await store.setJSON(`items/${id}`, { ...(await find(store, id)), status });
}

export async function remove(store: Store, id: string): Promise<void> {
  await store.setJSON(`items/${id}`, { ...(await find(store, id)), removed: true });
}

export async function merge(store: Store, from: string, into: string): Promise<void> {
  if (from === into) throw new Error("A request can't be merged into itself.");
  const source = await find(store, from);
  await find(store, into);
  const byId = new Map((await loadItems(store)).map((i) => [i.id, i]));
  if (rootOf(into, byId) === from) throw new Error(`${into} is already merged into ${from}.`);
  await store.setJSON(`items/${from}`, { ...source, mergedInto: into });
}

/** Deletes a request and its votes outright. For test data; use remove for real requests. */
export async function purge(store: Store, id: string): Promise<void> {
  const { blobs } = await store.list({ prefix: `votes/${id}/` });
  await Promise.all(blobs.map((b) => store.delete(b.key)));
  await store.delete(`items/${id}`);
}

export const createdSince = (items: BoardItem[], iso: string): BoardItem[] =>
  items.filter((i) => i.created > iso).sort((a, b) => a.created.localeCompare(b.created));

export async function pruneLimits(store: Store, now: Date, all = false): Promise<number> {
  const yesterday = new Date(now.getTime() - 86_400_000).toISOString().slice(0, 10);
  const { blobs } = await store.list({ prefix: "limits/" });
  const stale = blobs.filter((b) => all || b.key.split("/")[1] < yesterday);
  await Promise.all(stale.map((b) => store.delete(b.key)));
  return stale.length;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --import tsx --test scripts/requests-admin.test.ts`
Expected: all PASS.

- [ ] **Step 5: Write the command**

Create `scripts/requests.ts`:

```ts
// The feature-request board from the terminal, using the Netlify CLI's login and the linked site.
import { getStore } from "@netlify/blobs";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { Store } from "../netlify/edge-functions/lib/requests-api.ts";
import { isStatus, type BoardItem } from "../netlify/edge-functions/lib/requests-core.ts";
import { createdSince, listBoard, merge, pruneLimits, purge, remove, setStatus } from "./requests-admin.ts";

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
    console.log(`${String(i.votes).padStart(4)}  ${i.id}  ${i.status.padEnd(11)}  ${i.title}`);
    if (i.details) console.log(`${" ".repeat(29)}${i.details}`);
  }
}

const [command, a, b] = process.argv.slice(2);
const need = (value: string | undefined) => value ?? fail(usage);
const store = getStore({ name: "requests", ...credentials() }) as unknown as Store;

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
```

Create `scripts/requests.sh`:

```zsh
#!/bin/zsh
# Moderates the feature-request board at yaml.cafe/requests (Netlify Blobs store "requests").
#
#   scripts/requests.sh new                         requests since you last looked
#   scripts/requests.sh list                        everything, by votes
#   scripts/requests.sh status <id> planned         open | planned | in-progress | shipped
#   scripts/requests.sh merge <id> <into>           fold a duplicate into the original
#   scripts/requests.sh remove <id>                 hide a request (kept, marked removed)
#   scripts/requests.sh purge <id>                  delete a request and its votes (test data)
#   scripts/requests.sh prune [--all]               drop old daily-limit records
set -euo pipefail
cd "$(dirname "$0")/.."
exec node --import tsx scripts/requests.ts "$@"
```

Run: `chmod +x scripts/requests.sh && scripts/requests.sh list`
Expected: `No requests.` (the live store is empty; this proves credentials and Blobs access work).

Run: `scripts/requests.sh status zzzzzzzz planned`
Expected: exits non-zero with `No request zzzzzzzz.`

- [ ] **Step 6: Commit**

```bash
git add scripts/requests-admin.ts scripts/requests-admin.test.ts scripts/requests.ts scripts/requests.sh
git commit -m "feat(site): requests.sh to moderate the feature-request board

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The board page

**Files:**
- Create: `site/requests/similar.js`, `site/requests/similar.test.mjs`, `site/requests/index.html`, `site/requests/requests.css`, `site/requests/requests.js`

**Interfaces:**
- Consumes: the HTTP API from Task 2 (`GET /api/requests` → `{ items }`, `POST /api/requests` → `{ item }`, `POST|DELETE /api/requests/<id>/vote` → `{ votes }`, errors `{ error }`).
- Produces: `similar(title: string, items: { title: string; votes: number }[], limit = 3)` from `similar.js`; the page at `/requests/`; `localStorage` keys `ambient-voter` and `ambient-votes`; Umami events `Request posted` (`{ from }`) and `Vote`.

- [ ] **Step 1: Write the failing tests for the similar-titles hint**

Create `site/requests/similar.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { similar } from "./similar.js";

const items = [
  { id: "a", title: "Show token usage per session", votes: 4 },
  { id: "b", title: "Token usage in the menu bar", votes: 9 },
  { id: "c", title: "Support Windows", votes: 20 },
  { id: "d", title: "Usage limits for tokens", votes: 1 },
];

test("finds titles that share at least half the words, best match then most votes", () => {
  // a and b share both words (1.0) and sort by votes; d shares "usage" of two typed words (0.5).
  assert.deepEqual(similar("token usage", items).map((i) => i.id), ["b", "a", "d"]);
});

test("ignores short words and case, and caps the list", () => {
  assert.deepEqual(similar("TO a Windows", items).map((i) => i.id), ["c"]);
  assert.equal(similar("usage", items, 1).length, 1);
});

test("returns nothing for empty or unrelated input", () => {
  assert.deepEqual(similar("", items), []);
  assert.deepEqual(similar("dark mode", items), []);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test site/requests/similar.test.mjs`
Expected: FAIL, `Cannot find module ... similar.js`.

- [ ] **Step 3: Write `similar.js`**

Create `site/requests/similar.js`:

```js
// Titles that look like the one being typed, so people vote for an existing idea instead of repeating it.
const words = (s) => new Set(String(s).toLowerCase().match(/[\p{L}\p{N}]{3,}/gu) ?? []);

/** Up to `limit` items sharing at least half their words with `title` (of the shorter title), best first. */
export function similar(title, items, limit = 3) {
  const typed = words(title);
  if (typed.size === 0) return [];
  return items
    .map((item) => {
      const theirs = words(item.title);
      let shared = 0;
      for (const w of typed) if (theirs.has(w)) shared++;
      return { item, score: theirs.size ? shared / Math.min(typed.size, theirs.size) : 0 };
    })
    .filter((m) => m.score >= 0.5)
    .sort((a, b) => b.score - a.score || b.item.votes - a.item.votes)
    .slice(0, limit)
    .map((m) => m.item);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test site/requests/similar.test.mjs`
Expected: all PASS.

- [ ] **Step 5: Write the page**

Create `site/requests/index.html`:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Feature requests — Ambient</title>
  <meta name="description" content="Tell us what Ambient should bring you next, and vote for other people's ideas. No account needed.">
  <link rel="canonical" href="https://yaml.cafe/requests/">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Ambient">
  <meta property="og:url" content="https://yaml.cafe/requests/">
  <meta property="og:title" content="What should Ambient bring you next?">
  <meta property="og:description" content="Suggest a feature for Ambient or vote for other people's ideas. No account needed.">
  <meta property="og:image" content="https://yaml.cafe/assets/og.png">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="theme-color" content="#000000">
  <link rel="icon" href="/assets/favicon-64.png">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
  <link rel="stylesheet" href="/styles.css">
  <link rel="stylesheet" href="/requests/requests.css">
  <script defer src="https://cloud.umami.is/script.js" data-website-id="5071a34e-e2ce-4556-b044-90c5bd1c2ee9" data-domains="yaml.cafe" data-do-not-track="true"></script>
  <script defer src="/vendor/web-vitals-6.2.2.js"></script>
  <script defer src="/perf.js"></script>
  <script type="module" src="/requests/requests.js"></script>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "WebPage",
        "@id": "https://yaml.cafe/requests/#page",
        "name": "Feature requests",
        "url": "https://yaml.cafe/requests/",
        "description": "Suggest a feature for Ambient or vote for other people's ideas.",
        "isPartOf": { "@id": "https://yaml.cafe/#website" },
        "about": { "@id": "https://yaml.cafe/#app" }
      },
      {
        "@type": "BreadcrumbList",
        "itemListElement": [
          { "@type": "ListItem", "position": 1, "name": "Ambient", "item": "https://yaml.cafe/" },
          { "@type": "ListItem", "position": 2, "name": "Requests", "item": "https://yaml.cafe/requests/" }
        ]
      }
    ]
  }
  </script>
</head>
<body>
<nav class="nav" aria-label="Main">
  <div class="wrap">
    <a class="brand" href="/"><img src="/assets/icon-256.png" alt="">Ambient</a>
    <a class="btn small push" href="/" data-umami-event="Get Ambient" data-umami-event-from="requests-nav">Get Ambient</a>
  </div>
</nav>

<main class="page rq">
  <p class="crumbs"><a href="/">Ambient</a> › Requests</p>
  <h1>What should Ambient bring you next?</h1>
  <p class="rq-lede">Tell us what would make working with your agents better. Anyone can suggest or vote; no account needed.</p>

  <form id="rq-form" class="rq-suggest" novalidate>
    <label for="rq-title">Your idea</label>
    <input id="rq-title" name="title" type="text" autocomplete="off" required placeholder="What would you like Ambient to do for you?">
    <div id="rq-hint" class="rq-hint" hidden></div>
    <label for="rq-details">Details <span class="optional">(optional)</span></label>
    <textarea id="rq-details" name="details" rows="3" placeholder="Why it matters to you (optional)"></textarea>
    <p class="visually-hidden"><label>Leave this empty <input name="website" tabindex="-1" autocomplete="off"></label></p>
    <p class="rq-error" id="rq-form-error" role="alert"></p>
    <button class="btn" type="submit" id="rq-submit">Suggest it</button>
  </form>

  <p id="rq-message" class="rq-message" role="status" aria-live="polite"></p>

  <div class="rq-controls">
    <div class="rq-tabs" role="group" aria-label="Sort">
      <button type="button" data-sort="top" aria-pressed="true">Top</button>
      <button type="button" data-sort="new" aria-pressed="false">New</button>
    </div>
    <div class="rq-chips" role="group" aria-label="Status">
      <button type="button" data-filter="all" aria-pressed="true">All</button>
      <button type="button" data-filter="open" aria-pressed="false">Open</button>
      <button type="button" data-filter="planned" aria-pressed="false">Planned</button>
      <button type="button" data-filter="in-progress" aria-pressed="false">In progress</button>
      <button type="button" data-filter="shipped" aria-pressed="false">Shipped</button>
    </div>
  </div>
  <ul id="rq-list" class="rq-list" aria-label="Feature requests"></ul>
</main>

<footer>
  <div class="wrap">
    <span>© 2026 yaml.cafe</span>
    <a href="/guides/">Guides</a>
    <a href="/requests/">Requests</a>
    <a href="/contact/">Contact</a>
    <a href="/privacy.html">Privacy</a>
    <span class="spacer">Claude, Codex and Gemini are trademarks of their owners. Ambient isn't affiliated with Anthropic, OpenAI or Google.</span>
  </div>
</footer>
</body>
</html>
```

Create `site/requests/requests.css`:

```css
/* The feature-request board. Colors and type come from styles.css. */
.rq-lede { font-size: 19px; color: var(--ink-2); margin: -8px 0 28px; }
.rq-suggest { background: var(--paper-2); border-radius: 22px; padding: 22px; display: grid; gap: 8px; margin: 0 0 12px; }
.rq-suggest label { font-size: 14px; font-weight: 600; color: var(--ink); }
.rq-suggest .optional { font-weight: 400; color: var(--ink-2); }
.rq-suggest input, .rq-suggest textarea {
  font: inherit; font-size: 16px; width: 100%; padding: 10px 12px; border: 1px solid #d2d2d7;
  border-radius: 12px; background: #fff; color: var(--ink); resize: vertical;
}
.rq-suggest input:focus-visible, .rq-suggest textarea:focus-visible { outline: 3px solid rgba(0, 113, 227, 0.45); outline-offset: 1px; }
.rq-suggest .btn { justify-self: start; margin-top: 6px; }
.rq-hint { font-size: 14px; background: #fff; border-radius: 12px; padding: 10px 14px; }
.rq-hint p { margin: 0 0 4px; color: var(--ink); font-weight: 600; }
.rq-hint ul { margin: 0; padding-left: 18px; }
.rq-error { color: #c9302c; font-size: 14px; margin: 0; }
.rq-error:empty { display: none; }
.rq-message { color: var(--ink-2); font-size: 15px; margin: 8px 0 20px; min-height: 1.4em; }
.rq-controls { display: flex; flex-wrap: wrap; gap: 12px; justify-content: space-between; align-items: center; margin: 0 0 8px; }
.rq-tabs, .rq-chips { display: flex; flex-wrap: wrap; gap: 6px; }
.rq-controls button {
  font: inherit; font-size: 14px; padding: 6px 14px; min-height: 32px; border-radius: 980px;
  border: 1px solid #d2d2d7; background: #fff; color: var(--ink); cursor: pointer;
}
.rq-controls button[aria-pressed="true"] { background: var(--ink); border-color: var(--ink); color: #fff; }
.rq-controls button:focus-visible, .rq-vote:focus-visible { outline: 3px solid rgba(0, 113, 227, 0.45); outline-offset: 2px; }
.rq-list { list-style: none; padding: 0; margin: 0; }
.page .rq-list li { margin: 0; }
.rq-item { display: flex; gap: 16px; align-items: flex-start; padding: 16px 0; border-top: 1px solid var(--line); }
.rq-vote {
  flex: none; display: flex; flex-direction: column; align-items: center; justify-content: center;
  width: 56px; min-height: 56px; border-radius: 14px; border: 1px solid #d2d2d7; background: #fff;
  color: var(--ink); font: inherit; cursor: pointer;
}
.rq-vote[aria-pressed="true"] { background: var(--accent); border-color: var(--accent); color: #fff; }
.rq-vote:disabled { opacity: 0.6; cursor: progress; }
.rq-arrow { font-size: 12px; line-height: 1; }
.rq-count { font-size: 17px; font-weight: 600; }
.rq-body { min-width: 0; }
.rq-body h3 { margin: 4px 0; font-size: 17px; overflow-wrap: anywhere; }
.rq-body p { margin: 0; font-size: 15px; overflow-wrap: anywhere; }
.rq-badge { display: inline-block; vertical-align: middle; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 980px; }
.rq-planned { background: #e8f0fe; color: #1a56c4; }
.rq-in-progress { background: #fff4e0; color: #8a5300; }
.rq-shipped { background: #e6f6ea; color: #1d6b31; }
.rq-empty { padding: 24px 0; color: var(--ink-2); border-top: 1px solid var(--line); }
```

Create `site/requests/requests.js`:

```js
// The feature-request board. No account and no cookies: a random voter ID and the IDs you've voted
// for stay in this browser's storage. User text is only ever set with textContent.
import { similar } from "./similar.js";

const loadedAt = performance.now();
const params = new URLSearchParams(location.search);
const source = params.get("from") === "app" ? "app" : "site";
const version = params.get("v") || "";

// Storage can be unavailable (private windows, blocked site data); never let it break the page.
const store = {
  get(key) { try { return localStorage.getItem(key); } catch { return null; } },
  set(key, value) { try { localStorage.setItem(key, value); } catch { /* ignore */ } },
};
const track = (name, data) => { try { window.umami?.track(name, data); } catch { /* ignore */ } };

const voter = store.get("ambient-voter") || (() => { const id = crypto.randomUUID(); store.set("ambient-voter", id); return id; })();
const voted = new Set((() => { try { return JSON.parse(store.get("ambient-votes") || "[]"); } catch { return []; } })());
const saveVoted = () => store.set("ambient-votes", JSON.stringify([...voted]));

const LABELS = { planned: "Planned", "in-progress": "In progress", shipped: "Shipped" };
const state = { items: [], sort: "top", filter: "all" };
const $ = (id) => document.getElementById(id);
const list = $("rq-list"), message = $("rq-message"), form = $("rq-form"), title = $("rq-title");
const details = $("rq-details"), hint = $("rq-hint"), submit = $("rq-submit"), formError = $("rq-form-error");

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = {};
  try { data = await res.json(); } catch { /* not JSON */ }
  return { ok: res.ok, data };
}
const safely = (promise) => promise.catch(() => ({ ok: false, data: {} }));
const say = (text) => { message.textContent = text; };
const plural = (n) => `${n} vote${n === 1 ? "" : "s"}`;

function shown() {
  const items = state.items.filter((i) => state.filter === "all" || i.status === state.filter);
  return items.sort(state.sort === "new"
    ? (a, b) => b.created.localeCompare(a.created)
    : (a, b) => b.votes - a.votes || b.created.localeCompare(a.created));
}

function row(item) {
  const li = document.createElement("li");
  li.className = "rq-item";
  li.id = `req-${item.id}`;
  const mine = voted.has(item.id);
  const button = document.createElement("button");
  button.type = "button";
  button.className = "rq-vote";
  button.setAttribute("aria-pressed", String(mine));
  button.setAttribute("aria-label", `${mine ? "Take back your vote for" : "Vote for"} ${item.title}. ${plural(item.votes)}.`);
  const arrow = document.createElement("span");
  arrow.className = "rq-arrow";
  arrow.setAttribute("aria-hidden", "true");
  arrow.textContent = "▲";
  const count = document.createElement("span");
  count.className = "rq-count";
  count.textContent = String(item.votes);
  button.append(arrow, count);
  button.addEventListener("click", () => toggleVote(item, button));
  const body = document.createElement("div");
  body.className = "rq-body";
  const heading = document.createElement("h3");
  heading.textContent = item.title;
  if (LABELS[item.status]) {
    const badge = document.createElement("span");
    badge.className = `rq-badge rq-${item.status}`;
    badge.textContent = LABELS[item.status];
    heading.append(" ", badge);
  }
  body.append(heading);
  if (item.details) {
    const p = document.createElement("p");
    p.textContent = item.details;
    body.append(p);
  }
  li.append(button, body);
  return li;
}

function render() {
  const items = shown();
  if (!items.length) {
    const li = document.createElement("li");
    li.className = "rq-empty";
    li.textContent = state.items.length ? "Nothing here yet." : "No requests yet. Be the first.";
    list.replaceChildren(li);
    return;
  }
  list.replaceChildren(...items.map(row));
}

function syncControls() {
  document.querySelectorAll("[data-sort]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.sort === state.sort)));
  document.querySelectorAll("[data-filter]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.filter === state.filter)));
}

async function toggleVote(item, button) {
  if (button.disabled) return;
  button.disabled = true;
  const adding = !voted.has(item.id);
  const { ok, data } = await safely(api(adding ? "POST" : "DELETE", `/api/requests/${item.id}/vote`, { voter }));
  button.disabled = false;
  if (!ok) return say(data.error || "Couldn't save your vote. Try again in a moment.");
  if (adding) { voted.add(item.id); track("Vote"); } else voted.delete(item.id);
  saveVoted();
  item.votes = data.votes;
  render();
  document.querySelector(`#req-${item.id} .rq-vote`)?.focus();
}

function showHint() {
  const matches = similar(title.value, state.items);
  if (!matches.length) { hint.hidden = true; hint.replaceChildren(); return; }
  const lead = document.createElement("p");
  lead.textContent = "Is it one of these? Vote instead.";
  const ul = document.createElement("ul");
  for (const match of matches) {
    const li = document.createElement("li");
    const a = document.createElement("a");
    a.href = `#req-${match.id}`;
    a.textContent = `${match.title} (${plural(match.votes)})`;
    a.addEventListener("click", (event) => {
      event.preventDefault();
      state.filter = "all";
      syncControls();
      render();
      const target = document.getElementById(`req-${match.id}`);
      target?.scrollIntoView({ block: "center" });
      target?.querySelector(".rq-vote")?.focus();
    });
    li.append(a);
    ul.append(li);
  }
  hint.replaceChildren(lead, ul);
  hint.hidden = false;
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  formError.textContent = "";
  if (title.value.trim().length < 3) {
    formError.textContent = "Give your idea a title of at least 3 characters.";
    title.focus();
    return;
  }
  submit.disabled = true;
  submit.textContent = "Sending…";
  const { ok, data } = await safely(api("POST", "/api/requests", {
    title: title.value, details: details.value, source, version, voter,
    website: form.elements.website.value, elapsedMs: Math.round(performance.now() - loadedAt),
  }));
  submit.disabled = false;
  submit.textContent = "Suggest it";
  if (!ok) { formError.textContent = data.error || "Couldn't send your idea. Check your connection and try again."; return; }
  voted.add(data.item.id);
  saveVoted();
  state.items.unshift(data.item);
  state.sort = "new";
  state.filter = "all";
  syncControls();
  render();
  form.reset();
  hint.hidden = true;
  say("Thanks! It's on the board, with your vote.");
  track("Request posted", { from: source });
});

title.addEventListener("input", showHint);
document.querySelectorAll("[data-sort]").forEach((b) => b.addEventListener("click", () => { state.sort = b.dataset.sort; syncControls(); render(); }));
document.querySelectorAll("[data-filter]").forEach((b) => b.addEventListener("click", () => { state.filter = b.dataset.filter; syncControls(); render(); }));

syncControls();
say("Loading the board…");
const { ok, data } = await safely(api("GET", "/api/requests"));
if (ok && Array.isArray(data.items)) {
  state.items = data.items;
  say("");
  render();
} else {
  say("The board couldn't load. Try again in a moment.");
}
```

- [ ] **Step 6: Check the page locally (no API here, so this exercises the error state)**

Start the `site` preview server (`.claude/launch.json` → `site`, port 8787) and open `http://localhost:8787/requests/`.
Expected: header, lede and form render in the site's style; the status line reads "The board couldn't load. Try again in a moment."; submitting an empty title shows "Give your idea a title of at least 3 characters."; no console errors except the failed `/api/requests` fetch; at 375 px width nothing scrolls sideways (`document.documentElement.scrollWidth === innerWidth`).

- [ ] **Step 7: Run the suite and commit**

Run: `npm test`
Expected: all PASS.

```bash
git add site/requests/index.html site/requests/requests.css site/requests/requests.js site/requests/similar.js site/requests/similar.test.mjs
git commit -m "feat(site): the feature-request board page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Link the board across the site

**Files:**
- Modify: `site/index.html` (nav link, FAQ entry and its JSON-LD, footer link), `site/contact/index.html`, `site/guides/index.html`, `site/guides/claude-code-notifications-mac/index.html`, `site/guides/codex-notifications-mac/index.html`, `site/guides/gemini-cli-notifications-mac/index.html`, `site/privacy.html`, `site/404.html`, `site/llms.txt`, `site/sitemap.xml`

**Interfaces:**
- Consumes: the page at `/requests/` (Task 4).
- Produces: links to `/requests/` from every page; FAQ question "How do I ask for a feature?"; privacy section "Feature requests".

- [ ] **Step 1: Re-read the files the other session edits**

Run: `git status --short site/`
If any file this task modifies already shows as modified, it holds the other session's unfinished work, and committing the file would commit theirs too. Stop and ask the user whether to wait for that session to commit, or to commit both together. Continue only once the listed files are clean or the user has decided.

- [ ] **Step 2: Apply the edits with a checked script**

Run this from the repo root (each replacement must match exactly once, or it stops):

```bash
python3 - <<'EOF'
import pathlib
def sub(f, a, b, count=1):
    p = pathlib.Path(f); s = p.read_text()
    assert s.count(a) == count, (f, a[:70], s.count(a))
    p.write_text(s.replace(a, b))

# Every footer: Requests before Contact.
for f in ["site/index.html", "site/contact/index.html", "site/guides/index.html",
          "site/guides/claude-code-notifications-mac/index.html", "site/guides/codex-notifications-mac/index.html",
          "site/guides/gemini-cli-notifications-mac/index.html"]:
    sub(f, '    <a href="/contact/">Contact</a>\n', '    <a href="/requests/">Requests</a>\n    <a href="/contact/">Contact</a>\n')
for f in ["site/privacy.html", "site/404.html"]:
    sub(f, '<a href="/contact/">Contact</a><a href="/privacy.html">Privacy</a></div></footer>',
        '<a href="/requests/">Requests</a><a href="/contact/">Contact</a><a href="/privacy.html">Privacy</a></div></footer>')

# Homepage nav.
sub("site/index.html", '      <a href="/guides/">Guides</a>\n    </div>', '      <a href="/guides/">Guides</a>\n      <a href="/requests/">Requests</a>\n    </div>')

# Homepage FAQ, visible and in JSON-LD.
sub("site/index.html",
    '"acceptedAnswer": { "@type": "Answer", "text": "No. The download starts right away. If you want an email when a new version ships, you can leave your address after downloading; that\'s optional." } }\n',
    '"acceptedAnswer": { "@type": "Answer", "text": "No. The download starts right away. If you want an email when a new version ships, you can leave your address after downloading; that\'s optional." } },\n'
    '          { "@type": "Question", "name": "How do I ask for a feature?", "acceptedAnswer": { "@type": "Answer", "text": "Suggest it on the feature requests board at yaml.cafe/requests, or vote for someone else\'s idea there. No account needed. In the app, choose Suggest a Feature… from the menu bar menu." } }\n')
sub("site/index.html",
    "that's optional. See the <a href=\"/privacy.html\">privacy notice</a>.</p></details>\n",
    "that's optional. See the <a href=\"/privacy.html\">privacy notice</a>.</p></details>\n"
    "      <details><summary>How do I ask for a feature?</summary><p>Suggest it on the <a href=\"/requests/\">feature requests board</a>, or vote for someone else's idea there. No account needed. In the app, choose <strong>Suggest a Feature…</strong> from the menu bar menu.</p></details>\n")

# Contact page.
sub("site/contact/index.html",
    "  <p>Tell us which agent, terminal or editor you'd like Ambient to support next, or what would make the island or notifications more useful.</p>",
    "  <p>Suggest it on the <a href=\"/requests/\">feature requests board</a> and vote for other people's ideas, so we can see what matters most. You can also email us: tell us which agent, terminal or editor you'd like Ambient to support next, or what would make the island or notifications more useful.</p>")

# Privacy notice.
sub("site/privacy.html", "  <h2>Update emails</h2>",
    "  <h2>Feature requests</h2>\n"
    "  <p>The <a href=\"/requests/\">feature requests board</a> is public: what you write there, and how many votes it has, anyone can see. Posting and voting need no account. Your browser keeps a random ID so you vote once per request; we store only a scrambled version of it. To limit spam, we count posts and votes per network each day using a one-way hash whose secret changes every day, so it can't be traced back to your IP address or linked across days. We don't store IP addresses, cookies or email addresses for the board. To have a request removed, email us.</p>\n\n"
    "  <h2>Update emails</h2>")
sub("site/privacy.html", "<p>Last updated September 27, 2026.</p>", "<p>Last updated September 30, 2026.</p>")

# llms.txt and sitemap.
sub("site/llms.txt", "- [Contact](https://yaml.cafe/contact/)", "- [Feature requests](https://yaml.cafe/requests/): suggest a feature or vote for other people's ideas; no account needed.\n- [Contact](https://yaml.cafe/contact/)")
sub("site/sitemap.xml", "  <url><loc>https://yaml.cafe/contact/</loc>", "  <url><loc>https://yaml.cafe/requests/</loc><lastmod>2026-09-30</lastmod></url>\n  <url><loc>https://yaml.cafe/contact/</loc>")
print("ok")
EOF
```

Expected: `ok`. If an assertion fails, the other session changed that spot: read the file and adapt the matching string, keeping the same inserted text.

- [ ] **Step 3: Validate links, JSON-LD and the FAQ**

Run:

```bash
python3 - <<'EOF'
import json, re, pathlib, html
root = pathlib.Path("site"); problems = []
for p in root.rglob("*.html"):
    s = p.read_text()
    for block in re.findall(r'<script type="application/ld\+json">(.*?)</script>', s, re.S):
        try: json.loads(block)
        except Exception as e: problems.append(f"{p}: JSON-LD {e}")
    for href in re.findall(r'href="(/[^"#?]*)', s):
        t = root / href.lstrip("/")
        if href.endswith("/"): t = t / "index.html"
        if not t.exists(): problems.append(f"{p}: broken {href}")
s = (root / "index.html").read_text()
assert s.count("How do I ask for a feature?") == 2, "FAQ question must appear in JSON-LD and on the page"
print("\n".join(problems) or "no problems")
EOF
```

Expected: `no problems`.

- [ ] **Step 4: Commit**

```bash
git add site/index.html site/contact/index.html site/guides/index.html site/guides/claude-code-notifications-mac/index.html site/guides/codex-notifications-mac/index.html site/guides/gemini-cli-notifications-mac/index.html site/privacy.html site/404.html site/llms.txt site/sitemap.xml
git commit -m "site: link the feature-request board from every page, the FAQ, contact and privacy

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The app's entry points

**Files:**
- Create: `Sources/AmbientCore/FeatureRequests.swift`, `Tests/AmbientCoreTests/FeatureRequestsTests.swift`
- Modify: `Sources/AmbientApp/MenuBarController.swift` (menu items around line 120 and the `@objc` actions near line 155), `Sources/AmbientApp/Settings/Panes/GeneralPane.swift` (About section)

**Interfaces:**
- Consumes: `AmbientVersion.current` (`Sources/AmbientCore/Version.swift`).
- Produces: `public enum FeatureRequests { static func url(version: String = AmbientVersion.current) -> URL; static let website: URL }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/AmbientCoreTests/FeatureRequestsTests.swift`:

```swift
import Foundation
import Testing
@testable import AmbientCore

@Suite struct FeatureRequestsTests {
    @Test func opensTheBoardTaggedWithTheAppAndVersion() {
        #expect(FeatureRequests.url(version: "0.4.0").absoluteString == "https://yaml.cafe/requests/?from=app&v=0.4.0")
    }

    @Test func defaultsToTheRunningVersion() {
        #expect(FeatureRequests.url().absoluteString == "https://yaml.cafe/requests/?from=app&v=\(AmbientVersion.current)")
    }

    @Test func websiteIsTheHomepage() {
        #expect(FeatureRequests.website.absoluteString == "https://yaml.cafe/")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter FeatureRequestsTests`
Expected: FAIL to compile, `cannot find 'FeatureRequests' in scope`. (If the build fails in files this plan doesn't touch, such as the other session's `PerfMonitor.swift`, stop and tell the user; don't edit their files.)

- [ ] **Step 3: Write the implementation**

Create `Sources/AmbientCore/FeatureRequests.swift`:

```swift
import Foundation

/// The public feature-request board on yaml.cafe. The app opens it in the browser and sends nothing itself.
public enum FeatureRequests {
    public static func url(version: String = AmbientVersion.current) -> URL {
        var parts = URLComponents(string: "https://yaml.cafe/requests/")!
        parts.queryItems = [URLQueryItem(name: "from", value: "app"), URLQueryItem(name: "v", value: version)]
        return parts.url!
    }

    public static let website = URL(string: "https://yaml.cafe/")!
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `swift test --filter FeatureRequestsTests`
Expected: 3 tests PASS.

- [ ] **Step 5: Add the menu item**

In `Sources/AmbientApp/MenuBarController.swift`, replace:

```swift
        menu.addItem(item("Play Demo", #selector(demo)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(settings), key: ","))
```

with:

```swift
        menu.addItem(item("Play Demo", #selector(demo)))
        menu.addItem(.separator())
        menu.addItem(item("Suggest a Feature…", #selector(suggestFeature)))
        menu.addItem(item("Settings…", #selector(settings), key: ","))
```

and replace:

```swift
    @objc private func settings() { onSettings() }
```

with:

```swift
    @objc private func suggestFeature() { NSWorkspace.shared.open(FeatureRequests.url()) }
    @objc private func settings() { onSettings() }
```

(`MenuBarController.swift` already imports `AmbientCore`.)

- [ ] **Step 6: Update Settings › General › About**

In `Sources/AmbientApp/Settings/Panes/GeneralPane.swift`, replace:

```swift
                SettingsRow(title: "Source code") {
                    Link("github.com/viveky259259/ambient",
                         destination: URL(string: "https://github.com/viveky259259/ambient")!)
                        .font(Theme.Fonts.row)
                }
```

with:

```swift
                SettingsRow(title: "Website") {
                    Link("yaml.cafe", destination: FeatureRequests.website)
                        .font(Theme.Fonts.row)
                }
                SettingsDivider()
                SettingsRow(title: "Feature requests") {
                    Link("Suggest or vote", destination: FeatureRequests.url())
                        .font(Theme.Fonts.row)
                }
```

- [ ] **Step 7: Build and run the full Swift suite**

Run: `swift build && swift test`
Expected: builds; all tests PASS. Then run the app (`scripts/build-app.sh --run`), open the menu bar menu, confirm **Suggest a Feature…** sits above **Settings…** and opens `https://yaml.cafe/requests/?from=app&v=0.4.0` in the browser, and that Settings › General › About shows **Website** and **Feature requests** rows.

- [ ] **Step 8: Commit**

```bash
git add Sources/AmbientCore/FeatureRequests.swift Tests/AmbientCoreTests/FeatureRequestsTests.swift Sources/AmbientApp/MenuBarController.swift Sources/AmbientApp/Settings/Panes/GeneralPane.swift
git commit -m "feat(app): Suggest a Feature… opens the yaml.cafe board; About links the website

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Secret, draft deploy and end-to-end check

**Files:**
- No repo files change. Touches: Netlify environment (`REQUESTS_SECRET`), the private `viveky259259/secrets` repo (`ambient-notification/.env`), a draft deploy, and `qa-` test data that is deleted at the end.

**Interfaces:**
- Consumes: everything above.
- Produces: a verified draft deploy URL; `REQUESTS_SECRET` set in Netlify and saved in the secrets repo.

- [ ] **Step 1: Create the secret without printing it**

```bash
SECRET=$(openssl rand -hex 32)
netlify env:set REQUESTS_SECRET "$SECRET" >/dev/null && echo "set in Netlify"
S=/private/tmp/claude-501/-Users-vivekyadav-Documents-Projects-ambient-notification/b964dcad-723e-4355-b26d-f8d23a981c95/scratchpad
rm -rf "$S/secrets" && gh repo clone viveky259259/secrets "$S/secrets" -- --depth 1 --quiet
git -C "$S/secrets" remote set-url origin https://github.com/viveky259259/secrets.git
mkdir -p "$S/secrets/ambient-notification"
printf 'REQUESTS_SECRET=%s\n' "$SECRET" >> "$S/secrets/ambient-notification/.env"
git -C "$S/secrets" add ambient-notification/.env
git -C "$S/secrets" commit -q -m "ambient-notification: REQUESTS_SECRET for the feature-request board"
git -C "$S/secrets" push -q && echo "saved to secrets repo"
unset SECRET
```

Expected: `set in Netlify` and `saved to secrets repo`. Verify without printing the value: `netlify env:list --json | python3 -c "import json,sys; print('REQUESTS_SECRET' in json.load(sys.stdin))"` → `True`.

- [ ] **Step 2: Check for the other session's unfinished site work, then draft-deploy**

Run: `git status --short site netlify`
If anything is listed, it's the other session's uncommitted work: a draft deploy would include it. Tell the user and ask whether to proceed. Then:

Run: `scripts/deploy-site.sh 2>&1 | grep -oE "https://[a-z0-9]+--yaml-cafe.netlify.app" | head -1`
Expected: a draft URL. Save it as `D`.

- [ ] **Step 3: Exercise the API on the draft**

```bash
D=<draft URL from Step 2>
post() { curl -s -X POST "$D/api/requests" -H 'Content-Type: application/json' -d "$1" -w '\n%{http_code}\n'; }
idof() { python3 -c 'import json,sys; print(json.loads(sys.stdin.read().split("\n")[0])["item"]["id"])'; }
vote() { curl -s -X "$1" "$D/api/requests/$2/vote" -H 'Content-Type: application/json' -d "{\"voter\":\"$3\"}" -w ' %{http_code}\n'; }

curl -s "$D/api/requests" -w '\n%{http_code}\n'                                                     # {"items":[...]} 200
OUT=$(post '{"title":"qa-e2e Show token usage","details":"see https://evil.example now","voter":"qa-voter-1111","website":"","elapsedMs":5000}'); echo "$OUT"   # 201, "details":"see now", "votes":1
ID1=$(echo "$OUT" | idof)
OUT=$(post '{"title":"qa-e2e <b>bold</b> <script>x</script>","voter":"qa-voter-1111","website":"","elapsedMs":5000}'); echo "$OUT"   # 201, title exactly as typed
ID2=$(echo "$OUT" | idof)
post '{"title":"qa-e2e trap","voter":"qa-voter-1111","website":"x","elapsedMs":5000}'           # 201, but never stored
post '{"title":"qa-e2e too fast","voter":"qa-voter-1111","website":"","elapsedMs":200}'         # 201, but never stored
OUT=$(post '{"title":"qa-e2e 👩‍💻 emoji","voter":"qa-voter-1111","website":"","elapsedMs":5000}'); echo "$OUT"   # 201
ID3=$(echo "$OUT" | idof)
post '{"title":"qa-e2e fourth","voter":"qa-voter-1111","website":"","elapsedMs":5000}'         # 429, "You've suggested 3 things today..."
vote POST   $ID1 qa-voter-2222     # {"votes":2} 200
vote POST   $ID1 qa-voter-2222     # {"votes":2} 200
vote DELETE $ID1 qa-voter-2222     # {"votes":1} 200
vote POST   zzzzzzzz qa-voter-2222 # 404
scripts/requests.sh list           # exactly the three qa-e2e titles; no "trap", no "too fast"
```

Expected: each line's comment.

- [ ] **Step 4: Check the page on the draft**

Open `$D/requests/` in the browser pane (wait 30 s after Step 3 so the cached board includes the new items):
- The three `qa-e2e` items show. The bold one reads literally `qa-e2e <b>bold</b> <script>x</script>`, with no bold text and no script run.
- Voting and un-voting with the mouse, and with the keyboard (Tab to a vote button, press Space), update the count and `aria-pressed`, and focus stays on the button.
- Typing "token usage" in the title shows "Is it one of these? Vote instead." listing `qa-e2e Show token usage`; clicking it scrolls to that row.
- Posting shows the limit message in the form (this network used its 3 posts in Step 3).
- At 375 px, `document.documentElement.scrollWidth === innerWidth`.

Run Lighthouse on the draft board:

```bash
S=/private/tmp/claude-501/-Users-vivekyadav-Documents-Projects-ambient-notification/b964dcad-723e-4355-b26d-f8d23a981c95/scratchpad
CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" npx -y lighthouse@13.5.0 "$D/requests/" --quiet --only-categories=seo,performance,accessibility,best-practices --output=json --output-path=$S/lh-requests.json --chrome-flags="--headless=new"
python3 -c "import json; d=json.load(open('$S/lh-requests.json')); print({k: round(v['score']*100) for k,v in d['categories'].items()})"
```

Expected: accessibility and best practices 100; performance 100 (rerun once if 95–99). SEO may drop on a draft because the canonical points at yaml.cafe; recheck SEO on production in Task 8.

- [ ] **Step 5: Moderate the test data with the command**

```bash
scripts/requests.sh status $ID1 planned      # "... is now planned."
scripts/requests.sh merge $ID3 $ID1          # "Merged ..."
scripts/requests.sh remove $ID2              # "Removed ..."
scripts/requests.sh list                     # only "qa-e2e Show token usage", status planned
sleep 35 && curl -s "$D/api/requests"        # the same single item with "status":"planned"
```

- [ ] **Step 6: Delete the test data**

```bash
for id in $ID1 $ID2 $ID3; do scripts/requests.sh purge "$id"; done
scripts/requests.sh prune --all
scripts/requests.sh list                     # No requests.
```

---

### Task 8: Review and ship

**Files:**
- Modify: `/Users/vivekyadav/.claude/projects/-Users-vivekyadav-Documents-Projects-ambient-notification/memory/site-seo-validation.md` (one line)

- [ ] **Step 1: Whole-change review**

Run a fresh review of commits from Task 1 to Task 6 (`git log --oneline` to find the range) with the `code-review` skill at high effort, focusing on the Review Focus list and input handling in `requests-api.ts` and `requests.js`. Fix confirmed findings with a test first, commit each fix.

- [ ] **Step 2: Production deploy**

Run: `git status --short site netlify` (stop and ask if the other session has unfinished site work), then `scripts/deploy-site.sh --prod`.

- [ ] **Step 3: Verify production**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://yaml.cafe/requests/         # 200
curl -s https://yaml.cafe/api/requests                                        # {"items":[]}
curl -s -o /dev/null -w "%{http_code} %{content_type}\n" -H "Accept: text/markdown" https://yaml.cafe/   # 200 text/markdown
curl -s https://yaml.cafe/sitemap.xml | grep -c "/requests/"                  # 1
```

Run the schema.org validator on `https://yaml.cafe/requests/` and `https://yaml.cafe/` (0 errors), and Lighthouse on `https://yaml.cafe/requests/` (all 100).

- [ ] **Step 4: Record how to run the board**

Append to the memory file listed above:

```
- Feature-request board: `scripts/requests.sh new|list|status|merge|remove|purge|prune` (store `requests`, secret `REQUESTS_SECRET` in Netlify and the secrets repo). Draft and production share the store: use `qa-` titles for tests and `purge` them after.
```

- [ ] **Step 5: Report**

Tell the user: board URL, what the app changes need (a release), how to moderate, and the credits used (production deploys × 15).
