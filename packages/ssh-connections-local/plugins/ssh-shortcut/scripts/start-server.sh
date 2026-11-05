#!/bin/bash
set -euo pipefail
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BIN="$(command -v node || true)"
if [[ -z "$NODE_BIN" ]]; then
  for candidate in /opt/homebrew/bin/node /usr/local/bin/node; do
    if [[ -x "$candidate" ]]; then
      NODE_BIN="$candidate"
      break
    fi
  done
fi
if [[ -z "$NODE_BIN" ]]; then
  echo "SSH Connections requires Node.js 20 or newer. Install Node.js and restart ChatGPT." >&2
  exit 1
fi
exec "$NODE_BIN" "$PLUGIN_DIR/dist/server.cjs"
