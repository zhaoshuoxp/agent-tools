import test from "node:test";
import assert from "node:assert/strict";
import { normalizeUsage, nextReset, describeUsage } from "../src/usage.mjs";

const weekly = { usedPercent: 14, windowDurationMins: 10080, resetsAt: 1794094781 };
const fiveHour = { usedPercent: 39, windowDurationMins: 300, resetsAt: 1793918200 };

test("a weekly-only primary window stays weekly and does not invent a 5-hour limit", () => {
  const snapshot = normalizeUsage({ rateLimits: { limitId: "codex", primary: weekly, secondary: null } }, 1793910100);
  assert.equal(snapshot.buckets[0].weekly.usedPercent, 14);
  assert.equal(snapshot.buckets[0].fiveHour, null);
  assert.equal(nextReset(snapshot.buckets[0], 1793910100), weekly.resetsAt);
  assert.doesNotMatch(describeUsage(snapshot), /5-hour/);
});

test("window duration determines the label when primary and secondary are swapped", () => {
  const [bucket] = normalizeUsage({ rateLimits: { primary: weekly, secondary: fiveHour } }).buckets;
  assert.equal(bucket.weekly.windowDurationMins, 10080);
  assert.equal(bucket.fiveHour.windowDurationMins, 300);
  assert.equal(nextReset(bucket, 1793910100), fiveHour.resetsAt);
});

test("the bucket map takes precedence over the legacy view without mixing quotas", () => {
  const snapshot = normalizeUsage({
    rateLimits: { primary: { ...weekly, usedPercent: 99 } },
    rateLimitsByLimitId: {
      special: { limitName: "Special model", primary: { ...weekly, usedPercent: 81 } },
      codex: { primary: weekly, secondary: fiveHour },
    },
  });
  assert.deepEqual(snapshot.buckets.map(bucket => [bucket.id, bucket.weekly.usedPercent]), [["codex", 14], ["special", 81]]);
});

test("missing values stay unknown and zero remains a valid reading", () => {
  const [unknown] = normalizeUsage({ rateLimits: { primary: { windowDurationMins: 10080, usedPercent: null, resetsAt: null } } }).buckets;
  const [zero] = normalizeUsage({ rateLimits: { primary: { ...weekly, usedPercent: 0 } } }).buckets;
  assert.equal(unknown.weekly.usedPercent, null);
  assert.equal(unknown.weekly.resetsAt, null);
  assert.match(describeUsage({ buckets: [unknown] }), /Not reported/);
  assert.equal(zero.weekly.usedPercent, 0);
  assert.equal(normalizeUsage({ rateLimits: null }).buckets.length, 0);
});

test("unsupported windows and invalid timestamps do not produce false reset times", () => {
  const [bucket] = normalizeUsage({ rateLimits: {
    primary: { usedPercent: 30, windowDurationMins: 60, resetsAt: 1794094781 },
    secondary: { usedPercent: NaN, windowDurationMins: 10080, resetsAt: Infinity },
  } }).buckets;
  assert.equal(bucket.fiveHour, null);
  assert.equal(bucket.weekly.usedPercent, null);
  assert.equal(nextReset(bucket), null);
});

test("passing a reset never changes recorded usage to zero", () => {
  const [bucket] = normalizeUsage({ rateLimits: { primary: weekly } }).buckets;
  assert.equal(nextReset(bucket, weekly.resetsAt + 1), null);
  assert.equal(bucket.weekly.usedPercent, 14);
});
