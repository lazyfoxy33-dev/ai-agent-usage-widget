# QuotaWidget for macOS / macOS 原生小组件

QuotaWidget is a native WidgetKit frontend for Claude, Codex, and Kimi Code
usage. A menu bar companion app runs the shared Python data layer every three
minutes, writes the JSON contract into an App Group, and asks WidgetKit to
reload.

QuotaWidget 是 Claude、Codex 与 Kimi Code 用量的原生 WidgetKit 前端。菜单栏
伴侣 app 每三分钟运行共享 Python 数据层，把 JSON 契约写入 App Group，并通知
WidgetKit 刷新。

## Download / 下载

Most users don't need to build anything: download the notarized
`QuotaWidget.dmg` from
[Releases](https://github.com/lazyfoxy33-dev/ai-agent-usage-widget/releases), drag
**QuotaWidget** to Applications, open it (it lives in the menu bar), and add
**AI Agent Usage** from the widget gallery. It is Developer ID-signed and notarized,
so there is no Gatekeeper warning. You still need `python3` (see the note below).

大多数用户无需自行构建：从
[Releases](https://github.com/lazyfoxy33-dev/ai-agent-usage-widget/releases) 下载
已公证的 `QuotaWidget.dmg`，把 **QuotaWidget** 拖入「应用程序」并打开（在菜单栏），
再从小组件库添加 **AI Agent Usage**。已 Developer ID 签名 + 公证，无 Gatekeeper
拦截；仍需要 `python3`（见下方说明）。

## Requirements (building from source) / 要求（从源码构建）

- macOS 14 or later / macOS 14 或更高版本
- Xcode 16 or later / Xcode 16 或更高版本
- Python 3 and `curl` / Python 3 与 `curl`
- An Apple Developer Team that can register an App Group
- 可注册 App Group 的 Apple Developer Team

Widget extensions are sandboxed. Sharing CLI-derived data with the extension
requires a signed App Group; an unsigned build can compile and run tests, but
cannot complete the real app-to-widget data path.

Widget 扩展处于沙箱中。要把 CLI 数据共享给扩展，必须使用已签名的 App Group；
无签名构建可以编译和运行测试，但不能打通真实的 app 到 widget 数据链路。

## Sign And Install / 签名与安装

1. In Apple Developer Certificates, Identifiers & Profiles, create an App Group
   such as `group.example.QuotaWidget`.
2. Open `QuotaWidget.xcodeproj`, select both `QuotaWidgetApp` and
   `QuotaWidgetExtension`, choose the same Team, and enable the same App Group.
3. Set `APP_GROUP_ID` in the project build settings to that registered value.
4. Build and run `QuotaWidgetApp`, then add **AI Agent Usage** from the macOS
   widget gallery.

1. 在 Apple Developer 的 Certificates, Identifiers & Profiles 中创建 App
   Group，例如 `group.example.QuotaWidget`。
2. 打开 `QuotaWidget.xcodeproj`，为 `QuotaWidgetApp` 与
   `QuotaWidgetExtension` 选择同一个 Team，并启用同一个 App Group。
3. 把工程 Build Settings 中的 `APP_GROUP_ID` 改为已注册的值。
4. 构建并运行 `QuotaWidgetApp`，然后从 macOS 小组件库添加
   **AI Agent Usage**。

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
2. Ensure the App IDs `dev.lazyfoxy.QuotaWidget` and
   `dev.lazyfoxy.QuotaWidget.extension` have the **App Groups** capability
   enabled (the same setup development signing needs).
   确认 App ID `dev.lazyfoxy.QuotaWidget` 与 `.extension` 都启用了 **App Groups**
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

- **Widget says to open the app:** launch `QuotaWidgetApp` and use manual
  refresh once. If it remains empty, verify both targets use exactly the same
  registered App Group.
- **小组件提示打开 app：**启动 `QuotaWidgetApp` 并手动刷新一次；若仍为空，
  检查两个 target 是否使用完全相同且已注册的 App Group。
- **Refresh fails:** run `cd ../core && python3 fetch_usage.py` and resolve the
  provider-specific login or network message first.
- **刷新失败：**运行 `cd ../core && python3 fetch_usage.py`，先处理对应提供商的
  登录或网络提示。
