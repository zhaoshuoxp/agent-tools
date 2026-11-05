import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createServer } from "./server.mjs";

const dist = dirname(resolve(process.argv[1]));
const server = createServer({
  widgetHtml: readFileSync(resolve(dist, "widget.html"), "utf8"),
  iconSvg: readFileSync(resolve(dist, "../assets/icon.svg"), "utf8"),
});
server.connect(new StdioServerTransport()).catch((error) => {
  console.error("SSH Connections could not start:", error.message);
  process.exitCode = 1;
});
