# Agent Instructions

Rules for any AI agent (Codex, Claude, etc.) working in this repository.

## Privacy — never expose machine-local or personal info

This repository is **public**. When committing, opening PRs, or pushing anything to GitHub:

- **Commit identity must be the GitHub noreply address**, never a personal email.
  The repo's local git config is already set to it; do not override with a personal email.
- **No machine-local paths**: use `~` / `$HOME`, never absolute `/Users/<name>/…`.
- **No OS username**: use `$USER` / `$(id -un)`, never hardcode the literal username.
- **No** real account ids, device ids, hostnames, tokens, or personal usage numbers in
  committed files or PR titles/bodies.
- A `pre-commit` hook in `.githooks/` enforces this. Activate it once per clone:
  ```bash
  git config core.hooksPath .githooks
  ```
  Before pushing, also `grep` your diff for the username / home path / personal email.

## Secrets

- Tokens/credentials must never enter argv, logs, or the repo. Pass auth via curl
  `--config` stdin (see `core/usage/*.py`). `.gitignore` already excludes `*.jsonl` and
  credential files — keep it that way.
