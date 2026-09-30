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
