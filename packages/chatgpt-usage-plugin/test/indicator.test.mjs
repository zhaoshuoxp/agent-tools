import test from "node:test";
import assert from "node:assert/strict";
import { createIndicator } from "../src/indicator.mjs";
import { normalizeUsage } from "../src/usage.mjs";

const at = 1793910000;
const weekly = { usedPercent: 14, windowDurationMins: 10080, resetsAt: at + 12000 };
const snapshot = raw => normalizeUsage({ rateLimits: raw }, at);

test("a weekly-only icon shows used quota and includes a timestamped reset title", () => {
  const icon = createIndicator(snapshot({ limitId: "codex", primary: weekly }), { now: at });
  assert.match(icon.svg, /data-window="weekly"/);
  assert.match(icon.svg, />14<\/text>/);
  assert.match(icon.title, /Week: 14% used; resets/);
  assert.match(icon.title, /As of/);
  assert.doesNotMatch(icon.title, /5h:/);
  assert.equal(icon.icons[0].mimeType, "image/svg+xml");
  assert.equal(icon.icons[0].theme, undefined, "The host must receive the same mask-safe artwork for either theme.");
});

test("a second reported window adds a distinct inner ring and reset line", () => {
  const icon = createIndicator(snapshot({
    primary: weekly,
    secondary: { usedPercent: 39, windowDurationMins: 300, resetsAt: at + 3600 },
  }), { now: at });
  assert.match(icon.svg, /data-window="weekly"/);
  assert.match(icon.svg, /data-window="five-hour"/);
  assert.match(icon.title, /5h: 39% used; resets/);
  assert.match(icon.title, /Week: 14% used; resets/);
});

test("an unknown quota is a question mark and a known zero remains zero", () => {
  const unknown = createIndicator(null, { now: at });
  assert.match(unknown.svg, />\?<\/text>/);
  assert.doesNotMatch(unknown.title, /0%/);
  const zero = createIndicator(snapshot({ primary: { ...weekly, usedPercent: 0 } }), { now: at });
  assert.match(zero.svg, />0<\/text>/);
  assert.match(zero.title, /Week: 0% used/);
});

test("failed reads and elapsed reset times never create a fresh zero reading", () => {
  const stale = createIndicator(snapshot({ primary: weekly }), { now: at + 300, error: true });
  assert.match(stale.title, /out of date/);
  assert.match(stale.svg, />14<\/text>/);
  const due = createIndicator(snapshot({ primary: weekly }), { now: weekly.resetsAt + 1 });
  assert.match(due.title, /reset due/);
  assert.match(due.title, /14% used/);
});

test("the caption shows the outer window's local reset date even when the inner window resets sooner", () => {
  const weeklyReset = new Date(2026, 10, 7, 15, 39).getTime() / 1000;
  const fiveHourReset = new Date(2026, 10, 4, 20, 0).getTime() / 1000;
  const icon = createIndicator(snapshot({
    primary: { ...weekly, resetsAt: weeklyReset },
    secondary: { usedPercent: 39, windowDurationMins: 300, resetsAt: fiveHourReset },
  }), { now: fiveHourReset - 1000 });
  assert.match(icon.svg, /data-label="reset-date"[^>]*>11\.7<\/text>/);
  const unknown = createIndicator(snapshot({ primary: { ...weekly, resetsAt: null } }), { now: at });
  assert.match(unknown.svg, /data-label="reset-date"[^>]*>--<\/text>/);
});
