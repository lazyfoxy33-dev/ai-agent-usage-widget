# Touch Bar Install Hardening Design

## Goal

Make QuotaBar install as a stable per-user application instead of running the
build artifact from the repository.

## Design

- `build.sh` remains responsible for compiling and bundling `QuotaBar.app`.
- Before signing, the build removes extended attributes that can invalidate
  bundle signing under macOS FileProvider-managed directories.
- A shared signer performs a bounded retry because FileProvider can reattach
  Finder metadata between cleanup and signing. Every attempt cleans metadata,
  signs, and strictly verifies the bundle; exhausting the retries is fatal.
- Signing errors are fatal, and the completed bundle must pass strict
  `codesign` verification.
- `install.sh` copies the built app to `~/Applications/QuotaBar.app` without
  resource forks or extended attributes, signs and verifies that installed
  copy, then installs a LaunchAgent that points only to the installed copy.
- The installer uses `launchctl bootout`, `bootstrap`, and `kickstart` in the
  current GUI domain. Reinstalling replaces the existing job cleanly.
- The README documents the installed location and matching uninstall command.

## Error Handling

Build, copy, signing, verification, plist generation, and LaunchAgent
registration failures stop installation immediately. Removing an absent prior
LaunchAgent remains non-fatal.

## Testing

Static contract tests assert the required install path, metadata cleanup,
strict signing, and modern launchctl lifecycle. The existing Swift build and a
real local reinstall verify the complete behavior.
