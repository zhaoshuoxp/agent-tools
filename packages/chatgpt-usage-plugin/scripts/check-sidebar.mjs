import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const plugin = fileURLToPath(new URL("../plugins/usage-meter/", import.meta.url));
const client = new Client({ name: "usage-sidebar-check", version: "1.1.0" });
try {
  await client.connect(new StdioClientTransport({
    command: "/bin/bash", args: ["./scripts/start-server.sh"], cwd: plugin,
    env: process.env, stderr: "pipe",
  }));
  const tool = (await client.listTools()).tools.find(value => value.name === "usage.open");
  if (!tool?.icons?.length || /out of date|Quota not reported/.test(tool.title)) {
    throw new Error("The current account did not provide a fresh quota icon.");
  }
  console.log(tool.title);
  console.log(`Published ${tool.icons.length} mask-safe SVG icon(s) and the global sidebar entrypoint.`);
  console.log("This checks live MCP metadata; it does not inspect the app's rendered sidebar.");
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally { await client.close(); }
