# Contributing

Contributions are welcome.

## Before You Start

- Open an issue for significant behavior or UI changes.
- Keep provider integrations independent so a failure in one provider does not
  break the whole widget.
- Do not add token refresh behavior. Provider credentials must remain read-only.
- Do not commit real credentials, Keychain exports, session files, caches, or
  machine-specific paths.

## Development Setup

```bash
git clone https://github.com/lazyfoxy33-dev/ai-agent-usage-widget.git
cd ai-agent-usage-widget/usage-widget
python3 -m unittest discover -v
python3 fetch_usage.py
```

`fetch_usage.py` reads local provider state. Before sharing its output, inspect
it and remove anything you consider private.

## Pull Requests

1. Add or update tests for data-layer changes.
2. Run the full test suite.
3. Verify UI changes in Übersicht.
4. Keep changes focused and explain provider/API assumptions in the PR.
5. Confirm the diff contains no tokens, personal paths, session data, or cache
   files.

## Code Style

- Python code uses the standard library only.
- Keep parsing, caching, orchestration, and rendering responsibilities
  separated.
- Prefer explicit failure states over silently presenting outdated data.
- Keep the widget usable when only one provider is configured.
