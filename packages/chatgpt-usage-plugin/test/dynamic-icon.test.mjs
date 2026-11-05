import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, copyFile, chmod, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { ToolListChangedNotificationSchema } from "@modelcontextprotocol/sdk/types.js";

const plugin = fileURLToPath(new URL("../plugins/usage-meter/", import.meta.url));

test("an MCP host receives updated icon metadata, stale state, and recovery notifications", async () => {
  const temp = await mkdtemp(join(tmpdir(), "usage-meter-icon-test-"));
  const executable = join(temp, "codex-fixture.mjs");
  const stateFile = join(temp, "quota.json");
  await copyFile(new URL("./fake-codex.mjs", import.meta.url), executable);
  await chmod(executable, 0o755);
  const setState = value => writeFile(stateFile, JSON.stringify({ resetsAt: Math.floor(Date.now() / 1000) + 3600, ...value }));
  await setState({ usedPercent: 14 });
  const transport = new StdioClientTransport({
    command: "/bin/bash", args: ["./scripts/start-server.sh"], cwd: plugin, stderr: "pipe",
    env: { USAGE_CODEX_BIN: executable, USAGE_FIXTURE_STATE_FILE: stateFile, PATH: process.env.PATH },
  });
  const client = new Client({ name: "usage-icon-host-test", version: "1.0.0" });
  try {
    await client.connect(transport);
    const getEntry = async () => (await client.listTools()).tools.find(tool => tool.name === "usage.open");
    const first = await getEntry();
    assert.match(first.title, /Week: 14% used/);
    const originalIcon = first.icons[0].src;
    for (const state of [{ usedPercent: 41 }, { error: true }, { usedPercent: 8 }]) {
      await setState(state);
      let notify;
      const changed = new Promise(resolve => { notify = resolve; });
      client.setNotificationHandler(ToolListChangedNotificationSchema, notify);
      let timeout;
      const deadline = new Promise((_, reject) => {
        timeout = setTimeout(() => reject(new Error("The server did not publish tools/list_changed.")), 3000);
      });
      try {
        await client.callTool({ name: "usage.read", arguments: { refresh: true } });
        await Promise.race([changed, deadline]);
      } finally { clearTimeout(timeout); }
      const current = await getEntry();
      if (state.error) {
        assert.match(current.title, /out of date/);
        assert.match(current.title, /Week: 41% used/);
      } else {
        assert.match(current.title, new RegExp(`Week: ${state.usedPercent}% used`));
        assert.doesNotMatch(current.title, /out of date/);
      }
      assert.notEqual(current.icons[0].src, originalIcon);
      assert.deepEqual(current._meta["openai/ui"].entrypoints, [{ type: "global" }, { type: "thread" }]);
    }
  } finally {
    await client.close();
    await rm(temp, { recursive: true, force: true });
  }
});
