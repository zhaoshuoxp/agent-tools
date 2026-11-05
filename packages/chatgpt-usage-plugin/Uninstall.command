#!/bin/bash
set -euo pipefail
CODEX_BIN="${USAGE_CODEX_BIN:-/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex}"
if [[ ! -x "$CODEX_BIN" ]]; then CODEX_BIN="$(command -v codex || true)"; fi
if [[ -z "$CODEX_BIN" ]]; then echo "The Codex CLI was not found."; exit 1; fi
"$CODEX_BIN" plugin remove usage-meter@chatgpt-usage-local
"$CODEX_BIN" plugin marketplace remove chatgpt-usage-local
echo "Usage Meter was removed. Restart ChatGPT to refresh navigation."
