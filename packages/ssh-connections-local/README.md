# SSH Connections Local

A local marketplace containing the SSH Connections sidebar shortcut for the ChatGPT macOS app.

Requires ChatGPT desktop for macOS with local plugins enabled and Node.js 20 or newer. All JavaScript runtime dependencies are bundled.

Unzip the release archive and move the extracted folder to a permanent location before installing. Keep that folder in place because the local marketplace records its path.

Double-click `Install.command`, or run these commands from this folder:

```bash
codex plugin marketplace add .
codex plugin add ssh-shortcut@ssh-connections-local
```

Restart ChatGPT after installation when your running work permits. Look for **SSH Connections** in the sidebar's plugin apps. Click it to open **Settings > Connections > SSH**. Each host uses the app's existing switch. Sidebar placement and pin controls depend on your app version.

See `plugins/ssh-shortcut/README.md` for requirements, behavior, development, and removal.
