# Touch Bar Install Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install QuotaBar as a strictly signed per-user app with a reliable LaunchAgent.

**Architecture:** Keep compilation in `build.sh`, then copy the verified bundle
to `~/Applications` from `install.sh`. Treat signing and launch registration as
required installation steps.

**Tech Stack:** Bash, Swift, macOS codesign, launchctl, Python unittest

---

### Task 1: Add Installation Contract Tests

**Files:**
- Create: `touchbar/tests/test_install_contract.py`

- [x] Assert that build removes extended attributes and strictly verifies the bundle.
- [x] Assert that install copies to `~/Applications/QuotaBar.app`.
- [x] Assert that the LaunchAgent uses `bootout`, `bootstrap`, and `kickstart`.
- [x] Run the test and confirm it fails against the current scripts.

### Task 2: Harden Build And Install Scripts

**Files:**
- Create: `touchbar/sign_bundle.sh`
- Modify: `touchbar/build.sh`
- Modify: `touchbar/install.sh`
- Modify: `touchbar/README.md`

- [x] Add a bounded shared signing helper for FileProvider metadata races.
- [x] Remove bundle extended attributes before signing.
- [x] Make full ad-hoc signing and strict verification mandatory.
- [x] Copy without resource forks or extended attributes to `~/Applications`.
- [x] Generate the LaunchAgent with the installed application path.
- [x] Replace the existing LaunchAgent through the GUI launchctl domain.
- [x] Update install and uninstall documentation.

### Task 3: Verify The Real Installation

**Files:**
- Verify: `touchbar/QuotaBar.app`
- Verify: `~/Applications/QuotaBar.app`
- Verify: `~/Library/LaunchAgents/com.quotabar.app.plist`

- [x] Run all Touch Bar tests.
- [x] Run `touchbar/install.sh`.
- [x] Strictly verify the installed app signature.
- [x] Confirm launchd runs the installed path.
- [x] Run the installed binary with `--once`.
- [x] Confirm the Git worktree contains only intended source changes.
