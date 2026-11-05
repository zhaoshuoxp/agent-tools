import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createServer, openSettings, RESOURCE_URI, SETTINGS_URL } from "../src/server.mjs";

const widgetHtml = await readFile(new URL("../dist/widget.html", import.meta.url), "utf8");
const iconSvg = await readFile(new URL("../assets/icon.svg", import.meta.url), "utf8");

async function connect(t, open) {
  const server = createServer({ widgetHtml, iconSvg, open });
  const client = new Client({ name: "ssh-shortcut-test", version: "1.0.0" });
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  t.after(() => client.close());
  return client;
}

test("the opener requests only the documented SSH settings URL", async () => {
  const calls = [];
  await openSettings({ platform: "darwin", launch: async (...args) => calls.push(args) });
  assert.deepEqual(calls, [["/usr/bin/open", [SETTINGS_URL], { timeout: 10000 }]]);
});

test("unsupported systems fail before launching anything", async () => {
  await assert.rejects(openSettings({
    platform: "linux",
    launch: async () => assert.fail("must not launch"),
  }), /macOS/);
});

test("the sidebar tool opens settings once and exposes a self-contained UI", async (t) => {
  let launches = 0;
  const client = await connect(t, async () => { launches += 1; });
  const { tools } = await client.listTools();
  assert.equal(tools.length, 1);
  assert.deepEqual(tools[0]._meta["openai/ui"].entrypoints, [{ type: "global" }]);
  assert.equal(tools[0]._meta.ui.resourceUri, RESOURCE_URI);
  assert.deepEqual(tools[0].inputSchema.properties, {});
  assert.equal(tools[0].inputSchema.additionalProperties, false);

  const result = await client.callTool({ name: "open_ssh_settings", arguments: {} });
  assert.equal(result.structuredContent.opened, true);
  assert.equal(result.structuredContent.url, SETTINGS_URL);
  assert.equal(launches, 1);

  const resource = await client.readResource({ uri: RESOURCE_URI });
  const [content] = resource.contents;
  assert.equal(content.mimeType, "text/html;profile=mcp-app");
  assert.match(content.text, /Open SSH settings/);
  assert.doesNotMatch(content.text, /<script[^>]+src=|<link[^>]+href=/);
  assert.deepEqual(content._meta.ui.csp, { connectDomains: [], resourceDomains: [] });

  const invalid = await client.callTool({
    name: "open_ssh_settings",
    arguments: { url: "https://example.com" },
  });
  assert.equal(invalid.isError, true);
  assert.equal(launches, 1);
});

test("launch failures return an actionable error without claiming success", async (t) => {
  const client = await connect(t, async () => { throw new Error("Launch failed"); });
  const result = await client.callTool({ name: "open_ssh_settings", arguments: {} });
  assert.equal(result.isError, true);
  assert.equal(result.structuredContent.opened, false);
  assert.match(result.structuredContent.message, /Settings > Connections > SSH/);
});

test("the bundled server and launcher complete a real stdio MCP handshake", async (t) => {
  const client = new Client({ name: "ssh-shortcut-bundle-test", version: "1.0.0" });
  const transport = new StdioClientTransport({
    command: "/bin/bash",
    args: [new URL("../scripts/start-server.sh", import.meta.url).pathname],
    stderr: "pipe",
  });
  const errors = [];
  transport.stderr?.on("data", (chunk) => errors.push(String(chunk)));
  t.after(() => client.close());
  await client.connect(transport);
  assert.equal((await client.listTools()).tools[0].name, "open_ssh_settings");
  const resource = await client.readResource({ uri: RESOURCE_URI });
  assert.match(resource.contents[0].text, /SSH Connections/);
  assert.equal(errors.join(""), "");
});
