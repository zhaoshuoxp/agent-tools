# Adding and maintaining plugins

## Add a plugin

1. Put the complete project under `packages/<project-name>/`. Preserve its source, lockfile, build instructions, tests, assets, and existing license or third-party notices.
2. Identify the installable plugin directory. The current plugins use a `.codex-plugin/plugin.json` compatibility manifest with a `.mcp.json` server configuration. A future package may use the supported portable manifest layout described in the [official OpenAI packaging documentation](https://developers.openai.com/plugins/build/plugins).
3. Use a stable plugin name and a versioned manifest. Keep runtime paths relative to the installed plugin directory and include every required runtime file there. Bundle dependencies if installation should work without npm.
4. Add an entry to `.agents/plugins/marketplace.json`. For example, if the installable directory is `packages/my-plugin/`:

```json
{
  "name": "my-plugin",
  "source": {
    "source": "local",
    "path": "./packages/my-plugin"
  },
  "policy": {
    "installation": "AVAILABLE",
    "authentication": "ON_INSTALL"
  },
  "category": "Productivity"
}
```

The path is relative to the repository root. The entry's name must match the plugin manifest. Retain the shared marketplace name `chatgpt-plugins` as the catalog grows.

5. Add an English package README covering functionality, requirements, installation, an example request, update and removal steps, and build or test commands. Describe any account access or local application interaction the plugin uses.
6. Add the plugin, version, purpose, and documentation link to the root README's plugin table.
7. Run the package's build and existing tests, verify the catalog path resolves, then test installation and the main workflow in ChatGPT. Record any checks that could not be completed.

## Update a plugin

- Update source and lockfiles together when dependencies change. Keep the package and plugin manifest versions consistent.
- Rebuild committed runtime files and preserve third-party notices. The catalog distributes the installable directory, so source changes need corresponding runtime updates.
- Run the affected package's tests. Check both plugins when changing shared catalog behavior.
- Update the root version table and package documentation, then refresh or reinstall the local plugin to check the new build.
- Keep credentials, account tokens, private keys, host lists, and machine-specific configuration outside the repository. Commit example configuration with placeholder values when needed.

Each project keeps its own build system and dependency lockfile. Add future plugins without requiring changes to existing packages.
