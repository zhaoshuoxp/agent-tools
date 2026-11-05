#!/bin/bash
set -euo pipefail
PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_BIN="${USAGE_CODEX_BIN:-}"
if [[ -z "$CODEX_BIN" ]]; then
  for candidate in "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex" "/Applications/Codex.app/Contents/Resources/codex"; do
    if [[ -x "$candidate" ]]; then CODEX_BIN="$candidate"; break; fi
  done
fi
if [[ -z "$CODEX_BIN" ]]; then CODEX_BIN="$(command -v codex || true)"; fi
if [[ -z "$CODEX_BIN" ]]; then
  echo "The ChatGPT bundled Codex CLI was not found. Install or update ChatGPT first."
  exit 1
fi
NODE_BIN="$(command -v node || true)"
if [[ -z "$NODE_BIN" ]]; then
  for candidate in /opt/homebrew/bin/node /usr/local/bin/node; do
    if [[ -x "$candidate" ]]; then NODE_BIN="$candidate"; break; fi
  done
fi
if [[ -z "$NODE_BIN" ]]; then echo "Install Node.js 22 or newer, then run Install.command again."; exit 1; fi
"$NODE_BIN" -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Node.js 22 or newer is required."); process.exit(1); }'
if [[ ! -f "$PACKAGE_DIR/plugins/usage-meter/dist/server.mjs" ]]; then
  echo "The prebuilt plugin is missing. Run npm ci and npm run build in this folder."
  exit 1
fi
"$CODEX_BIN" plugin marketplace add "$PACKAGE_DIR"
echo
echo "The local marketplace is registered."
echo "Restart ChatGPT, open Plugins, select ChatGPT Usage Local, and install Usage Meter."
echo "Then open Usage Meter from the sidebar or a conversation panel."
echo "Keep this folder in place while the local marketplace is registered."
