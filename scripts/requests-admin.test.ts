import { test } from "node:test";
import assert from "node:assert/strict";
import { MemoryStore } from "../netlify/edge-functions/lib/memory-store.ts";
import { createdSince, listBoard, merge, printable, pruneLimits, purge, remove, setStatus } from "./requests-admin.ts";

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

test("merge records the duplicate on the target, so votes can be counted without a scan", async () => {
  const store = await seeded();
  await merge(store, "bbbbbbbb", "aaaaaaaa");
  assert.deepEqual((await store.get("items/aaaaaaaa"))?.mergedFrom, ["bbbbbbbb"]);
});

test("printable escapes control and bidi characters for the terminal but keeps emoji", () => {
  assert.equal(printable("ok\x1b[2K\u202Eend 👩‍💻"), "ok\\u{1b}[2K\\u{202e}end 👩‍💻");
});
