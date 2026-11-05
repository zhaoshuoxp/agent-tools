import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { readAccountLimits, UsageReader } from "../src/provider.mjs";

const fixture = fileURLToPath(new URL("./fake-codex.mjs", import.meta.url));
const spawnFixture = mode => (command, args, options) => {
  assert.deepEqual(args, ["app-server", "--listen", "stdio://"]);
  return spawn(process.execPath, [fixture, mode], options);
};

test("the provider completes the handshake and reads usage without starting a turn", async () => {
  const result = await readAccountLimits({ executable: "test-codex", spawnProcess: spawnFixture("success") });
  assert.equal(result.rateLimits.primary.usedPercent, 23);
});

test("private service diagnostics are not returned to the widget", async () => {
  await assert.rejects(readAccountLimits({ executable: "test-codex", spawnProcess: spawnFixture("error") }), error => {
    assert.equal(error.code, "USAGE_UNAVAILABLE");
    assert.doesNotMatch(error.message, /SECRET_SENTINEL/);
    return true;
  });
});

test("an exited or unresponsive service returns a bounded failure", async () => {
  await assert.rejects(readAccountLimits({ executable: "test-codex", spawnProcess: spawnFixture("exit") }), { code: "CLIENT_UNAVAILABLE" });
  await assert.rejects(readAccountLimits({ executable: "test-codex", spawnProcess: spawnFixture("timeout"), timeoutMs: 200 }), { code: "TIMEOUT" });
});

test("a missing executable returns a useful installation error", async () => {
  await assert.rejects(readAccountLimits({ executable: "/nonexistent/usage-meter-codex" }), { code: "CLI_MISSING" });
});

test("concurrent refreshes share one read and failures invalidate the previous snapshot", async () => {
  let calls = 0;
  let fail = false;
  const reader = new UsageReader({
    now: () => 1000,
    read: async () => {
      calls++;
      await new Promise(resolve => setTimeout(resolve, 10));
      if (fail) throw new Error("offline");
      return { rateLimits: { primary: { usedPercent: 14, windowDurationMins: 10080, resetsAt: 2000 } } };
    },
  });
  const [first, second] = await Promise.all([reader.get(true), reader.get(true)]);
  assert.equal(calls, 1);
  assert.equal(first, second);
  await reader.get();
  assert.equal(calls, 1);
  fail = true;
  await assert.rejects(reader.get(true), /offline/);
  assert.equal(reader.cached, null);
  fail = false;
  await reader.get();
  assert.equal(calls, 3);
});
