import { test } from "node:test";
import assert from "node:assert/strict";
import { check, globToRegExp, parseCases, select } from "./qa-cases.ts";

const SAMPLE = `# Island

### ISL-001 · Needs-you bloom names the need

- **Priority:** P0
- **Type:** both
- **Covers:** \`Sources/AmbientApp/Island/**\`, \`Sources/AmbientContracts/Need.swift\`
- **Automated by:** \`NeedTests\`
- **Needs:** Mac with a notch

**Steps**

1. Ask for permission.

**Expected**

- It blooms amber.

### ISL-002 · Hover list

- **Priority:** P2
- **Type:** manual
- **Covers:** \`Sources/AmbientApp/Island/IslandHover.swift\`
- **Automated by:** none
- **Needs:** nothing special

**Known gap:** the list is not sorted.

## Notes

### not a case
`;

test("cases parse with every field", () => {
  const { cases, errors } = parseCases(SAMPLE, "qa/cases/island.md");
  assert.equal(cases.length, 2);
  assert.deepEqual(errors, ["qa/cases/island.md:31: level-3 heading is not a case id: ### not a case"]);
  const [a, b] = cases;
  assert.equal(a.id, "ISL-001");
  assert.equal(a.title, "Needs-you bloom names the need");
  assert.equal(a.line, 3);
  assert.equal(a.priority, "P0");
  assert.equal(a.type, "both");
  assert.deepEqual(a.covers, ["Sources/AmbientApp/Island/**", "Sources/AmbientContracts/Need.swift"]);
  assert.deepEqual(a.automatedBy, ["NeedTests"]);
  assert.equal(a.knownGap, false);
  assert.deepEqual(b.automatedBy, []);
  assert.equal(b.knownGap, true);
});

test("a case missing a field or with a bad value is reported", () => {
  const md = "### SET-001 · Thing\n\n- **Priority:** P4\n- **Type:** sometimes\n- **Covers:** none\n";
  const { errors } = parseCases(md, "x.md");
  assert.ok(errors.some((e) => e.includes('priority "P4"')));
  assert.ok(errors.some((e) => e.includes('type "sometimes"')));
  assert.ok(errors.some((e) => e.includes("names no path")));
  assert.ok(errors.some((e) => e.includes("missing **Automated by:**")));
  assert.ok(errors.some((e) => e.includes("missing **Needs:**")));
});

test("globs: * stays in a folder, ** crosses folders, trailing / is the whole folder", () => {
  assert.ok(globToRegExp("Sources/A/*.swift").test("Sources/A/x.swift"));
  assert.ok(!globToRegExp("Sources/A/*.swift").test("Sources/A/B/x.swift"));
  assert.ok(globToRegExp("Sources/A/**").test("Sources/A/B/x.swift"));
  assert.ok(globToRegExp("Sources/**/x.swift").test("Sources/x.swift"));
  assert.ok(globToRegExp("Sources/**/x.swift").test("Sources/A/B/x.swift"));
  assert.ok(globToRegExp("Drivers/").test("Drivers/AmbientSpeaker/a.c"));
  assert.ok(!globToRegExp("Sources/A.swift").test("Sources/AxSwift"));
  assert.ok(!globToRegExp("Sources/A.swift").test("Sources/A.swift.bak"));
});

test("select picks covering cases, sorts by priority, and lists uncovered code", () => {
  const { cases } = parseCases(SAMPLE, "qa/cases/island.md");
  const sel = select(cases, [
    "Sources/AmbientApp/Island/IslandHover.swift",
    "Sources/AmbientApp/Pet/Pet.swift",
    "README.md",
  ]);
  assert.deepEqual(sel.selected.map((s) => s.qaCase.id), ["ISL-001", "ISL-002"]);
  assert.deepEqual(sel.uncovered, ["Sources/AmbientApp/Pet/Pet.swift"]);
  assert.deepEqual(sel.ignored, ["README.md"]);
});

test("select adds P0 cases only when asked", () => {
  const { cases } = parseCases(SAMPLE, "qa/cases/island.md");
  assert.equal(select(cases, ["README.md"]).selected.length, 0);
  const withP0 = select(cases, ["README.md"], true);
  assert.deepEqual(withP0.selected.map((s) => [s.qaCase.id, s.reason]), [["ISL-001", "P0"]]);
});

test("check reports duplicates, dead globs, missing tests and uncovered code", () => {
  const { cases, errors } = parseCases(SAMPLE + SAMPLE.replace("# Island", ""), "qa/cases/island.md");
  const problems = check({
    cases,
    parseErrors: [],
    repoFiles: ["Sources/AmbientApp/Island/Island.swift", "Sources/AmbientApp/Pet/Pet.swift", "README.md"],
    testSource: "struct Other {}",
  });
  assert.ok(errors.length > 0);
  assert.ok(problems.some((p) => p.includes("duplicate id ISL-001")));
  assert.ok(problems.some((p) => p.includes("`Sources/AmbientContracts/Need.swift` matches no file")));
  assert.ok(problems.some((p) => p.includes("`NeedTests` is not found")));
  assert.ok(problems.includes("no QA case covers Sources/AmbientApp/Pet/Pet.swift"));
  assert.ok(!problems.some((p) => p.includes("README.md")));
});

test("Automated by matches a test function or a qualified name", () => {
  const { cases } = parseCases(SAMPLE.replace("`NeedTests`", "`NeedTests.bloomsAmber()`"), "x.md");
  const problems = check({
    cases: cases.slice(0, 1),
    parseErrors: [],
    repoFiles: ["Sources/AmbientApp/Island/I.swift", "Sources/AmbientContracts/Need.swift"],
    testSource: "@Test func bloomsAmber() {}",
  });
  assert.deepEqual(problems, []);
});
