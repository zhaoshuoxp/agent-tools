#!/bin/bash
set -euo pipefail
MARKETPLACE_ROOT="$(cd "$(dirname "$0")" && pwd)"
CODEX_BIN="$(command -v codex || true)"
if [[ -z "$CODEX_BIN" ]]; then
  CODEX_BIN="/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
fi
if [[ ! -x "$CODEX_BIN" ]]; then
  echo "Install the ChatGPT desktop app or make the codex command available, then try again." >&2
  exit 1
fi
"$CODEX_BIN" plugin marketplace add "$MARKETPLACE_ROOT" --json
"$CODEX_BIN" plugin add ssh-shortcut@ssh-connections-local --json
echo "SSH Connections installed. Restart ChatGPT when your running work permits."
