# QuotaWidget Control App And Display Layers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the existing macOS `QuotaWidget.app` into the single control app for account configuration, refresh, diagnostics, and optional display-layer installation.

**Architecture:** Keep the current signed `QuotaWidget.app`, App Group, and Keychain service. Add app-side model/services for display-layer status and installation, then replace the narrow settings surface with a tabbed control window. Display layers read sanitized shared state and do not own credentials.

**Tech Stack:** SwiftUI, AppKit, WidgetKit, macOS Keychain Services, XCTest, shell install scripts, existing Python `core/fetch_usage.py`.

---

## File Structure

- Modify `macwidget/App/AccountSettingsView.swift`: keep account rows, but embed them in a broader control window.
- Create `macwidget/App/ControlCenterView.swift`: top-level tabbed control window for Accounts, Refresh, Displays, and Diagnostics.
- Create `macwidget/App/RefreshStatusModel.swift`: app-side refresh state and manual refresh presentation.
- Create `macwidget/App/DisplayLayerStore.swift`: pure model/service for display-layer status and commands.
- Modify `macwidget/App/QuotaWidgetApp.swift`: open the new control window from `Settings...`, wire model dependencies, and preserve menu bar actions.
- Modify `macwidget/App/UsageFetcher.swift`: expose fetch path diagnostics without leaking credentials.
- Modify `macwidget/Shared/UsageStore.swift`: expose shared App Group status helpers.
- Modify `usage-widget/install.sh`: keep CLI installer compatible, but align with the app-side install destination logic.
- Modify `usage-widget/index.jsx`: prefer sanitized shared state when available, keep compatibility fallback if needed.
- Modify `touchbar/install.sh`: make install/update idempotent and app-callable.
- Modify `touchbar/Sources/DataSource.swift`: allow display-only mode from shared sanitized state.
- Modify `macwidget/Tests/UsageContractTests.swift`: add pure model and source-contract tests.
- Modify `macwidget/Tests/UsageStoreTests.swift`: test shared-state diagnostics.
- Create `macwidget/Tests/DisplayLayerStoreTests.swift`: status and install-path tests.
- Modify `usage-widget/tests/test_install.py`: installer path and no-secret guarantees.
- Modify `usage-widget/tests/test_widget_source.py`: shared-state preference contract.
- Modify `touchbar/tests/test_install_contract.py` and `touchbar/tests/test_source_contract.py`: idempotent installer and shared-state display mode.
- Modify `README.md` and `macwidget/README.md`: document the new control app model.

## Task 1: Preserve Existing API Keys And Model Account Status

**Files:**
- Modify: `macwidget/Tests/UsageContractTests.swift`
- Modify: `macwidget/App/AccountSettingsView.swift`

- [ ] **Step 1: Write failing tests for existing Keychain service expectations**

Add tests to `UsageContractTests` that pin the service name and provider account ids:

```swift
func testAPIKeyStoreUsesStableServiceAndProviderAccounts() {
    XCTAssertEqual(APIKeyStore.defaultService, "AI Agent Usage Widget")
    XCTAssertEqual(APIKeyProviderID.deepseek.rawValue, "deepseek")
    XCTAssertEqual(APIKeyProviderID.siliconflow.rawValue, "siliconflow")
    XCTAssertEqual(APIKeyProviderID.openrouter.rawValue, "openrouter")
}

func testAccountRowsKeepAPIProvidersInControlApp() {
    let model = AccountSettingsModel(
        payload: .preview,
        configuredAPIKeys: [.deepseek, .siliconflow],
        codexActiveRefresh: false
    )

    let apiRows = model.rows.filter { $0.kind == .apiKey }
    XCTAssertEqual(apiRows.map(\.id), [.deepseek, .siliconflow, .openrouter])
    XCTAssertEqual(apiRows.map(\.configured), [true, true, false])
}
```

- [ ] **Step 2: Run tests to verify they fail if current code is missing the model**

Run:

```bash
xcodebuild test -project macwidget/QuotaWidget.xcodeproj -scheme QuotaWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL only if the current branch lacks `APIKeyStore` or the account model. If these tests already pass, continue; they become regression coverage for the control app.

- [ ] **Step 3: Keep implementation minimal**

If the tests fail because the current branch does not have the account model, implement or restore:

```swift
enum APIKeyProviderID: String, CaseIterable, Identifiable {
    case deepseek
    case siliconflow
    case openrouter

    var id: String { rawValue }
}

struct APIKeyStore: Sendable {
    static let defaultService = "AI Agent Usage Widget"
}
```

Do not change the service name. Existing DeepSeek and SiliconFlow keys depend on it.

- [ ] **Step 4: Run tests**

Run the same `xcodebuild test` command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macwidget/App/AccountSettingsView.swift macwidget/Tests/UsageContractTests.swift
git commit -m "test(macwidget): pin control app account storage"
```

## Task 2: Add Shared State Diagnostics

**Files:**
- Modify: `macwidget/Shared/UsageStore.swift`
- Modify: `macwidget/Tests/UsageStoreTests.swift`

- [ ] **Step 1: Write failing tests for shared-state status**

Add to `UsageStoreTests`:

```swift
func testSharedStateStatusReportsMissingContainer() {
    let store = UsageStore(containerURLProvider: { nil })

    let status = store.status()

    XCTAssertFalse(status.available)
    XCTAssertEqual(status.reason, .missingContainer)
    XCTAssertNil(status.usagePath)
}

func testSharedStateStatusReportsUsageFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = UsageStore(containerURLProvider: { directory })
    try store.write("{\"schema_version\":1}")

    let status = store.status()

    XCTAssertTrue(status.available)
    XCTAssertTrue(status.usagePath?.hasSuffix("Library/Application Support/usage.json") ?? false)
    XCTAssertNotNil(status.modifiedAt)

    try? FileManager.default.removeItem(at: directory)
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project macwidget/QuotaWidget.xcodeproj -scheme QuotaWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because `UsageStore.status()` and status types do not exist.

- [ ] **Step 3: Implement status model**

Add to `UsageStore.swift`:

```swift
struct UsageStoreStatus: Equatable {
    enum Reason: Equatable {
        case ok
        case missingContainer
        case missingUsageFile
    }

    let available: Bool
    let reason: Reason
    let usagePath: String?
    let modifiedAt: Date?
}
```

Add method:

```swift
func status() -> UsageStoreStatus {
    guard let container = containerURLProvider() else {
        return UsageStoreStatus(
            available: false,
            reason: .missingContainer,
            usagePath: nil,
            modifiedAt: nil
        )
    }

    let url = container
        .appendingPathComponent("Library/Application Support", isDirectory: true)
        .appendingPathComponent("usage.json")

    guard FileManager.default.fileExists(atPath: url.path) else {
        return UsageStoreStatus(
            available: false,
            reason: .missingUsageFile,
            usagePath: url.path,
            modifiedAt: nil
        )
    }

    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return UsageStoreStatus(
        available: true,
        reason: .ok,
        usagePath: url.path,
        modifiedAt: attrs?[.modificationDate] as? Date
    )
}
```

- [ ] **Step 4: Run tests**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macwidget/Shared/UsageStore.swift macwidget/Tests/UsageStoreTests.swift
git commit -m "feat(macwidget): report shared usage state"
```

## Task 3: Add Display Layer Status Model

**Files:**
- Create: `macwidget/App/DisplayLayerStore.swift`
- Create: `macwidget/Tests/DisplayLayerStoreTests.swift`
- Modify: `macwidget/QuotaWidget.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing tests**

Create `DisplayLayerStoreTests.swift`:

```swift
import Foundation
import XCTest
@testable import QuotaWidgetApp

final class DisplayLayerStoreTests: XCTestCase {
    func testUbersichtDestinationCandidatesIncludeBothUnicodeForms() {
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)
        let candidates = DisplayLayerStore.ubersichtWidgetDirectories(homeDirectory: home)
            .map(\.path)

        XCTAssertTrue(candidates.contains("/tmp/home/Library/Application Support/Übersicht/widgets"))
        XCTAssertTrue(candidates.contains("/tmp/home/Library/Application Support/Übersicht/widgets"))
    }

    func testDisplayStatusDetectsInstalledUbersichtWidget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let widget = root
            .appendingPathComponent("Library/Application Support/Übersicht/widgets/usage-widget", isDirectory: true)
        try FileManager.default.createDirectory(at: widget, withIntermediateDirectories: true)
        try "marker".write(to: widget.appendingPathComponent("index.jsx"), atomically: true, encoding: .utf8)

        let store = DisplayLayerStore(
            homeDirectory: root,
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            processList: { [] }
        )

        let status = store.status(for: .ubersicht)

        XCTAssertEqual(status.layer, .ubersicht)
        XCTAssertTrue(status.installed)
        XCTAssertFalse(status.running)

        try? FileManager.default.removeItem(at: root)
    }
}
```

- [ ] **Step 2: Add test file to Xcode project and run tests**

Add `DisplayLayerStoreTests.swift` to the `QuotaWidgetTests` target in `project.pbxproj`.

Run:

```bash
xcodebuild test -project macwidget/QuotaWidget.xcodeproj -scheme QuotaWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because `DisplayLayerStore` does not exist.

- [ ] **Step 3: Implement display model**

Create `DisplayLayerStore.swift`:

```swift
import Foundation

enum DisplayLayer: String, CaseIterable, Identifiable {
    case ubersicht
    case widgetKit
    case touchBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ubersicht: return "Übersicht"
        case .widgetKit: return "macOS Widget"
        case .touchBar: return "Touch Bar / Bar"
        }
    }
}

struct DisplayLayerStatus: Equatable, Identifiable {
    var id: DisplayLayer { layer }
    let layer: DisplayLayer
    let installed: Bool
    let running: Bool
    let detail: String
}

struct DisplayLayerStore {
    let homeDirectory: URL
    let applicationsDirectory: URL
    let processList: () -> [String]

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        processList: @escaping () -> [String] = DisplayLayerStore.defaultProcessList
    ) {
        self.homeDirectory = homeDirectory
        self.applicationsDirectory = applicationsDirectory
        self.processList = processList
    }

    static func ubersichtWidgetDirectories(homeDirectory: URL) -> [URL] {
        [
            homeDirectory.appendingPathComponent("Library/Application Support/Übersicht/widgets", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Application Support/Übersicht/widgets", isDirectory: true)
        ]
    }

    func status(for layer: DisplayLayer) -> DisplayLayerStatus {
        switch layer {
        case .ubersicht:
            let installed = Self.ubersichtWidgetDirectories(homeDirectory: homeDirectory).contains { base in
                FileManager.default.fileExists(atPath: base.appendingPathComponent("usage-widget/index.jsx").path)
            }
            let running = processList().contains { $0.localizedCaseInsensitiveContains("Übersicht") || $0.localizedCaseInsensitiveContains("Übersicht") }
            return DisplayLayerStatus(layer: layer, installed: installed, running: running, detail: installed ? "Installed" : "Not installed")
        case .widgetKit:
            return DisplayLayerStatus(layer: layer, installed: true, running: false, detail: "Bundled with QuotaWidget.app")
        case .touchBar:
            let installed = FileManager.default.fileExists(atPath: applicationsDirectory.appendingPathComponent("QuotaBar.app").path)
            let running = processList().contains { $0.localizedCaseInsensitiveContains("QuotaBar") }
            return DisplayLayerStatus(layer: layer, installed: installed, running: running, detail: installed ? "Installed" : "Not installed")
        }
    }

    private static func defaultProcessList() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? []
        } catch {
            return []
        }
    }
}
```

- [ ] **Step 4: Run tests**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macwidget/App/DisplayLayerStore.swift macwidget/Tests/DisplayLayerStoreTests.swift macwidget/QuotaWidget.xcodeproj/project.pbxproj
git commit -m "feat(macwidget): model display layer status"
```

## Task 4: Add Control Center View

**Files:**
- Create: `macwidget/App/ControlCenterView.swift`
- Modify: `macwidget/App/AccountSettingsView.swift`
- Modify: `macwidget/Tests/UsageContractTests.swift`
- Modify: `macwidget/QuotaWidget.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing source-contract test**

Add to `UsageContractTests.swift`:

```swift
func testControlCenterDefinesExpectedTabs() throws {
    let source = try sourceFile("App/ControlCenterView.swift")

    XCTAssertTrue(source.contains("TabView"))
    XCTAssertTrue(source.contains("Accounts"))
    XCTAssertTrue(source.contains("Refresh"))
    XCTAssertTrue(source.contains("Displays"))
    XCTAssertTrue(source.contains("Diagnostics"))
    XCTAssertTrue(source.contains("AccountSettingsView"))
    XCTAssertTrue(source.contains("DisplayLayerStore"))
}
```

Add helper if not already present:

```swift
private func sourceFile(_ relativePath: String) throws -> String {
    var directory = URL(fileURLWithPath: #filePath)
    while directory.lastPathComponent != "macwidget" {
        let parent = directory.deletingLastPathComponent()
        if parent.path == directory.path {
            throw NSError(domain: "UsageContractTests", code: 1)
        }
        directory = parent
    }
    return try String(contentsOf: directory.appendingPathComponent(relativePath), encoding: .utf8)
}
```

- [ ] **Step 2: Run tests and verify failure**

Expected: FAIL because `ControlCenterView.swift` does not exist.

- [ ] **Step 3: Create control center view**

Create `ControlCenterView.swift`:

```swift
import SwiftUI

struct ControlCenterView: View {
    @ObservedObject var accountViewModel: AccountSettingsViewModel
    let displayStore: DisplayLayerStore
    let usageStore: UsageStore
    let refreshNow: () -> Void

    var body: some View {
        TabView {
            AccountSettingsView(viewModel: accountViewModel)
                .tabItem { Text("Accounts") }

            RefreshPanel(refreshNow: refreshNow)
                .tabItem { Text("Refresh") }

            DisplaysPanel(displayStore: displayStore)
                .tabItem { Text("Displays") }

            DiagnosticsPanel(usageStore: usageStore, displayStore: displayStore)
                .tabItem { Text("Diagnostics") }
        }
        .frame(minWidth: 560, minHeight: 460)
    }
}

struct RefreshPanel: View {
    let refreshNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Refresh")
                .font(.title2)
            Text("QuotaWidget refreshes usage data for every display layer.")
                .foregroundStyle(.secondary)
            Button("Refresh Now", action: refreshNow)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct DisplaysPanel: View {
    let displayStore: DisplayLayerStore

    var body: some View {
        List(DisplayLayer.allCases) { layer in
            let status = displayStore.status(for: layer)
            HStack {
                VStack(alignment: .leading) {
                    Text(layer.title).font(.headline)
                    Text(status.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(status.installed ? "Installed" : "Not Installed")
                    .foregroundStyle(status.installed ? .green : .orange)
            }
        }
    }
}

struct DiagnosticsPanel: View {
    let usageStore: UsageStore
    let displayStore: DisplayLayerStore

    var body: some View {
        let status = usageStore.status()
        List {
            LabeledContent("Shared usage state", value: status.available ? "Available" : "\(status.reason)")
            ForEach(DisplayLayer.allCases) { layer in
                let layerStatus = displayStore.status(for: layer)
                LabeledContent(layer.title, value: layerStatus.detail)
            }
        }
    }
}
```

- [ ] **Step 4: Add file to app target and run tests**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macwidget/App/ControlCenterView.swift macwidget/App/AccountSettingsView.swift macwidget/Tests/UsageContractTests.swift macwidget/QuotaWidget.xcodeproj/project.pbxproj
git commit -m "feat(macwidget): add control center view"
```

## Task 5: Wire Settings Menu To Control Center

**Files:**
- Modify: `macwidget/App/QuotaWidgetApp.swift`
- Modify: `macwidget/Tests/UsageContractTests.swift`

- [ ] **Step 1: Write failing source-contract test**

Add:

```swift
func testSettingsMenuOpensControlCenter() throws {
    let source = try sourceFile("App/QuotaWidgetApp.swift")

    XCTAssertTrue(source.contains("ControlCenterView"))
    XCTAssertTrue(source.contains("Settings..."))
    XCTAssertTrue(source.contains("SettingsPresenter"))
}
```

- [ ] **Step 2: Run tests**

Expected: FAIL until `QuotaWidgetApp.swift` uses `ControlCenterView`.

- [ ] **Step 3: Wire the Settings scene**

In `QuotaWidgetApp.swift`, keep the menu item text `Settings...`, but make `Settings` show `ControlCenterView`:

```swift
Settings {
    ControlCenterView(
        accountViewModel: settingsModel,
        displayStore: DisplayLayerStore(),
        usageStore: UsageStore(),
        refreshNow: { model.refresh() }
    )
}
```

Keep `SettingsPresenter.app(openSettings:)` so the menu action still activates and raises the settings window.

- [ ] **Step 4: Run tests**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macwidget/App/QuotaWidgetApp.swift macwidget/Tests/UsageContractTests.swift
git commit -m "feat(macwidget): open control center from settings"
```

## Task 6: Add Übersicht Install/Update/Remove Commands

**Files:**
- Modify: `macwidget/App/DisplayLayerStore.swift`
- Create or modify: `macwidget/Tests/DisplayLayerStoreTests.swift`
- Modify: `usage-widget/install.sh`
- Modify: `usage-widget/tests/test_install.py`

- [ ] **Step 1: Write failing tests for installing to existing Übersicht directories**

Add:

```swift
func testInstallUbersichtCopiesWidgetIntoExistingDirectories() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let source = root.appendingPathComponent("source", isDirectory: true)
    let widgets = root.appendingPathComponent("Library/Application Support/Übersicht/widgets", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: widgets, withIntermediateDirectories: true)
    try "widget".write(to: source.appendingPathComponent("index.jsx"), atomically: true, encoding: .utf8)

    let store = DisplayLayerStore(
        homeDirectory: root,
        applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
        processList: { [] }
    )

    try store.installUbersichtWidget(from: source)

    XCTAssertTrue(FileManager.default.fileExists(
        atPath: widgets.appendingPathComponent("usage-widget/index.jsx").path
    ))

    try? FileManager.default.removeItem(at: root)
}
```

- [ ] **Step 2: Run tests and verify failure**

Expected: FAIL because `installUbersichtWidget(from:)` does not exist.

- [ ] **Step 3: Implement installer method**

Add:

```swift
func installUbersichtWidget(from sourceDirectory: URL) throws {
    let destinations = Self.ubersichtWidgetDirectories(homeDirectory: homeDirectory)
        .filter { FileManager.default.fileExists(atPath: $0.path) }
    let targets = destinations.isEmpty
        ? [Self.ubersichtWidgetDirectories(homeDirectory: homeDirectory)[0]]
        : destinations

    for base in targets {
        let destination = base.appendingPathComponent("usage-widget", isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceDirectory, to: destination)
    }
}
```

- [ ] **Step 4: Keep shell installer aligned**

Ensure `usage-widget/install.sh` also defines both candidates:

```bash
BASE_DIRS=(
  "$HOME/Library/Application Support/Übersicht/widgets"
  "$HOME/Library/Application Support/Übersicht/widgets"
)
```

Add/update `usage-widget/tests/test_install.py` assertion:

```python
def test_installer_supports_ubersicht_unicode_directory_variants(self):
    with open(INSTALL) as f:
        source = f.read()
    self.assertIn("BASE_DIRS=(", source)
    self.assertIn("Übersicht/widgets", source)
    self.assertIn("Übersicht/widgets", source)
```

- [ ] **Step 5: Run tests**

```bash
xcodebuild test -project macwidget/QuotaWidget.xcodeproj -scheme QuotaWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
python3 -m unittest usage-widget.tests.test_install -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add macwidget/App/DisplayLayerStore.swift macwidget/Tests/DisplayLayerStoreTests.swift usage-widget/install.sh usage-widget/tests/test_install.py
git commit -m "feat(macwidget): manage ubersicht widget install"
```

## Task 7: Prefer Shared State In Übersicht

**Files:**
- Modify: `usage-widget/index.jsx`
- Modify: `usage-widget/tests/test_widget_source.py`

- [ ] **Step 1: Write failing source test**

Add:

```python
def test_widget_prefers_control_app_shared_state(self):
    self.assertIn("QUOTAWIDGET_SHARED_USAGE", self.source)
    self.assertIn("group.dev.lazyfoxy.QuotaWidget", self.source)
    self.assertIn("usage.json", self.source)
```

- [ ] **Step 2: Run test and verify failure**

```bash
python3 -m unittest usage-widget.tests.test_widget_source.TestWidgetSource.test_widget_prefers_control_app_shared_state -v
```

Expected: FAIL.

- [ ] **Step 3: Update command to prefer shared state**

At the top of `usage-widget/index.jsx`, make the command check an optional shared state first:

```jsx
const SHARED_USAGE_DEFAULT = "$HOME/Library/Group Containers/group.dev.lazyfoxy.QuotaWidget/Library/Application Support/usage.json";
const SCRIPT_DIRS = [
  "$HOME/Library/Application Support/Übersicht/widgets/usage-widget",
  "$HOME/Library/Application Support/Übersicht/widgets/usage-widget"
];
const FETCHER_DIRS = SCRIPT_DIRS.map((d) => `"${d}"`).join(" ");
export const command = `/bin/sh -lc 'shared="$${QUOTAWIDGET_SHARED_USAGE:-${SHARED_USAGE_DEFAULT}}"; if [ -f "$shared" ]; then cat "$shared"; exit 0; fi; for d in ${FETCHER_DIRS}; do if [ -f "$d/fetch_usage.py" ]; then exec /usr/bin/python3 "$d/fetch_usage.py"; fi; done; exit 1'`;
```

The `$${...}` spelling is intentional: it emits shell parameter expansion in the generated command while avoiding JavaScript template interpolation. Do not expose API keys in command arguments.

- [ ] **Step 4: Run tests and compile check**

```bash
python3 -m unittest usage-widget.tests.test_widget_source -v
npx --yes esbuild usage-widget/index.jsx --bundle --format=esm --outfile=/tmp/usage-widget-check.js
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add usage-widget/index.jsx usage-widget/tests/test_widget_source.py
git commit -m "feat(ubersicht): read control app shared usage first"
```

## Task 8: Add WidgetKit Diagnostics

**Files:**
- Modify: `macwidget/App/DisplayLayerStore.swift`
- Modify: `macwidget/Tests/DisplayLayerStoreTests.swift`

- [ ] **Step 1: Write failing tests for signing and extension diagnostics**

Add:

```swift
func testWidgetKitStatusIsBundledAndReportsSharedStateDetail() {
    let store = DisplayLayerStore(
        homeDirectory: URL(fileURLWithPath: "/tmp/home", isDirectory: true),
        applicationsDirectory: URL(fileURLWithPath: "/tmp/apps", isDirectory: true),
        processList: { [] }
    )

    let status = store.status(for: .widgetKit)

    XCTAssertEqual(status.layer, .widgetKit)
    XCTAssertTrue(status.installed)
    XCTAssertTrue(status.detail.contains("Bundled"))
}
```

- [ ] **Step 2: Run tests**

Expected: PASS if Task 3 used the suggested implementation. If it fails, update the implementation without expanding scope.

- [ ] **Step 3: Add diagnostic command guidance to UI**

In `DiagnosticsPanel`, include WidgetKit guidance:

```swift
Text("If the widget appears blank, verify that QuotaWidget.app is Developer ID signed and that the WidgetKit extension is registered.")
    .font(.caption)
    .foregroundStyle(.secondary)
```

- [ ] **Step 4: Run tests**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macwidget/App/ControlCenterView.swift macwidget/App/DisplayLayerStore.swift macwidget/Tests/DisplayLayerStoreTests.swift
git commit -m "feat(macwidget): surface widgetkit diagnostics"
```

## Task 9: Make Touch Bar / Bar Install Status App-Callable

**Files:**
- Modify: `touchbar/install.sh`
- Modify: `touchbar/tests/test_install_contract.py`
- Modify: `macwidget/App/DisplayLayerStore.swift`
- Modify: `macwidget/Tests/DisplayLayerStoreTests.swift`

- [ ] **Step 1: Write failing tests for idempotent install script**

In `touchbar/tests/test_install_contract.py`, add:

```python
def test_install_script_supports_app_callable_mode(self):
    source = self.install_script.read_text()
    self.assertIn("QUOTABAR_INSTALL_DESTINATION", source)
    self.assertIn("QuotaBar.app", source)
    self.assertNotIn("sudo", source)
```

- [ ] **Step 2: Run test and verify failure**

```bash
python3 -m unittest touchbar.tests.test_install_contract -v
```

Expected: FAIL until script supports configurable destination.

- [ ] **Step 3: Update install script**

In `touchbar/install.sh`, use a configurable destination:

```bash
destination="${QUOTABAR_INSTALL_DESTINATION:-/Applications/QuotaBar.app}"
```

Keep install idempotent:

```bash
rm -rf "$destination"
ditto "$source_app" "$destination"
open "$destination"
```

- [ ] **Step 4: Add app status detection**

In `DisplayLayerStore.status(for: .touchBar)`, check `applicationsDirectory.appendingPathComponent("QuotaBar.app")`.

- [ ] **Step 5: Run tests**

```bash
python3 -m unittest touchbar.tests.test_install_contract -v
xcodebuild test -project macwidget/QuotaWidget.xcodeproj -scheme QuotaWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add touchbar/install.sh touchbar/tests/test_install_contract.py macwidget/App/DisplayLayerStore.swift macwidget/Tests/DisplayLayerStoreTests.swift
git commit -m "feat(macwidget): detect touch bar display install"
```

## Task 10: Document Control App Installation Model

**Files:**
- Modify: `README.md`
- Modify: `macwidget/README.md`
- Modify: `usage-widget/README.md`
- Modify: `touchbar/README.md`

- [ ] **Step 1: Write docs source test if the repo has one**

If no docs test exists, add source assertions to existing README-related tests only if there is an established pattern. Do not create a heavy docs test harness.

- [ ] **Step 2: Update README**

Document:

```markdown
### macOS Control App

Install `QuotaWidget.app` first. It is the control app for AI Agent Usage on macOS:

- configure provider accounts and API keys
- refresh usage data
- write sanitized shared state
- install or update optional display layers

Display layers do not store API keys.
```

- [ ] **Step 3: Update macwidget README**

Document:

```markdown
`QuotaWidget.app` is the primary macOS entry point. Use **Settings...** to open the control center. The Accounts tab manages local-agent and API-balance providers. The Displays tab installs optional display layers. The WidgetKit extension is bundled with the signed app and reads only App Group state.
```

- [ ] **Step 4: Update display layer READMEs**

In `usage-widget/README.md` and `touchbar/README.md`, add:

```markdown
Recommended installation is through `QuotaWidget.app` > Settings... > Displays. Manual installation remains available for development.
```

- [ ] **Step 5: Run relevant tests**

```bash
python3 -m unittest usage-widget.tests.test_install usage-widget.tests.test_widget_source -v
python3 -m unittest discover -s touchbar/tests -v
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add README.md macwidget/README.md usage-widget/README.md touchbar/README.md
git commit -m "docs: describe macos control app model"
```

## Task 11: Full Verification For Kimi CLI Before Handoff Back

**Files:** no new files unless fixing failures.

- [ ] **Step 1: Run design-system tests**

```bash
node --test docs/design/tests/design-system.test.mjs
```

Expected: all tests pass.

- [ ] **Step 2: Run core tests**

```bash
(cd core && python3 -m unittest discover -s tests -v)
```

Expected: all tests pass.

- [ ] **Step 3: Run Übersicht tests and compile check**

```bash
python3 -m unittest usage-widget.tests.test_widget_source usage-widget.tests.test_install -v
npx --yes esbuild usage-widget/index.jsx --bundle --format=esm --outfile=/tmp/usage-widget-check.js
```

Expected: tests pass and esbuild exits 0.

- [ ] **Step 4: Run Touch Bar tests**

```bash
python3 -m unittest discover -s touchbar/tests -v
```

Expected: all tests pass.

- [ ] **Step 5: Run macwidget tests**

```bash
xcodebuild test -project macwidget/QuotaWidget.xcodeproj -scheme QuotaWidget -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass. CoreSimulator warnings are acceptable if the final test result is `** TEST SUCCEEDED **`.

- [ ] **Step 6: Verify no local secrets or personal paths in diff**

```bash
git diff -- README.md macwidget usage-widget touchbar core docs | grep -nE 'AKIA|BEGIN PRIVATE|password:|api[_-]?key' || true
```

Expected: no secrets. Documentation may mention the term `API key`; it must not include actual key values, local usernames, or absolute user paths.

- [ ] **Step 7: Handoff to Codex for final review**

Do not merge after Kimi CLI implementation. Ask Codex to review:

- source diff
- test output
- signed-build behavior
- whether existing DeepSeek and SiliconFlow Keychain entries remain detected
- whether the WidgetKit blank-state regression is avoided

## Codex Final Acceptance Checklist

Codex should verify after Kimi CLI finishes:

- `QuotaWidget.app` still uses Keychain service `AI Agent Usage Widget`.
- Existing DeepSeek and SiliconFlow Keychain entries are detected as configured.
- `Settings...` opens the control center, not only the old accounts view.
- Displays tab shows Übersicht, macOS Widget, and Touch Bar / Bar.
- Übersicht installer supports both Unicode application-support paths.
- WidgetKit extension does not receive raw API keys.
- Signed installation is not replaced by an ad-hoc build during local testing.
- All verification commands in Task 11 pass.
