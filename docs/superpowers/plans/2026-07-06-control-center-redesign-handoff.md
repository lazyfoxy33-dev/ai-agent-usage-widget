# QuotaWidget Control Center Redesign Handoff

## Context

This branch is `codex/balance-providers`.

The current macOS configuration window works functionally, but the visual result is not acceptable. A static browser mockup has been approved as the design direction:

- Mockup URL while local server is running: `http://127.0.0.1:57931/`
- Mockup source: `.superpowers/mockups/control-center-redesign/index.html`

Use the mockup as the visual and structural reference. Do not invent a different direction.

## Goal

Redesign `QuotaWidget.app` settings into a polished macOS control center:

- sidebar navigation on the left
- content workspace on the right
- accounts as the primary first screen
- provider rows grouped by type
- display layers as clean action cards
- consistent visual language for refresh and diagnostics

The goal is a practical macOS utility UI, not a marketing page.

## Non-Goals

- Do not create a new app bundle.
- Do not change the Keychain service name.
- Do not install or overwrite `/Applications/QuotaWidget.app`.
- Do not implement Windows work.
- Do not redesign the widget visuals in this task.
- Do not touch unrelated dirty files unless required for compile/test.

## Important Existing State

Preserve the behavior from recent commits:

- `QuotaWidget.app` is the control app.
- Keychain service must remain exactly `AI Agent Usage Widget`.
- DeepSeek, SiliconFlow, and OpenRouter are API-key providers.
- Display layers do not own secrets.
- `Displays` actions were recently added and must not be removed:
  - Übersicht install/update
  - Übersicht open folder
  - WidgetKit refresh timelines
  - Widget gallery open
  - Touch Bar install/update
  - Touch Bar open app
- The app bundles display layer install sources into `Contents/Resources/display-layers`.

## Primary Files

Expected files to edit:

- `macwidget/App/ControlCenterView.swift`
- `macwidget/App/AccountSettingsView.swift`
- `macwidget/Tests/UsageContractTests.swift`

Possible files to edit if needed:

- `macwidget/App/DisplayLayerStore.swift`
- `macwidget/Tests/DisplayLayerStoreTests.swift`
- `macwidget/QuotaWidget.xcodeproj/project.pbxproj`
- `macwidget/project.yml`

Avoid unrelated files, especially existing dirty design/widget/windows changes.

## Desired UI Structure

### Top-Level Layout

Replace the current default `TabView` settings UI with a two-column layout:

- Left sidebar:
  - app title: `QuotaWidget`
  - subtitle: `AI Agent Usage control center`
  - navigation items:
    - `Accounts`
    - `Refresh`
    - `Displays`
    - `Diagnostics`
  - compact status area:
    - shared state
    - last refresh
    - configured provider count

- Right content area:
  - toolbar/header with page title and subtitle
  - relevant action buttons
  - page content

Use SwiftUI native controls, but avoid the stock `TabView`/plain `List` look.

### Accounts Page

This should be the first/default screen.

Required sections:

- Summary row with three compact metric panels:
  - `Local agents`
  - `API balance`
  - `Shared state`

- `Local Agents` group:
  - Claude
  - Codex
  - Kimi Code

- `API Balance` group:
  - DeepSeek
  - SiliconFlow
  - OpenRouter

Each provider row should include:

- provider logo or compact glyph
- provider name
- type tag: `Local Agent` or `API Key`
- status text
- detail text / balance summary where available
- right-side action button

API-key editing should feel inline and calm. Avoid an awkward modal/sheet-first feel. It is acceptable to keep existing save/delete behavior, but visually present the editor as an inline panel below the selected API provider group.

### Displays Page

Show three cards, not a plain list:

- `Übersicht Widget`
- `macOS Widget`
- `Touch Bar / Bar`

Each card should show:

- installed/not installed status
- short explanation
- existing actions from `DisplayLayerActions`

Do not remove the underlying actions that were just implemented.

### Refresh Page

Use the same visual language:

- clear page header
- current refresh status
- `Refresh Now` primary action
- short note that all display layers read the shared state

No complex new refresh model is required in this task.

### Diagnostics Page

Use the same visual language:

- shared usage state status
- display layer statuses
- guidance for WidgetKit blank state / signing

Avoid dumping long local paths or personal details in the UI.

## Visual Style

Follow the approved mockup:

- macOS utility feel
- restrained colors
- light gray sidebar
- white/right content workspace
- subtle borders
- 6-8px corner radius
- no large decorative cards
- no gradient blobs
- no oversized hero typography
- stable row heights and compact controls

Text must not overflow buttons or rows. The window should work at roughly `920 x 620` and also degrade reasonably near the existing minimum settings size.

## Testing Requirements

Use TDD.

Add or update tests before implementation.

Required source-contract assertions in `UsageContractTests.swift`:

- `ControlCenterView.swift` should no longer contain `TabView`.
- It should contain sidebar/navigation structures such as `ControlSidebar`, `ControlPage`, or equivalent names.
- It should contain these visible navigation labels:
  - `Accounts`
  - `Refresh`
  - `Displays`
  - `Diagnostics`
- It should contain group labels:
  - `Local Agents`
  - `API Balance`
- It should contain all six provider names:
  - `Claude`
  - `Codex`
  - `Kimi Code`
  - `DeepSeek`
  - `SiliconFlow`
  - `OpenRouter`
- It should still contain display action labels:
  - `Install / Update`
  - `Open Folder`
  - `Refresh Timelines`
  - `Open Widget Gallery`
  - `Open App`

Also keep existing behavior tests passing:

- account rows keep API providers
- Keychain service remains stable
- display layer action/install tests remain green

## Verification Commands

Run at minimum:

```bash
xcodebuild test -project macwidget/QuotaWidget.xcodeproj -scheme QuotaWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
python3 -m unittest usage-widget.tests.test_widget_source usage-widget.tests.test_install -v
python3 -m unittest discover -s touchbar/tests -v
```

If touching design docs or web mockup tests, also run:

```bash
node --test docs/design/tests/design-system.test.mjs
```

Before handoff, scan the diff:

```bash
git diff -- macwidget | grep -nE 'AKIA|BEGIN PRIVATE|password:|api[_-]?key' || true
```

Expected: no real secrets, no local username/path leaks.

## Git Discipline

- Preserve existing dirty worktree changes that are unrelated.
- Do not revert files you did not intentionally edit.
- Commit only the redesign changes.
- Suggested commit message:

```bash
git commit -m "feat(macwidget): redesign control center settings"
```

## Acceptance Criteria

The task is ready for Codex review when:

- the settings window visually follows the approved mockup direction
- Accounts is the default page and feels like the main control center
- provider configuration is easier to scan
- Displays no longer looks like a plain list
- existing display actions still compile and test
- all required verification commands pass
- no installed signed app is overwritten

