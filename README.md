# AI Agent Usage Widget

A compact [Übersicht](https://tracesof.net/uebersicht/) widget for monitoring
Claude and Codex usage on macOS.

It displays:

- Five-hour usage and reset countdown
- Weekly usage and reset countdown
- Claude and Codex status independently, so one provider can fail without
  hiding the other
- Stale-data indicators when a provider cannot supply a fresh snapshot

![Widget preview](docs/widget-preview.jpg)

## How It Works

The widget runs a small Python script once per minute and renders the returned
JSON in Übersicht.

- **Claude:** reads the existing Claude Code OAuth access token from macOS
  Keychain and calls Anthropic's usage endpoint. The token is read-only:
  this project never refreshes, stores, or prints it.
- **Codex:** reads rate-limit snapshots from local Codex session JSONL files.
  It does not make model requests or access the Codex credential store.

Claude responses are cached for five minutes to reduce API traffic. Codex
snapshots are checked for freshness before being displayed.

## Requirements

- macOS
- [Übersicht](https://tracesof.net/uebersicht/)
- Python 3
- `curl`
- Claude Code and/or Codex installed and used at least once

Check the command-line requirements:

```bash
python3 --version
curl --version
```

## Quick Start

### Option A: Download The ZIP

1. Open the repository's **Code** menu and choose **Download ZIP**.
2. Double-click the downloaded ZIP file.
3. Open Terminal, type `cd ` (including the trailing space), drag the extracted
   `ai-agent-usage-widget` folder into Terminal, and press Return.
4. Run:

```bash
cd usage-widget
bash install.sh
```

### Option B: Clone With Git

```bash
git clone https://github.com/lazyfoxy33-dev/ai-agent-usage-widget.git
cd ai-agent-usage-widget/usage-widget
bash install.sh
```

Open or restart Übersicht. Make sure Übersicht is running and the
`usage-widget` entry is enabled in its menu. The widget is installed at:

```text
~/Library/Application Support/Übersicht/widgets/usage-widget/
```

To update an existing installation, pull the latest changes and run
`bash install.sh` again.

## First Use

The widget refreshes automatically once per minute. It can display either
provider by itself, so configuring both Claude and Codex is optional.

1. Use Claude Code and/or Codex normally at least once.
2. Install the widget and start Übersicht.
3. Wait up to one minute for the first refresh.
4. If macOS asks whether Python or `security` may access the Claude Code
   Keychain item, review the prompt and allow access if you want Claude usage
   to appear.

The interface currently uses Chinese labels:

- `5 小时`: rolling five-hour usage
- `本周`: weekly usage
- `后重置`: time remaining until reset

## Provider Setup

### Claude

Sign in to Claude Code normally. The widget reads the
`Claude Code-credentials` Keychain item. If the access token has expired, use
Claude Code again so the official client can refresh its own login.

The widget deliberately does not refresh Claude tokens because OAuth refresh
tokens may rotate. Refreshing them independently could sign the official
client out.

### Codex

Use Codex at least once so it writes a session containing rate-limit data.
Codex usage is a local snapshot from the latest model response, not a live
usage API. The widget marks an expired snapshot as stale instead of presenting
it as current.

## Network And Proxy Behavior

Claude usage requests honor `HTTPS_PROXY` or `https_proxy`. If neither is set,
the script checks common local proxy ports `7897` and `7890`. If no proxy is
available, `curl` connects directly.

No proxy is used for Codex because Codex data is read from local files.

## Privacy And Security

- Credentials are read only from macOS Keychain at runtime.
- Tokens are never written to this repository or the widget cache.
- Claude usage data is sent only to Anthropic's API.
- Codex data stays on the local machine.
- The cache contains usage percentages and reset times only.

Review [SECURITY.md](SECURITY.md) before reporting a security issue.

## Troubleshooting

### Check The Data Source

Run the data source directly to verify provider access without waiting for the
desktop widget:

```bash
cd usage-widget
python3 fetch_usage.py
```

Successful output is JSON containing separate `claude` and `codex` sections.
Do not post unreviewed command output in a public issue.

Common states:

- `claude.reason = "expired"`: open Claude Code and sign in or run a request.
- `claude.reason = "error"`: check network access, `curl`, and proxy settings.
- `codex.reason = "no_data"`: use Codex once, then wait for the next widget
  refresh.
- Codex percentages are gray/stale: the latest local snapshot has passed its
  reset time; use Codex to produce a fresh snapshot.

### Refresh The Widget

There is no clickable refresh button in the widget. It refreshes automatically
every 60 seconds. To reload it immediately, disable and re-enable
`usage-widget` from the Übersicht menu, or restart Übersicht.

### Reinstall Or Update

After downloading a newer release or pulling new commits, run the installer
again from the new `usage-widget` directory:

```bash
bash install.sh
```

The installer replaces the widget code but does not modify Claude Code or
Codex credentials.

## Uninstall

```bash
rm -rf "$HOME/Library/Application Support/Übersicht/widgets/usage-widget"
```

Optionally remove the Claude usage cache:

```bash
rm -rf "$HOME/.cache/usage-widget"
```

## Development

```bash
cd usage-widget
python3 -m unittest discover -v
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## Limitations

- The Claude OAuth usage endpoint is not a documented public API and may
  change.
- Codex does not currently expose a separate live usage endpoint to this
  widget; displayed values depend on the latest local session snapshot.
- The widget currently targets macOS and Übersicht only.

## License

[MIT](LICENSE)
