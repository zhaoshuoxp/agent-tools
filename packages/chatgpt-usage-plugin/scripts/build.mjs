import { build } from "esbuild";
import { readFile, writeFile, mkdir, copyFile, access, cp, mkdtemp, rm } from "node:fs/promises";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";

const root = fileURLToPath(new URL("../", import.meta.url));
const dist = join(root, "plugins/usage-meter/dist");
await mkdir(dist, { recursive: true });
// Stage inputs outside protected macOS folders before starting the native bundler.
const staging = await mkdtemp(join(tmpdir(), "chatgpt-usage-build-"));
try {
  await cp(join(root, "src"), join(staging, "src"), { recursive: true });
  await cp(join(root, "node_modules"), join(staging, "node_modules"), { recursive: true });
  const widget = await build({
    absWorkingDir: staging, entryPoints: ["src/widget.mjs"], bundle: true, format: "esm", platform: "browser",
    target: "es2022", minify: true, write: false, legalComments: "inline", metafile: true,
  });
  const widgetStyles = await readFile(join(root, "src/widget.css"), "utf8");
  const html = (await readFile(join(root, "src/widget.html"), "utf8"))
    .replace("/* STYLES */", () => widgetStyles)
    .replace("/* SCRIPT */", () => widget.outputFiles[0].text.replace(/<\/script/gi, "<\\/script"));
  await writeFile(join(dist, "widget.html"), html);
  const server = await build({
    absWorkingDir: staging, entryPoints: ["src/server.mjs"], outfile: join(staging, "dist/server.mjs"),
    bundle: true, format: "esm", platform: "node", target: "node22", minify: true,
    legalComments: "inline", metafile: true,
    banner: { js: "import { createRequire } from 'node:module'; const require = createRequire(import.meta.url);" },
  });
  await copyFile(join(staging, "dist/server.mjs"), join(dist, "server.mjs"));
  const packages = new Set();
  for (const input of [...Object.keys(widget.metafile.inputs), ...Object.keys(server.metafile.inputs)]) {
    if (!input.includes("node_modules/")) continue;
    let dir = dirname(resolve(staging, input));
    while (dir.startsWith(join(staging, "node_modules"))) {
      try {
        const pkg = JSON.parse(await readFile(join(dir, "package.json"), "utf8"));
        if (pkg.name) { packages.add(dir); break; }
      } catch { /* Continue to the package root. */ }
      dir = dirname(dir);
    }
  }
  const notices = [];
  for (const dir of [...packages].sort()) {
    const pkg = JSON.parse(await readFile(join(dir, "package.json"), "utf8"));
    let licenseText = "";
    for (const filename of ["LICENSE", "LICENSE.md", "LICENSE.txt", "license", "LICENCE", "LICENSE-MIT", "LICENSE-MIT.txt"]) {
      try { licenseText = await readFile(join(dir, filename), "utf8"); break; } catch { /* Optional spelling. */ }
    }
    notices.push(`${pkg.name}@${pkg.version} (${pkg.license ?? "see package"})\n${licenseText}`);
  }
  await writeFile(join(dist, "THIRD_PARTY_NOTICES.txt"), notices.join("\n\n--------------------\n\n"));
  await copyFile(join(root, "LICENSE"), join(root, "plugins/usage-meter/LICENSE"));
  console.log("Built the self-contained local plugin. Node.js 22+ is required at runtime.");
} finally { await rm(staging, { recursive: true, force: true }); }
