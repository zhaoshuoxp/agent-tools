#!/bin/bash
set -euo pipefail
PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_BIN="${USAGE_CODEX_BIN:-/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex}"
if [[ ! -x "$CODEX_BIN" ]]; then CODEX_BIN="$(command -v codex || true)"; fi
if [[ -z "$CODEX_BIN" ]]; then echo "The Codex CLI was not found."; exit 1; fi
"$CODEX_BIN" plugin marketplace add "$PACKAGE_DIR"
"$CODEX_BIN" plugin add usage-meter@chatgpt-usage-local
echo "Usage Meter was updated. Refresh or reconnect the plugin in ChatGPT."
echo "If the sidebar retains the previous icon, restart ChatGPT."
