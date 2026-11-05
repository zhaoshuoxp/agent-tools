import { readFile } from "node:fs/promises";
import { McpServer } from "@modelcontextprotocol/server";
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { OpenAIExtensions } from "@openai/mcp-extensions/server";
import { z } from "zod/v4";
import { UsageReader, UsageError, readAccountLimits } from "./provider.mjs";
import { describeUsage } from "./usage.mjs";
import { createIndicator } from "./indicator.mjs";

const UI_URI = "ui://usage-meter/v1/index.html";
const reader = new UsageReader({ read: () => readAccountLimits({ timeoutMs: 8000 }) });
let lastSnapshot = null;
let readingFailed = false;
const publishers = new Set();
const icon = await readFile(new URL("../assets/icon.svg", import.meta.url), "utf8");
const icons = [{ src: `data:image/svg+xml,${encodeURIComponent(icon)}`, mimeType: "image/svg+xml", sizes: ["any"] }];
const annotations = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };

async function result(refresh = false) {
  try {
    const snapshot = await reader.get(refresh);
    lastSnapshot = snapshot;
    readingFailed = false;
    for (const publish of publishers) publish();
    return { structuredContent: snapshot, content: [{ type: "text", text: describeUsage(snapshot) }] };
  } catch (error) {
    readingFailed = true;
    for (const publish of publishers) publish();
    return {
      isError: true,
      structuredContent: {
        error: {
          code: error instanceof UsageError ? error.code : "USAGE_UNAVAILABLE",
          message: error instanceof UsageError ? error.message : "Usage is unavailable. Refresh to try again.",
        },
      },
      content: [{ type: "text", text: error instanceof UsageError ? error.message : "Usage is unavailable." }],
    };
  }
}

serveStdio(async () => {
  // Populate the native entrypoint before the host discovers its tool metadata.
  await result();
  const initial = createIndicator(lastSnapshot, { error: readingFailed });
  const server = new McpServer({ name: "usage-meter", title: "Usage Meter", version: "1.1.2", icons });
  new OpenAIExtensions(server);
  server.registerResource("usage-meter", UI_URI, { mimeType: "text/html;profile=mcp-app" }, async () => ({
    contents: [{
      uri: UI_URI,
      mimeType: "text/html;profile=mcp-app",
      text: await readFile(new URL("./widget.html", import.meta.url), "utf8"),
      _meta: {
        ui: { prefersBorder: false, csp: { connectDomains: [], resourceDomains: [] } },
        "openai/ui": { preferredDisplayMode: "fullscreen", availableDisplayModes: ["inline", "fullscreen"] },
      },
    }],
  }));
  const entrypoint = server.registerTool("usage.open", {
    title: initial.title,
    description: "Open reported 5-hour and weekly ChatGPT Work / Codex usage limits and reset times for the local account.",
    inputSchema: z.object({}),
    annotations,
    icons: initial.icons,
    _meta: {
      ui: { resourceUri: UI_URI, visibility: ["model", "app"] },
      "openai/ui": { entrypoints: [{ type: "global" }, { type: "thread" }] },
    },
  }, async () => {
    const output = await result();
    // Keep the entrypoint usable when the account cannot supply a reading.
    delete output.isError;
    return output;
  });
  server.registerTool("usage.read", {
    title: "Refresh usage",
    description: "Read the current local account usage snapshot without starting a model request.",
    inputSchema: z.object({ refresh: z.boolean().optional() }),
    annotations,
    _meta: { ui: { visibility: ["app"] } },
  }, async ({ refresh }) => result(refresh));
  let published = JSON.stringify([initial.title, initial.icons]);
  const publish = () => {
    const indicator = createIndicator(lastSnapshot, { error: readingFailed });
    const signature = JSON.stringify([indicator.title, indicator.icons]);
    if (signature === published) return;
    published = signature;
    // The SDK emits the standard tools/list_changed notification on update.
    entrypoint.update({ title: indicator.title, icons: indicator.icons });
  };
  publishers.add(publish);
  const timer = setInterval(() => {
    if (server.isConnected()) void result(true);
  }, 60000);
  timer.unref();
  const previousClose = server.server.onclose;
  server.server.onclose = () => {
    clearInterval(timer);
    publishers.delete(publish);
    previousClose?.();
  };
  return server;
});
