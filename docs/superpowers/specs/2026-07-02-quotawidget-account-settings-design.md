# QuotaWidget Account Settings Design

## Goal

Add a configurable Accounts interface to the QuotaWidget macOS menu bar app so
users can set up all six supported providers from the app itself:

- Claude
- Codex
- Kimi Code
- DeepSeek
- SiliconFlow
- OpenRouter

The settings UI should make the newly added balance providers usable from a
normal macOS GUI launch, where shell environment variables are not available.

## Problem

The current balance-provider implementation reads API keys from process
environment variables:

- `DEEPSEEK_API_KEY`
- `SILICONFLOW_API_KEY`
- `OPENROUTER_API_KEY`

That is acceptable for the shared data layer and tests, but it does not work
well for QuotaWidget users. A macOS app launched from Finder, Spotlight, login
items, or the menu bar normally does not inherit shell startup environment
variables. As a result, DeepSeek, SiliconFlow, and OpenRouter show `no_data`
even when a user has configured keys in their terminal.

Claude, Codex, and Kimi have a different setup model. They should not become
manual token-entry forms:

- Claude credentials come from the official local credential store / Keychain.
- Codex data comes from local session snapshots, plus an optional active probe.
- Kimi credentials come from Kimi Code CLI OAuth files.

The app needs one unified settings surface, but provider-specific setup flows.

## Recommended Approach

Build a single `Accounts` settings window in the QuotaWidget companion app. The
page is grouped into two sections:

1. Local agent accounts
2. API balance accounts

This is the preferred first version because it keeps all provider setup in one
place while still respecting the fact that the providers use different
credential models.

## UI Structure

The menu bar app gains a new menu item:

- `Settings...`

Clicking it opens a normal macOS settings window. First version can be a
single-window SwiftUI view; it does not need a full multi-pane Settings scene.

The window contains a sidebar-like structure with these conceptual sections:

- `Accounts`
- `Refresh`
- `Privacy`
- `About`

For the first implementation, only `Accounts` needs to be functional. The other
labels can be omitted or left out entirely if that keeps the initial version
smaller. The important scope is the Accounts page.

### Accounts Page

The page has a top-level `Refresh All` action and six provider rows.

Each provider row shows:

- Provider mark / color
- Provider name
- Current status
- Main setup action
- Test action where useful
- Secondary action when useful

### Local Agent Accounts

#### Claude

Status examples:

- `Detected - Keychain credentials - refreshed 1m ago`
- `Not detected - open Claude Code and sign in`
- `Expired - open Claude Code and sign in again`
- `Request limited - retry later`

Actions:

- `Test`
- `Open Claude`

The app should not store a Claude token. The test action runs the shared fetcher
with current credentials and reports the sanitized provider status.

#### Codex

Status examples:

- `Local sessions detected - active refresh off`
- `No local snapshots - use Codex once`
- `Active refresh enabled - every 30m`

Actions:

- `Test`
- `Enable Probe` / `Disable Probe`

Codex active refresh maps to the existing config fields:

- `codex_active_refresh`
- `codex_refresh_interval_seconds`

The settings UI should write the shared config file used by `core/usage/config.py`.
The minimum interval remains the existing core minimum.

#### Kimi Code

Status examples:

- `Detected - Kimi Code CLI credentials`
- `Not logged in - CLI credentials missing`
- `Expired - sign in again with Kimi Code CLI`
- `Request limited - retry later`

Actions:

- `Test`
- `Open Login Help`

The app should not store a Kimi token. Login remains owned by the official Kimi
Code CLI.

### API Balance Accounts

DeepSeek, SiliconFlow, and OpenRouter use the same row model.

Status examples:

- `Not configured`
- `Configured - last checked 2m ago - ¥88.88`
- `Configured - no spending trend yet`
- `Configured - key rejected`
- `Configured - key lacks credits permission`
- `Request limited - retry later`

Actions:

- `Add Key`
- `Test`
- `Replace`
- `Remove`

Add/Replace opens a secure input sheet:

- Provider name and setup hint
- Secure text field for API key
- `Save and Test`
- `Cancel`

Remove asks for confirmation and deletes only that provider's stored key.

## Credential Storage

Use macOS Keychain for API balance providers.

Suggested service/account names:

- Service: `AI Agent Usage Widget`
- Account: `deepseek`
- Account: `siliconflow`
- Account: `openrouter`

The app never writes API keys to:

- `usage.json`
- balance history JSONL files
- logs
- process arguments
- repository files

## Fetcher Integration

The shared Python layer should keep supporting environment variables as its
lowest-level input because that is portable and testable.

QuotaWidgetApp should bridge Keychain credentials into the fetcher process:

1. Read provider keys from Keychain.
2. Create a process environment based on the app environment.
3. Add only configured API keys:
   - `DEEPSEEK_API_KEY`
   - `SILICONFLOW_API_KEY`
   - `OPENROUTER_API_KEY`
4. Run `core/fetch_usage.py`.
5. Validate the returned JSON with `UsagePayload.decode`.
6. Write sanitized JSON to the App Group via `UsageStore`.

The Widget extension continues reading only the sanitized `usage.json`. It never
needs Keychain access.

## Testing Provider Access

The `Test` action should run a targeted refresh path where possible:

- For API balance providers, run the shared fetcher with the selected key in the
  environment and inspect only that provider result.
- For Claude/Kimi/Codex, run the shared fetcher and inspect the provider result.

The UI should show the exact sanitized reason:

- `no_data`
- `expired`
- `rate_limited`
- `error`
- `stale`

It should translate those into user-facing copy without exposing raw exception
text that might include local details.

## Data Model

Add a small app-side account status model:

```swift
enum AccountKind {
    case localAgent
    case apiKey
}

struct AccountRowState: Identifiable {
    let id: ProviderID
    let name: String
    let kind: AccountKind
    let configured: Bool
    let statusText: String
    let detailText: String?
    let lastChecked: Date?
    let balanceSummary: String?
}
```

The exact names can follow local Swift style, but the model should keep setup
status separate from usage payload decoding. The widget data contract remains
focused on provider usage/balance snapshots.

## Error Handling

- Keychain read failure: show `Keychain unavailable` and keep existing key state
  unchanged.
- Keychain write failure: keep the sheet open and show a short error.
- Invalid key: do not save unless the user explicitly chooses to save anyway.
- Network error during test: allow saving, but mark status as `Connection failed`.
- Fetcher timeout: keep current cached widget data and show `Refresh timed out`.

For first implementation, `Save and Test` may save first and then test if that
keeps the flow simpler, but failed tests must be visible and easy to retry.

## Privacy

The settings page should include a short privacy note:

> API keys are stored in Keychain. QuotaWidget injects them into the fetcher
> process only during refresh. The widget extension receives only sanitized
> balances and usage status.

No provider key should ever be displayed in full after saving. A configured key
can be shown as a masked value such as `••••••abcd` if needed.

## Scope For First Version

In scope:

- Accounts settings window in QuotaWidget app.
- Six provider rows.
- Keychain storage for DeepSeek, SiliconFlow, and OpenRouter.
- Add/Test/Replace/Remove for API key providers.
- Test / login guidance / Codex active refresh controls for local agent
  providers.
- QuotaWidgetApp injects Keychain keys into `UsageFetcher`.
- Widget display uses existing `UsagePayload` support.
- README update for app-based provider setup.

Out of scope:

- Windows Credential Manager UI.
- iCloud sync for keys.
- Custom provider endpoints.
- Multiple accounts per provider.
- Full onboarding wizard.
- Showing raw API responses.

## Implementation Notes

Existing files likely involved:

- `macwidget/App/QuotaWidgetApp.swift`
- `macwidget/App/UsageFetcher.swift`
- `macwidget/Shared/UsageStore.swift`
- `macwidget/Shared/UsageContract.swift`
- `macwidget/Tests/UsageContractTests.swift`
- New app-side Keychain helper file under `macwidget/App/`
- New SwiftUI settings view under `macwidget/App/`
- `core/usage/config.py` only if app-side Codex config writing needs a shared
  path documented or adjusted
- README files

## Kimi Delegation Constraint

If implementation is delegated to Kimi CLI and Kimi appears stuck, do not
silently finish the remaining work in Codex. First identify why Kimi is stuck,
report the likely cause, and try to get Kimi unstuck or continue via Kimi. Only
take over after explicit user approval or after demonstrating that Kimi cannot
proceed.
