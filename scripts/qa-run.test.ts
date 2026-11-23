import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { classify, clearStaleLock, isQAApp, parseScript, type ProcessOps } from "./qa-run.ts";

test("script headers set app, timeout and partial checking", () => {
  const s = parseScript("EVT-001", "/x/EVT-001.sh", "#!/bin/zsh\n# needs-app: yes\n# timeout: 20\n# checks: part\n# slow: yes\n");
  assert.deepEqual(s, { id: "EVT-001", path: "/x/EVT-001.sh", needsApp: true, timeout: 20, partial: true, slow: true });
  const d = parseScript("EVT-002", "/x/EVT-002.sh", "#!/bin/zsh\necho hi\n");
  assert.deepEqual([d.needsApp, d.timeout, d.partial, d.slow], [false, 60, false, false]);
});

test("a known gap is expected to fail, and passing it is flagged", () => {
  assert.equal(classify(0, false), "pass");
  assert.equal(classify(1, false), "fail");
  assert.equal(classify(1, true), "known-gap");
  assert.equal(classify(0, true), "gap-fixed");
  assert.equal(classify(2, false), "error");
  assert.equal(classify(null, true), "error");
});

test("only the QA app's executable counts as the QA app", () => {
  assert.ok(isQAApp("/Users/x/actions-runner-ambient/_work/ambient/ambient/build/AmbientQA.app/Contents/MacOS/AmbientQA"));
  assert.ok(isQAApp("/r/build/AmbientQA.app/Contents/MacOS/AmbientQA --flag"));
  assert.ok(!isQAApp("/Applications/Ambient.app/Contents/MacOS/Ambient"));
  assert.ok(!isQAApp("/usr/bin/vim /x/AmbientQA.app/Contents/MacOS/AmbientQA.swift"));
});

/** A lock as a runner leaves it, with pretend processes: `live` maps a pid to its command. */
function fixture(files: Record<string, string>, live: Record<number, string>) {
  const dir = join(mkdtempSync(join(tmpdir(), "qa-lock-test.")), "lock");
  mkdirSync(dir);
  for (const [name, text] of Object.entries(files)) writeFileSync(join(dir, name), text);
  const killed: [number, string][] = [];
  const ops: ProcessOps = {
    alive: (pid) => pid in live,
    command: (pid) => live[pid] ?? "",
    kill: (pid, signal) => {
      killed.push([pid, signal]);
      delete live[Math.abs(pid)];
    },
    sleep: async () => {},
  };
  return { dir, killed, ops };
}

const QA_APP = "/r/build/AmbientQA.app/Contents/MacOS/AmbientQA";

test("a lock whose runner died is cleared, stopping the app that runner left running", async () => {
  const { dir, killed, ops } = fixture({ pid: "100", app: "200" }, { 200: QA_APP });
  assert.equal(await clearStaleLock(dir, ops), true);
  assert.deepEqual(killed, [[-200, "SIGTERM"]]);
  assert.ok(!existsSync(dir));
});

test("a lock held by a live runner is left alone, with its app", async () => {
  const { dir, killed, ops } = fixture({ pid: "100", app: "200" }, { 100: "node qa-run.ts", 200: QA_APP });
  assert.equal(await clearStaleLock(dir, ops), false);
  assert.deepEqual(killed, []);
  assert.ok(existsSync(dir));
});

test("a reused pid that isn't the QA app is never signalled", async () => {
  const { dir, killed, ops } = fixture({ pid: "100", app: "200" }, { 200: "/Applications/Safari.app/Contents/MacOS/Safari" });
  assert.equal(await clearStaleLock(dir, ops), true);
  assert.deepEqual(killed, []);
});

test("an app that ignores SIGTERM is killed", async () => {
  const { dir, killed, ops } = fixture({ pid: "100", app: "200" }, { 200: QA_APP });
  ops.kill = (pid, signal) => {
    killed.push([pid, signal]);
  };
  await clearStaleLock(dir, ops);
  assert.deepEqual(killed, [[-200, "SIGTERM"], [-200, "SIGKILL"]]);
});

test("the dead runner's case folder is removed, and only a case folder", async () => {
  const folder = mkdtempSync("/tmp/aq.");
  const { dir, ops } = fixture({ pid: "100", folder }, {});
  await clearStaleLock(dir, ops);
  assert.ok(!existsSync(folder));
  const other = mkdtempSync(join(tmpdir(), "keep."));
  const second = fixture({ pid: "100", folder: other }, {});
  await clearStaleLock(second.dir, second.ops);
  assert.ok(existsSync(other));
});
