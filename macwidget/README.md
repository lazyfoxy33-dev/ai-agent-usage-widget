# QuotaWidget for macOS / macOS 菜单栏 app

QuotaWidget is the macOS menu bar app for Claude, Codex, and Kimi Code usage plus
DeepSeek, SiliconFlow, and OpenRouter balances. It runs the shared Python data
layer on a timer and writes the sanitized JSON contract into its App Group
container.

QuotaWidget 是 macOS 菜单栏 app：状态栏常驻图标，展示 Claude、Codex、Kimi Code 用量
与 DeepSeek、SiliconFlow、OpenRouter 余额。它定时运行共享 Python 数据层，并把脱敏后的
JSON 契约写入 App Group 容器。

`QuotaWidget.app` is the primary macOS entry point. Use **设置…** (Settings) to open the settings window: a single page lists the local-agent and API-balance providers with their status and actions, plus a Touch Bar row and a **Touch Bar 显示** section where you choose and reorder the providers shown on the strip. The window is in Chinese.

## Download / 下载

Most users don't need to build anything: download the Developer ID-signed
`QuotaWidget.dmg` from
[Releases](https://github.com/lazyfoxy33-dev/ai-agent-usage-widget/releases), drag
**QuotaWidget** to Applications, and open it (it lives in the menu bar). It is
Developer ID-signed; if the release note says it is not notarized, right-click →
Open on first launch. You still need `python3` (see the note below).

大多数用户无需自行构建：从
[Releases](https://github.com/lazyfoxy33-dev/ai-agent-usage-widget/releases) 下载
`QuotaWidget.dmg`（Developer ID 签名），把 **QuotaWidget** 拖入「应用程序」并打开（在菜单栏）。
若对应 Release 说明标注未公证，首次打开请在 Finder 中右键 → 打开。仍需要 `python3`（见下方说明）。

## Requirements (building from source) / 要求（从源码构建）

- macOS 14 or later / macOS 14 或更高版本
- Xcode 16 or later / Xcode 16 或更高版本
- Python 3 and `curl` / Python 3 与 `curl`
- An Apple Developer Team that can register an App Group — only needed for
  Developer ID distribution
- 可注册 App Group 的 Apple Developer Team —— 仅分发签名时需要

Local development and tests do not need a registered App Group: with
`CODE_SIGNING_ALLOWED=NO` the App Group container is unavailable, yet the app
still builds, the tests pass, and usage still renders — only the Diagnostics
shared-state row reports unavailable.

本地开发与测试不需要注册 App Group：使用 `CODE_SIGNING_ALLOWED=NO` 时 App Group
容器不可用，但 app 仍可编译、测试照常通过、用量照常显示，只有 Diagnostics 里的
共享状态会显示为不可用。

## Sign And Install / 签名与安装

1. In Apple Developer Certificates, Identifiers & Profiles, create an App Group
   such as `group.example.QuotaWidget`.
2. Open `QuotaWidget.xcodeproj`, select `QuotaWidgetApp`, choose your Team, and
   enable that App Group.
3. Set `APP_GROUP_ID` in the project build settings to the registered value.
4. Build and run `QuotaWidgetApp`; it appears in the menu bar.

1. 在 Apple Developer 的 Certificates, Identifiers & Profiles 中创建 App
   Group，例如 `group.example.QuotaWidget`。
2. 打开 `QuotaWidget.xcodeproj`，为 `QuotaWidgetApp` 选择你的 Team，并启用同一个
   App Group。
3. 把工程 Build Settings 中的 `APP_GROUP_ID` 改为已注册的值。
4. 构建并运行 `QuotaWidgetApp`，它会出现在菜单栏。

Command-line install / 命令行安装：

```bash
export QUOTAWIDGET_TEAM="YOUR_TEAM_ID"
export QUOTAWIDGET_APP_GROUP="group.example.QuotaWidget"
./install.sh
```

The companion app appears only in the menu bar. Use **立即刷新** for a manual
refresh. Failed refreshes keep the last successful snapshot.

伴侣 app 只显示在菜单栏。点击**立即刷新**可手动刷新；刷新失败时会保留上一次
成功数据。

## Account settings / 账户设置

点击菜单栏的 QuotaWidget，选择 **设置…** 打开账户设置窗口：

- **Claude、Codex、Kimi Code** 从本地官方客户端存储自动检测；Claude 与 Kimi
  只需正常使用官方客户端即可识别，Codex 可额外开启 **Enable Probe** 主动探测。
- **DeepSeek、SiliconFlow、OpenRouter** 点 **Add Key** 输入 API key；key 通过
  macOS Keychain（服务名 `AI Agent Usage Widget`）保存，可 **Test** 验证或
  **Remove** 删除。
- 共享数据层仍兼容 `DEEPSEEK_API_KEY`、`SILICONFLOW_API_KEY`、`OPENROUTER_API_KEY`
  等环境变量，但 GUI 设置是推荐路径。
- 菜单栏 app 与 Touch Bar 前端只交换脱敏的 JSON 契约，永远不会接触原始 API key。

Click QuotaWidget in the menu bar and choose **设置…** to open the account
settings window:

- **Claude, Codex, and Kimi Code** are auto-detected from local official-client
  storage; Claude and Kimi are recognized once you use the official client, and
  Codex can additionally enable **Enable Probe** for active probing.
- For **DeepSeek, SiliconFlow, and OpenRouter**, click **Add Key** to enter an API
  key; keys are stored in the macOS Keychain (service `AI Agent Usage Widget`)
  and can be **Test**ed or **Remove**d.
- **OpenRouter** uses the official "Sign in with OpenRouter" OAuth PKCE flow: click
  **登录 OpenRouter** and authorize in the window — no pasted key.
- When the **DeepSeek Harness** (`dsh`) already configured `DEEPSEEK_API_KEY` or
  `OPENROUTER_API_KEY`, that value is reused read-only from
  `~/.dsh/.credentials.yaml` (the row shows a `dsh` tag); a Keychain entry wins.
- The shared data layer still supports `DEEPSEEK_API_KEY`, `SILICONFLOW_API_KEY`,
  `OPENROUTER_API_KEY`, and similar environment variables, but the GUI settings
  are the recommended path.
- The menu bar app and the Touch Bar frontend exchange only the sanitized JSON
  contract and never see raw API keys.
- The app mirrors its sanitized payload to
  `~/.config/ai-agent-usage-widget/usage.json` (mode 0600) after every refresh; the
  Touch Bar agent reads that mirror (under 15 minutes old) so both frontends agree on
  SiliconFlow / DeepSeek / OpenRouter, whose credentials only this app can reach.
- **Touch Bar 显示** decides which providers appear on the strip and in which
  order (all six are selectable: Claude / Codex / Kimi render gauges, DeepSeek /
  SiliconFlow / OpenRouter render balances); reordering uses the inline ▲▼
  buttons and the agent picks the change up on its next refresh.

## Distribution / 分发

`install.sh` uses development signing for your own machine. To produce a `.dmg`
others can download and run, use `distribute.sh`, which builds with a
**Developer ID Application** certificate and **Hardened Runtime**, notarizes with
`notarytool`, staples the ticket, and packages a `.dmg`.

`install.sh` 用开发签名，只适合自己的机器。要产出可供别人下载运行的 `.dmg`，用
`distribute.sh`：它以 **Developer ID Application** 证书 + **Hardened Runtime**
构建，用 `notarytool` 公证、装订票据并打包成 `.dmg`。

One-time setup / 一次性准备：

1. In Xcode → Settings → Accounts → Manage Certificates, create a
   **Developer ID Application** certificate.
   在 Xcode → Settings → Accounts → Manage Certificates 中创建一张
   **Developer ID Application** 证书。
2. Ensure the App ID `dev.lazyfoxy.QuotaWidget` has the **App Groups** capability
   enabled (the same setup development signing needs).
   确认 App ID `dev.lazyfoxy.QuotaWidget` 启用了 **App Groups**
   能力（和开发签名所需的一致）。
3. Store notarization credentials once / 存一次公证凭证：

   ```bash
   xcrun notarytool store-credentials quotawidget-notary \
     --apple-id "you@example.com" \
     --team-id "YOUR_TEAM_ID" \
     --password "app-specific-password"   # from appleid.apple.com
   ```

Build, notarize and package / 构建、公证、打包：

```bash
export QUOTAWIDGET_TEAM="YOUR_TEAM_ID"
export QUOTAWIDGET_NOTARY_PROFILE="quotawidget-notary"
./distribute.sh
# → build/dist/QuotaWidget.dmg
```

> **End users need `python3`.** The companion app runs the shared Python data
> layer via `/usr/bin/python3`, which recent macOS does not ship by default; the
> first launch may prompt to install the Command Line Tools. Mention this in your
> release notes.
>
> **终端用户需要 `python3`。** 伴侣 app 通过 `/usr/bin/python3` 运行共享数据层，
> 新版 macOS 默认不自带，首次启动可能会提示安装命令行工具。请在发布说明里注明。

## Development / 开发

The generated Xcode project is committed. To regenerate it after editing
`project.yml`, install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and run:

生成后的 Xcode 工程已提交。修改 `project.yml` 后，如需重新生成，请安装
[XcodeGen](https://github.com/yonaskolb/XcodeGen) 并运行：

```bash
xcodegen generate
```

Run tests without signing / 无签名运行测试：

```bash
xcodebuild test \
  -project QuotaWidget.xcodeproj \
  -scheme QuotaWidget \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Unsigned build-only verification / 仅做无签名构建验证：

```bash
QUOTAWIDGET_UNSIGNED=1 ./build.sh
```

## Troubleshooting / 排错

- **Menu bar shows nothing:** make sure `QuotaWidget.app` is running and use
  **立即刷新** once. If it stays empty, set `APP_GROUP_ID` to an App Group that
  is registered for `dev.lazyfoxy.QuotaWidget`.
- **菜单栏没有内容：**确认 `QuotaWidget.app` 正在运行，并点一次**立即刷新**；若仍为空，
  检查 `APP_GROUP_ID` 是否为 `dev.lazyfoxy.QuotaWidget` 已注册的 App Group。
- **Refresh fails:** run `cd ../core && python3 fetch_usage.py` and resolve the
  provider-specific login or network message first.
- **刷新失败：**运行 `cd ../core && python3 fetch_usage.py`，先处理对应提供商的
  登录或网络提示。
