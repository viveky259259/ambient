import { test } from "node:test";
import assert from "node:assert/strict";
import { chiSquare, render, summarize, wilson } from "./ab-stats.ts";
import { readFileSync } from "node:fs";
import { cleanVariant, downloadVariant, PREVIEW_HOST, variantFromBody, visitorThemeFile } from "../netlify/edge-functions/lib/ab-core.ts";

test("the test's tools work only locally and on draft deploys", () => {
  for (const host of ["localhost", "127.0.0.1", "[::1]", "ambient.localhost", "6740a1b2--yaml-cafe.netlify.app", "feat-x--yaml-cafe.netlify.app"]) {
    assert.ok(PREVIEW_HOST.test(host), host);
  }
  for (const host of ["yaml.cafe", "www.yaml.cafe", "yaml-cafe.netlify.app", "localhost.evil.com", "x--y.netlify.app.evil.com"]) {
    assert.ok(!PREVIEW_HOST.test(host), host);
  }
  // The loader carries its own copy of the pattern, since it runs in the browser.
  assert.ok(readFileSync(new URL("../site/themes/loader.js", import.meta.url), "utf8").includes(PREVIEW_HOST.toString()));
});

test("visitors get a theme's files, not the test's notes", () => {
  for (const path of ["/themes/loader.js", "/themes/system.css", "/themes/iris/theme.css", "/themes/iris/fonts.css", "/themes/iris/motif.js", "/themes/fonts/old-standard-tt-1a2b3c4d.woff2"]) {
    assert.ok(visitorThemeFile(path), path);
  }
  for (const path of ["/themes", "/themes/", "/themes/index.html", "/themes/manifest.json", "/themes/README.md", "/themes/iris/meta.json", "/themes/fonts/README.md", "/themes/../index.html"]) {
    assert.ok(!visitorThemeFile(path), path);
  }
});

test("variants are checked before they're stored", () => {
  assert.equal(cleanVariant("signal-box"), "signal-box");
  assert.equal(cleanVariant("../x"), "");
  assert.equal(cleanVariant("A"), "");
  assert.equal(variantFromBody('{"v":"iris"}'), "iris");
  assert.equal(variantFromBody("not json"), "");
  assert.equal(variantFromBody(`{"v":"${"a".repeat(300)}"}`), "");
});

test("only design-test downloads carry a variant", () => {
  assert.equal(downloadVariant("2026-11-20/0.10.0/site/US/iris/uuid"), "iris");
  assert.equal(downloadVariant("2026-11-20/0.10.0/brew/US/uuid"), null);
});

test("wilson gives a sensible range", () => {
  const [low, high] = wilson(10, 100);
  assert.ok(low > 0.05 && low < 0.06, `low ${low}`);
  assert.ok(high > 0.17 && high < 0.18, `high ${high}`);
  assert.deepEqual(wilson(0, 0), [0, 0]);
});

test("chi-square finds a real difference and ignores a tiny one", () => {
  const big = chiSquare([{ visitors: 1000, downloads: 50 }, { visitors: 1000, downloads: 120 }]);
  assert.ok(big.p < 0.0001, `p ${big.p}`);
  const small = chiSquare([{ visitors: 1000, downloads: 50 }, { visitors: 1000, downloads: 53 }]);
  assert.ok(small.p > 0.5, `p ${small.p}`);
  // df = 1, chi2 = 3.841 is the 5% point.
  assert.ok(Math.abs(chiSquare([{ visitors: 200, downloads: 20 }, { visitors: 200, downloads: 34 }]).p - 0.04) < 0.02);
});

test("summarize counts per variant, from a start day, including variants nobody has seen", () => {
  const views = ["2026-11-20/iris/a", "2026-11-20/iris/b", "2026-11-21/almanac/c", "2026-11-19/iris/old"];
  const downloads = ["2026-11-21/0.10.0/site/US/iris/x", "2026-11-21/0.10.0/brew/US/y", "2026-11-18/0.10.0/site/US/iris/old"];
  const s = summarize(views, downloads, ["almanac", "iris", "barometer"], "2026-11-20");
  assert.equal(s.visitors, 3);
  assert.equal(s.downloads, 1);
  assert.deepEqual(s.rows.map((r) => [r.variant, r.visitors, r.downloads]), [["iris", 2, 1], ["almanac", 1, 0], ["barometer", 0, 0]]);
  assert.match(render(s, 1000), /999 downloads to go/);
});

test("summarize leaves out variants that were never in the test", () => {
  const s = summarize(["2026-11-20/iris/a", "2026-11-20/forged/b"], ["2026-11-20/0.10.0/site/US/forged/x"], ["iris"], "", new Set(["iris", "almanac"]));
  assert.deepEqual(s.rows.map((r) => r.variant), ["iris"]);
  assert.equal(s.visitors, 1);
  assert.equal(s.downloads, 0);
});

test("a tiny sample doesn't top the table", () => {
  const views = [...Array(200)].map((_, i) => `2026-11-20/iris/${i}`).concat(["2026-11-20/prism/p"]);
  const downloads = [...Array(30)].map((_, i) => `2026-11-20/0.10.0/site/US/iris/${i}`).concat(["2026-11-20/0.10.0/site/US/prism/p"]);
  assert.deepEqual(summarize(views, downloads).rows.map((r) => r.variant), ["iris", "prism"]);
});
