import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export const SETTINGS_URL = "codex://settings/connections/ssh";
export const RESOURCE_URI = "ui://ssh-shortcut/v1.html";
const execFileAsync = promisify(execFile);

export async function openSettings({ platform = process.platform, launch = execFileAsync } = {}) {
  if (platform !== "darwin") {
    throw new Error("SSH Connections requires the ChatGPT desktop app on macOS.");
  }
  await launch("/usr/bin/open", [SETTINGS_URL], { timeout: 10000 });
}

export function createServer({ widgetHtml, iconSvg, open = openSettings }) {
  const server = new McpServer({ name: "SSH Connections", version: "1.0.2" });
  server.registerResource("ssh-shortcut", RESOURCE_URI, {
    mimeType: "text/html;profile=mcp-app",
    description: "A shortcut to the app's SSH connection settings.",
  }, async () => ({
    contents: [{
      uri: RESOURCE_URI,
      mimeType: "text/html;profile=mcp-app",
      text: widgetHtml,
      _meta: { ui: { prefersBorder: false, csp: { connectDomains: [], resourceDomains: [] } } },
    }],
  }));

  server.registerTool("open_ssh_settings", {
    title: "SSH Connections",
    description: "Open Settings > Connections > SSH in the ChatGPT desktop app on this Mac.",
    inputSchema: z.strictObject({}),
    outputSchema: {
      opened: z.boolean(),
      url: z.literal(SETTINGS_URL),
      message: z.string(),
    },
    icons: [{
      src: `data:image/svg+xml;base64,${Buffer.from(iconSvg).toString("base64")}`,
      mimeType: "image/svg+xml",
      sizes: ["any"],
    }],
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
    },
    _meta: {
      ui: { resourceUri: RESOURCE_URI, visibility: ["model", "app"] },
      "openai/ui": { entrypoints: [{ type: "global" }] },
    },
  }, async () => {
    let opened = false;
    let message = "SSH settings requested. Use the switches in Settings to enable or disable each host.";
    try {
      await open();
      opened = true;
    } catch {
      message = "Could not open SSH settings. Open ChatGPT and choose Settings > Connections > SSH.";
    }
    return {
      ...(opened ? {} : { isError: true }),
      structuredContent: { opened, url: SETTINGS_URL, message },
      content: [{ type: "text", text: message }],
    };
  });
  return server;
}
