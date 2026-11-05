import { mkdir, readFile, writeFile } from "node:fs/promises";
import { build } from "esbuild";

await mkdir("dist", { recursive: true });
await build({
  entryPoints: ["src/entry.mjs"],
  outfile: "dist/server.cjs",
  bundle: true,
  platform: "node",
  target: "node20",
  format: "cjs",
  minify: true,
  legalComments: "eof",
});
const widget = await build({
  entryPoints: ["src/widget.js"],
  bundle: true,
  platform: "browser",
  format: "esm",
  minify: true,
  legalComments: "eof",
  write: false,
});
const script = widget.outputFiles[0].text.replace(/<\/script/gi, "<\\/script");
const template = await readFile("src/widget.html", "utf8");
await writeFile("dist/widget.html", template.replace("<!-- WIDGET_SCRIPT -->", `<script type="module">${script}</script>`));
