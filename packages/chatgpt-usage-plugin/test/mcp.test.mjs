import test from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const plugin = fileURLToPath(new URL("../plugins/usage-meter/", import.meta.url));

test("the built plugin advertises native entrypoints and serves an offline UI resource", async () => {
  const transport = new StdioClientTransport({
    command: "/bin/bash", args: ["./scripts/start-server.sh"], cwd: plugin, stderr: "pipe",
    env: { USAGE_CODEX_BIN: "/nonexistent/usage-meter-codex", PATH: process.env.PATH },
  });
  const client = new Client({ name: "usage-meter-test", version: "1.0.0" });
  try {
    await client.connect(transport);
    const { tools } = await client.listTools();
    const open = tools.find(tool => tool.name === "usage.open");
    const read = tools.find(tool => tool.name === "usage.read");
    assert.deepEqual(open._meta["openai/ui"].entrypoints, [{ type: "global" }, { type: "thread" }]);
    assert.equal(read.annotations.readOnlyHint, true);
    const resource = await client.readResource({ uri: open._meta.ui.resourceUri });
    assert.equal(resource.contents[0].mimeType, "text/html;profile=mcp-app");
    assert.match(resource.contents[0].text, /Show beside conversation context/);
    assert.doesNotMatch(resource.contents[0].text, /<script[^>]+src=/);
    const script = resource.contents[0].text.match(/<script type="module">([\s\S]*?)<\/script>/)?.[1];
    assert.ok(script, "The self-contained widget must include a module script.");
    const syntax = spawnSync(process.execPath, ["--input-type=module", "--check"], { input: script, encoding: "utf8" });
    assert.equal(syntax.status, 0, syntax.stderr);
    const opened = await client.callTool({ name: "usage.open", arguments: {} });
    assert.equal(opened.structuredContent.error.code, "CLI_MISSING");
    assert.notEqual(opened.isError, true, "The panel should still open when its data source is unavailable.");
  } finally { await client.close(); }
});
