# Usage Meter for ChatGPT macOS 1.1.2

A local ChatGPT plugin that publishes a quota ring directly as its sidebar entrypoint icon. The entrypoint title contains quota percentages, reset times, and the reading timestamp. It uses the official MCP tool icon, title, and list-change interfaces.

## Sidebar indicator

- The outer ring represents used weekly quota. The number in the center is the percentage used.
- The caption below the ring shows that outer window's local reset date as `M.D`, for example `11.7`. Missing reset dates display `--`. Hover text retains the full reset date and time for each reported window.
- The icon uses bold black geometry with white keylines. This artwork works with ChatGPT's monochrome mask conversion and remains outlined when original colors are shown.
- The quota track, used segment, digits, and date use full opacity. A thicker segment indicates used quota. The host controls the final Tint color; the plugin does not add another fade to the artwork.
- The gauge fills the available icon width, with a lower opening for the reset date and enlarged center digits. ChatGPT controls the native icon slot size; changing the SVG dimensions cannot enlarge that slot.
- A second, inner ring represents used 5-hour quota when the account reports that window. When only 5-hour quota is reported, it uses the outer ring.
- Missing quotas display a dashed ring with a question mark. A known zero displays `0`.
- The entrypoint title includes each reported reset time and the reading time. ChatGPT uses this title for its sidebar label and hover text.
- The server refreshes its reading every minute while connected, updates the icon and title, and sends the standard `notifications/tools/list_changed` notification. It also updates immediately after a manual refresh from its detail view.
- A failed read retains the last quota, adds a status dot, and labels the title **out of date**. It never substitutes a zero reading.

The client controls metadata caching, hover presentation, and sidebar redraws. Protocol tests verify changed icons, titles, notifications, failure handling, and recovery. Automatic redraw in the actual ChatGPT sidebar has not been visually verified because the available automation tool cannot operate this app. A client that caches entrypoint metadata may require a plugin refresh or reconnect. This implementation does not claim a separate hover-popover API or a guaranteed redraw interval in the host.

## Install

1. Keep this extracted folder in a permanent location.
2. Double-click `Install.command` to register the local marketplace. Node.js 22 or newer is required; the plugin is already built.
3. Restart ChatGPT. Open **Plugins**, choose **ChatGPT Usage Local**, and install **Usage Meter**.
4. Open **Usage Meter** in the sidebar or the conversation panel picker. You can also ask ChatGPT to open the plugin.
5. To attach usage to an existing chat, open Usage Meter from that chat's conversation panel, then select **Show beside conversation context**. Use the same button to remove it. The global sidebar entry has its own conversation context.

Local plugin installation and custom MCP interfaces must be allowed by your account or workspace. The installation script registers the marketplace through the bundled Codex CLI. Complete installation in the app to review and enable the local plugin.

To update an existing install, run `Update.command`, then refresh or reconnect Usage Meter in ChatGPT so it starts the new server. If ChatGPT retains the old entrypoint metadata, restart the app.

## Display behavior

- A reported 300-minute window appears as **5-hour limit**. If the service does not return it, that card is hidden and a short note explains the missing window.
- A reported 10,080-minute window appears as **Weekly usage**, regardless of whether the service puts it in `primary` or `secondary`.
- Percentages show **used** quota, with the remaining percentage below. Missing values display **Not reported**.
- Each window shows the service's reset time in your local time zone. **Next reset** uses the earliest pending reset. Passing that time never fabricates a zero-usage reading.
- The view refreshes every minute while mounted. A failed read marks the previous snapshot **Out of date**. The context summary includes its reading time; after the view closes, it remains a dated snapshot.
- When the service returns several quota buckets, the view keeps them separate.

## Supported placement and account scope

ChatGPT's documented extension points provide a sidebar entry and a conversation panel. This package updates the icon and title of its own sidebar entry using those interfaces. The host controls the final layout and metadata refresh behavior. The model selector and built-in context circle do not expose a documented customization point for this plugin.

The data comes from `account/rateLimits/read` in the local Codex app-server. It represents the locally signed-in **ChatGPT Work / Codex** account. The reader uses the same local Codex home as the app by default; retain `CODEX_HOME` if your installation uses a custom profile. It does not count normal Chat-mode messages or infer their model-specific quotas. If the app and CLI use different profiles, the local CLI profile determines the returned account.

The plugin starts no model turns, stores no account tokens itself, and sends no usage data to a third-party server. The official account service manages its existing authentication and may refresh its credentials. Attaching the summary makes that dated usage information available to the current conversation.

## Troubleshooting

- **Plugin is missing:** restart ChatGPT, select the local marketplace in Plugins, and install it. Workspace policy may restrict local plugins.
- **Node.js is missing:** install Node.js 22+ and restart ChatGPT. The launcher checks `PATH`, `/opt/homebrew/bin/node`, and `/usr/local/bin/node`.
- **Usage is unavailable:** sign in to ChatGPT Work / Codex using your ChatGPT account and refresh. API-key-only accounts do not expose subscription quotas through this route.
- **CLI is missing:** set `USAGE_CODEX_BIN` in the MCP server environment to the installed Codex executable. The default checks the bundled ChatGPT and Codex app locations, then `PATH`.
- **Context button is disabled:** the current host does not advertise the model-context extension. The sidebar and panel view remain available when supported.
- **Changes do not appear:** rebuild, increment the plugin version if distributing an update, and refresh or reinstall the local plugin through ChatGPT.

Double-click `Uninstall.command` to remove the plugin and its dedicated marketplace, then restart ChatGPT.

## Development

```bash
npm ci
npm run build
npm test
npm run check:live
```

`src/` contains the widget and local reader. `plugins/usage-meter/dist/` contains self-contained bundles, so installation does not run npm. The live check reads the local account service and prints only quota values and reset times. Tests use synthetic quota fixtures unless you explicitly run the live check.

The app-server protocol is versioned and described as experimental; future client changes may require an update. No supported app API has been established here for ordinary Chat-mode message quotas or a permanent model-selector badge.

Official references: [Plugin extensions](https://developers.openai.com/plugins/build/extensions), [Plugin packaging and local marketplaces](https://developers.openai.com/plugins/build/plugins), [App-server account and rate limits](https://learn.chatgpt.com/docs/app-server#auth-endpoints).
