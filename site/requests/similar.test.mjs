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
