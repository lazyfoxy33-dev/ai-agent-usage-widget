# QuotaWidget Account Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a QuotaWidget menu bar Accounts settings UI for all six providers, with Keychain-backed API-key storage for DeepSeek, SiliconFlow, and OpenRouter.

**Architecture:** Keep provider fetching centralized in `core/fetch_usage.py`; macOS app code only stores API keys in Keychain and injects them into the fetcher process environment. Add a SwiftUI settings window and small app-side account status model; the widget extension remains a sanitized `usage.json` consumer.

**Tech Stack:** SwiftUI, AppKit menu bar app, macOS Keychain Services, XCTest, existing Python fetcher contract.

---

## File Structure

- Create `macwidget/App/APIKeyStore.swift`: Keychain wrapper for DeepSeek, SiliconFlow, and OpenRouter API keys.
- Create `macwidget/App/AccountSettingsView.swift`: SwiftUI Accounts UI and provider-row interactions.
- Modify `macwidget/App/UsageFetcher.swift`: accept extra environment variables for API keys and add a targeted provider test helper.
- Modify `macwidget/App/QuotaWidgetApp.swift`: open settings window, provide account view model, inject Keychain keys during refresh.
- Modify `macwidget/Shared/UsageStore.swift`: write Codex active-refresh config if needed by the settings UI.
- Modify `macwidget/Tests/UsageContractTests.swift` or add `macwidget/Tests/APIKeyStoreTests.swift`: cover keychain abstraction through injectable fake storage.
- Modify `macwidget/Tests/UsageStoreTests.swift`: cover app-side config writing if added.
- Modify `macwidget/README.md` and top-level `README.md`: document app-based account setup.

## Task 1: Keychain API-Key Store

**Files:**
- Create: `macwidget/App/APIKeyStore.swift`
- Create: `macwidget/Tests/APIKeyStoreTests.swift`

- [ ] **Step 1: Write failing tests for provider mapping and fake storage**

Add tests using an injected in-memory backend, not the real Keychain:

```swift
func testStoresReadsAndDeletesAPIKeysByProvider() throws {
    let backend = InMemoryCredentialBackend()
    let store = APIKeyStore(backend: backend)

    try store.save("deepseek-key", for: .deepseek)
    try store.save("openrouter-key", for: .openrouter)

    XCTAssertEqual(try store.read(.deepseek), "deepseek-key")
    XCTAssertEqual(try store.read(.openrouter), "openrouter-key")

    try store.delete(.deepseek)
    XCTAssertNil(try store.read(.deepseek))
    XCTAssertEqual(try store.read(.openrouter), "openrouter-key")
}
```

Run:

```bash
cd macwidget
xcodebuild -project QuotaWidget.xcodeproj -scheme QuotaWidget -derivedDataPath build/DerivedData APP_GROUP_ID=group.dev.lazyfoxy.QuotaWidget CODE_SIGNING_ALLOWED=NO test
```

Expected: FAIL because `APIKeyStore`, `InMemoryCredentialBackend`, and API-key provider ids do not exist.

- [ ] **Step 2: Implement provider IDs and injectable credential backend**

Create `APIKeyProviderID` with cases:

```swift
enum APIKeyProviderID: String, CaseIterable, Identifiable {
    case deepseek
    case siliconflow
    case openrouter

    var id: String { rawValue }
    var envName: String {
        switch self {
        case .deepseek: return "DEEPSEEK_API_KEY"
        case .siliconflow: return "SILICONFLOW_API_KEY"
        case .openrouter: return "OPENROUTER_API_KEY"
        }
    }
}
```

Create protocol:

```swift
protocol CredentialBackend {
    func read(service: String, account: String) throws -> String?
    func save(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}
```

Create `APIKeyStore` using service `AI Agent Usage Widget`.

- [ ] **Step 3: Implement real Keychain backend**

Implement `KeychainCredentialBackend` using Security framework:

- `SecItemCopyMatching` for read
- `SecItemAdd` or `SecItemUpdate` for save
- `SecItemDelete` for delete

Do not log key values. Do not expose key values in errors.

- [ ] **Step 4: Verify tests pass**

Run the same `xcodebuild ... test` command.

Expected: PASS for the new `APIKeyStoreTests`.

- [ ] **Step 5: Commit**

```bash
git add macwidget/App/APIKeyStore.swift macwidget/Tests/APIKeyStoreTests.swift
git commit -m "feat(macwidget): add api key keychain store"
```

## Task 2: Fetcher Environment Injection

**Files:**
- Modify: `macwidget/App/UsageFetcher.swift`
- Modify: `macwidget/Tests/UsageContractTests.swift`

- [ ] **Step 1: Write failing test for environment construction**

Add a pure test that does not run Python:

```swift
func testFetcherEnvironmentIncludesConfiguredAPIKeys() {
    let env = UsageFetcher.environment(
        base: ["PATH": "/usr/bin"],
        apiKeys: [.deepseek: "deepseek-key", .openrouter: "openrouter-key"]
    )

    XCTAssertEqual(env["PATH"], "/usr/bin")
    XCTAssertEqual(env["DEEPSEEK_API_KEY"], "deepseek-key")
    XCTAssertEqual(env["OPENROUTER_API_KEY"], "openrouter-key")
    XCTAssertNil(env["SILICONFLOW_API_KEY"])
}
```

Run `xcodebuild ... test`.

Expected: FAIL because `UsageFetcher.environment(base:apiKeys:)` does not exist.

- [ ] **Step 2: Add environment helper and fetch overload**

Add:

```swift
static func environment(
    base: [String: String] = ProcessInfo.processInfo.environment,
    apiKeys: [APIKeyProviderID: String]
) -> [String: String]
```

Modify `fetch(timeout:)` to call a new overload:

```swift
static func fetch(
    timeout: TimeInterval = 30,
    apiKeys: [APIKeyProviderID: String] = [:]
) throws -> String
```

Set `process.environment` to the merged environment.

- [ ] **Step 3: Add provider-result test helper**

Add a small parser helper:

```swift
static func providerStatus(from json: String, providerKey: String) -> UsageProvider?
```

Use `JSONSerialization` or `UsagePayload.decode`; keep it sanitized.

- [ ] **Step 4: Verify tests pass**

Run `xcodebuild ... test`.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macwidget/App/UsageFetcher.swift macwidget/Tests/UsageContractTests.swift
git commit -m "feat(macwidget): inject provider api keys into fetcher"
```

## Task 3: Accounts View Model

**Files:**
- Create: `macwidget/App/AccountSettingsView.swift`
- Modify: `macwidget/Tests/UsageContractTests.swift`

- [ ] **Step 1: Write failing tests for row state derivation**

Add tests for status text using existing `UsagePayload.preview` and fake key state:

```swift
func testAccountRowsIncludeAllSixProviders() {
    let model = AccountSettingsModel(
        payload: .preview,
        configuredAPIKeys: [.siliconflow],
        codexActiveRefresh: false
    )

    XCTAssertEqual(model.rows.map(\.id), [
        .claude, .codex, .kimi, .deepseek, .siliconflow, .openrouter
    ])
}
```

Expected: FAIL because model types do not exist.

- [ ] **Step 2: Implement provider IDs and row state**

Create:

```swift
enum AccountProviderID: String, CaseIterable, Identifiable {
    case claude, codex, kimi, deepseek, siliconflow, openrouter
    var id: String { rawValue }
}

enum AccountKind {
    case localAgent
    case apiKey
}

struct AccountRowState: Identifiable, Equatable {
    let id: AccountProviderID
    let name: String
    let kind: AccountKind
    let configured: Bool
    let statusText: String
    let detailText: String?
    let balanceSummary: String?
}
```

Create `AccountSettingsModel` as a pure value type that derives rows from:

- latest `UsagePayload?`
- configured API-key provider set
- Codex active-refresh flag

- [ ] **Step 3: Implement SwiftUI view shell**

`AccountSettingsView` should display:

- `Local agent accounts` section
- `API balance accounts` section
- Six provider rows
- Action buttons matching the spec
- Privacy note

Keep the view thin; put row derivation in the model from Step 2.

- [ ] **Step 4: Verify tests pass**

Run `xcodebuild ... test`.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macwidget/App/AccountSettingsView.swift macwidget/Tests/UsageContractTests.swift
git commit -m "feat(macwidget): add account settings model"
```

## Task 4: Settings Window And Menu Integration

**Files:**
- Modify: `macwidget/App/QuotaWidgetApp.swift`
- Modify: `macwidget/Tests/UsageContractTests.swift`

- [ ] **Step 1: Write failing tests for Keychain-to-fetch API-key collection**

Add pure test around a helper:

```swift
func testCollectsOnlyConfiguredAPIKeys() throws {
    let backend = InMemoryCredentialBackend()
    let store = APIKeyStore(backend: backend)
    try store.save("sf-key", for: .siliconflow)

    let keys = try QuotaWidgetModel.apiKeys(from: store)

    XCTAssertEqual(keys, [.siliconflow: "sf-key"])
}
```

Expected: FAIL because `QuotaWidgetModel.apiKeys(from:)` does not exist.

- [ ] **Step 2: Inject API keys during refresh**

Modify `QuotaWidgetModel.refresh()`:

- read API keys from `APIKeyStore`
- pass them to `UsageFetcher.fetch(apiKeys:)`
- preserve existing status behavior

Do not crash refresh if Keychain read fails; set user-visible status and keep
the last widget data.

- [ ] **Step 3: Add Settings menu item**

In `MenuBarExtra`, add:

- `Settings...`
- divider before Quit

Opening settings should create or activate an `NSWindow` containing
`AccountSettingsView`. Reuse one window rather than creating many.

- [ ] **Step 4: Wire row actions**

Implement minimal first-version actions:

- API key Add/Replace opens secure sheet and saves to Keychain.
- Remove deletes the key.
- Test runs fetcher and updates status text.
- Claude/Kimi login help opens a docs URL or provider app URL.
- Codex probe toggle writes the existing config file.

- [ ] **Step 5: Verify tests pass and app builds**

Run:

```bash
cd macwidget
xcodebuild -project QuotaWidget.xcodeproj -scheme QuotaWidget -derivedDataPath build/DerivedData APP_GROUP_ID=group.dev.lazyfoxy.QuotaWidget CODE_SIGNING_ALLOWED=NO test
QUOTAWIDGET_UNSIGNED=1 ./build.sh
```

Expected: tests pass and build succeeds.

- [ ] **Step 6: Commit**

```bash
git add macwidget/App/QuotaWidgetApp.swift macwidget/App/AccountSettingsView.swift macwidget/Tests/UsageContractTests.swift
git commit -m "feat(macwidget): add account settings window"
```

## Task 5: Codex Active Refresh Config

**Files:**
- Modify: `macwidget/Shared/UsageStore.swift` or create `macwidget/App/AppConfigStore.swift`
- Modify: `macwidget/Tests/UsageStoreTests.swift`

- [ ] **Step 1: Write failing tests for config write**

Add test using a temporary directory:

```swift
func testWritesCodexActiveRefreshConfig() throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = AppConfigStore(baseDirectory: dir)

    try store.writeCodexActiveRefresh(enabled: true, intervalSeconds: 1800)
    let data = try Data(contentsOf: store.configURL)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    XCTAssertEqual(json?["codex_active_refresh"] as? Bool, true)
    XCTAssertEqual(json?["codex_refresh_interval_seconds"] as? Int, 1800)
}
```

Expected: FAIL because `AppConfigStore` does not exist.

- [ ] **Step 2: Implement config store**

Write JSON to the same location read by `core/usage/config.py`:

- default: `~/.config/ai-agent-usage-widget/config.json`
- support test injection with `baseDirectory`

- [ ] **Step 3: Connect Codex toggle**

Make `Enable Probe` / `Disable Probe` write the config file and update row state.

- [ ] **Step 4: Verify tests pass**

Run `xcodebuild ... test`.

- [ ] **Step 5: Commit**

```bash
git add macwidget/App/AppConfigStore.swift macwidget/App/AccountSettingsView.swift macwidget/Tests/UsageStoreTests.swift
git commit -m "feat(macwidget): configure codex active refresh"
```

## Task 6: Documentation And Final Verification

**Files:**
- Modify: `README.md`
- Modify: `macwidget/README.md`

- [ ] **Step 1: Update docs**

Document:

- QuotaWidget app has `Settings...`
- Claude/Codex/Kimi are detected from local official stores
- DeepSeek/SiliconFlow/OpenRouter keys are stored in Keychain
- Shell env vars still work for the shared data layer, but app settings are the
  recommended GUI path
- Widget extension never sees raw keys

- [ ] **Step 2: Run final verification**

Run:

```bash
cd core && python3 -m unittest discover -s tests
cd ../usage-widget && python3 -m unittest discover -v
cd ../windows-widget && node --test src/render.test.mjs
cd ../touchbar && python3 -m unittest discover -s tests
cd ../macwidget && xcodebuild -project QuotaWidget.xcodeproj -scheme QuotaWidget -derivedDataPath build/DerivedData APP_GROUP_ID=group.dev.lazyfoxy.QuotaWidget CODE_SIGNING_ALLOWED=NO test
cd ../macwidget && QUOTAWIDGET_UNSIGNED=1 ./build.sh
```

Expected:

- Core tests pass.
- Übersicht tests pass.
- Windows renderer tests pass.
- Touch Bar tests pass.
- Xcode tests pass.
- Unsigned macOS build succeeds.

- [ ] **Step 3: Run privacy checks**

Run:

```bash
git diff --check
git diff | grep -F "$HOME" || true
git diff | grep -F "$(id -un)" || true
git diff | rg 'AKIA|BEGIN PRIVATE|Bearer [A-Za-z0-9_./+=-]{8,}|provider token|secret token' || true
```

Expected: no private paths, usernames, or credential values in tracked changes.

- [ ] **Step 4: Commit docs**

```bash
git add README.md macwidget/README.md
git commit -m "docs: document quotawidget account settings"
```

## Execution Constraints For Kimi

- Execute one task at a time.
- Do not use Kimi subagents for this plan.
- Do not commit unless the task explicitly says to commit.
- After each Kimi task, Codex reviews diff and runs the listed verification.
- If Kimi stalls or gives no output for more than two minutes, Codex must first
  inspect process state and logs, explain the likely cause, and try to resume or
  continue through Kimi before taking over directly.
