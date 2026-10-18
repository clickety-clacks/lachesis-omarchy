# Lachesis for Omarchy

An Omarchy bar widget for [Lachesis](https://github.com/clickety-clacks/lachesis). The bar keeps the active Codex and Claude usage percentages visible. Open the panel for account usage, reset times, recent-burn estimates, and compatible account pools.

## Install

Run a Lachesis service first. This widget reads its local HTTP API on port 7843. Install the plugin with:

```sh
omarchy plugin add https://github.com/clickety-clacks/lachesis-omarchy.git --enable
```

The widget needs `bash`, `curl`, and `jq`. Its forecast presentation test needs Node.js only when developing the plugin.

By default, the widget reads Lachesis at `localhost:7843`. If Lachesis runs on another machine, set **Lachesis host** and **SSH user** in the widget settings. The remote user must be able to connect with SSH without an interactive prompt and run `curl` against `127.0.0.1:7843` on that machine. Leaving **SSH user** blank uses the current local username.

The widget reads the local Codex account ID from `~/.codex/auth.json` and only the Claude account UUID at `~/.claude.json` → `oauthAccount.accountUuid`. It matches the Claude UUID against the per-account `provider_account_uuid` field returned by Lachesis; that field may be null when unavailable. It does not send either file or any token to Lachesis. If the Claude UUID is missing or does not match exactly one registered account, the active Claude account is shown as unknown while the per-account details remain available.

Omarchy clones plugins from Git and updates them with a fast-forward pull. To update an installation, run `omarchy plugin update mike.lachesis-usage`. The plugin ID remains `mike.lachesis-usage` so existing Omarchy layouts and IPC shortcuts keep working.

## Check and release

Before a release, run:

```sh
bash -n fetch.sh
node forecast.test.js
jq -e '.schemaVersion == 1 and .id == "mike.lachesis-usage" and (.version | test("^[0-9]+[.][0-9]+[.][0-9]+$"))' manifest.json
```

Update `manifest.json`'s version for each release. Tag the tested commit with the matching `v` prefix, then push the default branch and tag. The GitHub workflow checks the plugin and publishes a release from the tag. Omarchy installs and updates from the default branch; tags and releases provide stable reference points, but they do not pin `omarchy plugin update`.
