# QuotaWidget Control App And Display Layers Design

## Goal

Turn the existing macOS `QuotaWidget.app` into the single control app for AI Agent Usage on macOS. The control app owns account configuration, API keys, refresh, shared sanitized state, and optional display-layer installation. Übersicht, WidgetKit, and Touch Bar / Bar become display layers that do not store credentials or implement provider configuration.

## Scope

This design is macOS-only for the first release. Windows is intentionally out of scope.

The existing `QuotaWidget.app` bundle, App Group, and Keychain storage are reused. We do not create a new `AI Agent Usage.app` bundle in this phase.

The first display layers managed by the control app are:

- Übersicht desktop widget
- macOS WidgetKit widget
- Touch Bar / Bar app

## Product Shape

`QuotaWidget.app` remains a menu bar app, but `Settings...` opens a fuller control window with these areas:

- Accounts: Claude, Codex, Kimi Code, DeepSeek, SiliconFlow, and OpenRouter configuration.
- Refresh: current refresh status, last refresh time, manual refresh, and automatic refresh settings.
- Displays: install, update, remove, open, and diagnose optional display layers.
- Diagnostics: signing, App Group, Keychain, shared state, and display-layer health.

The app can still show a compact menu bar menu, but configuration should live in the control window instead of being scattered across display layers.

## Data Ownership

The control app is the only component that reads raw credentials:

- Local providers continue to read their existing local login state through the shared Python core.
- API-balance providers use API keys stored in macOS Keychain under the existing service `AI Agent Usage Widget`.
- DeepSeek, SiliconFlow, and OpenRouter API keys are injected into the refresh process environment by the control app.

The control app writes a sanitized JSON contract to the shared App Group container. Display layers read this sanitized state and never receive raw API keys.

## Display Layer Responsibilities

### Übersicht

The control app installs or updates the `usage-widget` bundle into the user's Übersicht widgets directory. It must support both Unicode forms of the Übersicht application support directory because existing installs may use either path.

The installed Übersicht widget should prefer the control app's sanitized shared state. If the shared state is unavailable, it may fall back to running the bundled fetcher only as a compatibility path, but credentials must still be sourced through safe environment/config paths rather than copied into the widget.

### macOS WidgetKit

The WidgetKit extension is bundled with the signed control app. It is not installed separately by the Displays page.

The Displays page shows whether the extension is registered and whether the App Group usage file exists. It should provide user guidance to add or re-add the widget from the macOS widget gallery and offer a refresh-timelines action.

The WidgetKit extension only reads App Group state.

### Touch Bar / Bar

The control app can install or update the existing Touch Bar / Bar app using the repository's current packaging approach. It should be able to start, stop, and remove that display layer.

The Touch Bar / Bar display should read the same sanitized shared state where possible. If it keeps a subprocess-based refresh path for compatibility, it must not become an independent configuration surface.

## First Version Non-Goals

The first version does not include:

- Windows control app work.
- A full first-launch onboarding wizard.
- A display marketplace.
- Remote release downloads.
- Visual previews for every display layer.
- A new bundle identifier or Keychain migration.

## Error Handling

The control app should surface these states in Diagnostics:

- App Group unavailable or unreadable.
- Keychain read/write failure.
- Python fetcher missing or failing.
- Display layer installed in an unexpected path.
- WidgetKit extension not registered.
- App or extension is ad-hoc signed when a signed install is required.

Diagnostics should avoid printing raw credentials, local usernames, absolute home paths, or personal account values.

## Testing Expectations

Implementation must add tests for:

- Control window model sections and row states.
- Display-layer status detection.
- Übersicht install path selection for both Unicode directory forms.
- Keychain-backed API keys still being read by the refresh path.
- WidgetKit extension diagnostics.
- No display-layer installer writes secrets into repo files or generated widget files.

Manual acceptance must include:

- Existing DeepSeek and SiliconFlow keys remain visible as configured.
- `Settings...` exposes Accounts and Displays.
- Übersicht can be installed/updated from the control app.
- WidgetKit does not render blank with a signed build.
- Touch Bar / Bar can be installed or detected from the control app.
