import { test } from "node:test";
import assert from "node:assert/strict";
import { classify, parseScript } from "./qa-run.ts";

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
