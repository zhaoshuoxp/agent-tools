# ChatGPT Plugins

A growing collection of local plugins for the ChatGPT desktop app on macOS. Each package includes its source, tests, and prebuilt runtime files. The shared marketplace makes the plugins available from one catalog.

## Plugins

| Plugin | Version | Function | Documentation |
| --- | --- | --- | --- |
| Usage Meter | 1.1.2 | Display reported ChatGPT Work / Codex quota usage and reset times in a sidebar indicator and detail panel. | [Usage Meter](packages/chatgpt-usage-plugin/README.md) |
| SSH Connections | 1.0.2 | Open **Settings > Connections > SSH** from a sidebar shortcut. | [SSH Connections](packages/ssh-connections-local/plugins/ssh-shortcut/README.md) |

### Usage Meter

The sidebar icon shows weekly quota usage, with an inner ring for the 5-hour window when available. Open the plugin to see percentages, reset times, and the reading timestamp. It refreshes every minute while connected, and a failed refresh marks the last reading as out of date. The detail view can attach a dated usage summary to the current conversation.

Usage comes from the locally signed-in ChatGPT Work / Codex account through the local Codex app-server. Subscription quota availability depends on the account and service response. The plugin starts no model turns. ChatGPT controls sidebar redraws and metadata caching.

Example prompt: `Open Usage Meter and show my current usage limits.`

### SSH Connections

Click **SSH Connections** in the sidebar to open the app's SSH settings. Use the switches on that settings page to enable or disable individual hosts. The plugin also provides an **Open SSH settings** button.

The shortcut sends the fixed `codex://settings/connections/ssh` navigation request to macOS. ChatGPT manages the connections and their credentials.

Example prompt: `Open SSH connection settings.`

## Requirements

- ChatGPT desktop for macOS with local plugins and the required sidebar or panel interfaces enabled.
- Node.js 22 or newer to run both plugins. SSH Connections alone supports Node.js 20 or newer.
- Access to the Codex CLI, either on `PATH` or bundled with the ChatGPT desktop app.
- A locally signed-in ChatGPT account for Usage Meter quota readings.

Runtime dependencies are bundled in the committed `dist/` files. Building from source requires npm and access to the npm registry. Account or workspace policies may limit local plugin installation.

## Install

Clone the repository into a location you intend to keep:

```bash
git clone https://github.com/zhaoshuoxp/chatgpt-plugins.git
cd chatgpt-plugins
codex plugin marketplace add .
```

If `codex` is not on `PATH`, use the bundled CLI for the last command:

```bash
"/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex" plugin marketplace add .
```

Restart ChatGPT when your running work permits. Open **Plugins**, select the **ChatGPT Plugins** marketplace, and install **Usage Meter**, **SSH Connections**, or both. Open the installed plugin from the sidebar or select it in a new conversation. Sidebar placement depends on the app version.

You can also install from the registered catalog with the CLI:

```bash
codex plugin add usage-meter@chatgpt-plugins
codex plugin add ssh-shortcut@chatgpt-plugins
```

Keep the checkout in place while its local marketplace is registered. ChatGPT runs an installed cached copy; refresh or reinstall a plugin after changing its runtime files.

Each package retains its original standalone marketplace and `.command` helpers. Those helpers and the package-level installation instructions use the standalone names `chatgpt-usage-local` and `ssh-connections-local`. The commands above use the combined `chatgpt-plugins` catalog. When migrating an existing installation, remove its old standalone entry before installing the same plugin from the combined catalog.

## Update and remove

From this repository's checkout:

```bash
git pull --ff-only
codex plugin add usage-meter@chatgpt-plugins
codex plugin add ssh-shortcut@chatgpt-plugins
```

Run the install command for each plugin you use, then refresh or reconnect it in ChatGPT. Restart the app if it retains old sidebar metadata.

Remove either plugin as needed:

```bash
codex plugin remove usage-meter@chatgpt-plugins
codex plugin remove ssh-shortcut@chatgpt-plugins
```

After removing all plugins installed from this catalog, remove its registration with `codex plugin marketplace remove chatgpt-plugins`.

## Build and test

Run these commands from the repository root to rebuild Usage Meter and run its existing tests:

```bash
npm --prefix packages/chatgpt-usage-plugin ci --ignore-scripts
npm --prefix packages/chatgpt-usage-plugin run build
npm --prefix packages/chatgpt-usage-plugin test
```

Rebuild and test SSH Connections:

```bash
npm --prefix packages/ssh-connections-local/plugins/ssh-shortcut ci --ignore-scripts
npm --prefix packages/ssh-connections-local/plugins/ssh-shortcut run build
npm --prefix packages/ssh-connections-local/plugins/ssh-shortcut test
```

Usage Meter tests use synthetic account responses. To explicitly read the local account's quota, run `npm --prefix packages/chatgpt-usage-plugin run check:live`. SSH Connections tests replace the navigation launcher. Visible sidebar behavior and the destination settings page require a manual check in ChatGPT.

## Repository layout and future plugins

```text
.agents/plugins/marketplace.json   Shared plugin catalog
packages/
  chatgpt-usage-plugin/            Usage Meter project and standalone catalog
  ssh-connections-local/          SSH Connections project and standalone catalog
CONTRIBUTING.md                    How to add and maintain plugins
```

Add future projects under `packages/`, register their installable directories in the shared catalog, and add their documentation to the table above. See [CONTRIBUTING.md](CONTRIBUTING.md) for the entry format and maintenance steps.

Local marketplace setup follows the [official OpenAI plugin packaging documentation](https://developers.openai.com/plugins/build/plugins). The SSH navigation target is listed in the [official desktop app commands](https://learn.chatgpt.com/docs/app/commands#settings).
