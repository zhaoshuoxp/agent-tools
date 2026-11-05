# SSH Connections

A local ChatGPT macOS plugin with a sidebar entry that opens **Settings > Connections > SSH**. Click **SSH Connections** in the sidebar to request the settings page; use the app's switches to enable or disable each host. The plugin page includes an **Open SSH settings** button for reopening it.

## Requirements

- ChatGPT desktop for macOS with local plugins and sidebar extensions enabled.
- Node.js 20 or newer. The launcher detects Node.js on `PATH`, `/opt/homebrew/bin/node`, or `/usr/local/bin/node`.

The released `dist/` files include all JavaScript dependencies. Running the plugin requires no `npm install`, API key, network listener, or SSH credentials.

## Install

The containing `ssh-connections-local` folder is a local marketplace. From that folder:

```bash
codex plugin marketplace add .
codex plugin add ssh-shortcut@ssh-connections-local
```

Restart the ChatGPT desktop app after installation. Look for **SSH Connections** in the sidebar's plugin apps. If your app exposes a pin or favorites control for plugin apps, pin this entry there. The host controls sidebar placement and availability.

The installable plugin is at `plugins/ssh-shortcut/`. Keep the marketplace folder if you want to reinstall it later. Remove the plugin with:

```bash
codex plugin remove ssh-shortcut@ssh-connections-local
```

## Behavior and scope

The sidebar entry invokes the local MCP tool `open_ssh_settings`. The tool asks macOS to open the documented `codex://settings/connections/ssh` deep link. A successful result confirms that macOS accepted the launch request; it does not verify the visible page or the state of any connection.

The public plugin interface does not document a way to change the desktop app's SSH switches or a master SSH switch. This plugin provides the requested settings shortcut. It does not read or write SSH configuration, keys, host lists, or connection state.

## Development

```bash
npm ci --ignore-scripts
npm run build
npm test
```

Tests exercise the SDK handshake over stdio, sidebar metadata, UI resource loading, the fixed navigation target, invalid input, and launch failures. Tests replace the launcher when invoking the navigation tool, so they do not open settings or change connection state. Sidebar rendering and the destination page require a manual check in the installed ChatGPT app.

## References

- [OpenAI: plugin sidebar extensions](https://developers.openai.com/plugins/build/extensions)
- [OpenAI: desktop app deep links](https://learn.chatgpt.com/docs/app/commands#settings)
- [OpenAI: local plugin packaging](https://developers.openai.com/plugins/build/plugins)
