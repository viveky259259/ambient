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
