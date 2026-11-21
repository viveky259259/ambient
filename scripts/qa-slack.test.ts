import { test } from "node:test";
import assert from "node:assert/strict";
import { changes, message } from "./qa-slack.ts";
import type { Run } from "./qa-dashboard.ts";

const r = (id: string, status: string) => ({ id, title: `case ${id}`, priority: "P1", status, partial: false, seconds: 1, output: "" }) as never;
const run = (started: string, results: unknown[]): Run => ({ dir: started, info: { started, build: "321", commit: "abc1234" }, results: results as never });

test("a run is compared with each case's previous result", () => {
  const older = [run("1", [r("A-001", "pass"), r("A-002", "fail"), r("A-003", "fail")])];
  const now = run("2", [r("A-001", "fail"), r("A-002", "fail"), r("A-003", "pass"), r("A-004", "error"), r("A-005", "gap-fixed")]);
  const c = changes(now, older);
  assert.deepEqual(c.newlyFailing.map((x: { id: string }) => x.id), ["A-001", "A-004"]);
  assert.deepEqual(c.stillFailing.map((x: { id: string }) => x.id), ["A-002"]);
  assert.deepEqual(c.fixed.map((x: { id: string }) => x.id), ["A-003"]);
  assert.deepEqual(c.gapFixed.map((x: { id: string }) => x.id), ["A-005"]);
});

test("the message counts results and links the dashboard", () => {
  const m = message(run("2", [r("A-001", "pass"), r("A-002", "fail"), r("A-003", "known-gap")]), [], "https://d/x");
  assert.match(m.text, /build 321/);
  assert.match(m.text, /3 scripted cases: \*1 passed\*, \*1 failed\*, 1 known gaps/);
  assert.match(m.text, /\*Newly failing\*\n• `A-002`/);
  assert.match(JSON.stringify(m.blocks), /<https:\/\/d\/x\|Dashboard>/);
});

test("the message says what the run was for and links its log", () => {
  const withContext: Run = { dir: "3", info: { started: "3", build: "321", commit: "abc1234", context: "PR #48 · feat/agent-history", runUrl: "https://gh/run/1" }, results: [] };
  const m = message(withContext, [], "https://d/x");
  assert.match(m.text, /Ambient QA\* · PR #48 · feat\/agent-history ·/);
  assert.match(JSON.stringify(m.blocks), /<https:\/\/gh\/run\/1\|Run log>/);
});
