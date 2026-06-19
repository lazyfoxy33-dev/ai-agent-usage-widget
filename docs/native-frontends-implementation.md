# Native Frontends Implementation / 原生前端落地记录

## Scope / 范围

PR #4 adds a cross-platform data layer, a native macOS WidgetKit frontend, and
a Windows Tauri desktop frontend. All frontends consume
`core/fetch_usage.py`; provider logic is not duplicated.

PR #4 新增跨平台数据层、macOS 原生 WidgetKit 前端与 Windows Tauri 桌面前端。
所有前端统一消费 `core/fetch_usage.py`，不重复实现提供商逻辑。

## Implemented / 已实现

- Claude reads macOS Keychain or the Windows/Linux
  `~/.claude/.credentials.json` file. It remains strictly read-only.
- Claude 在 macOS 读取 Keychain，在 Windows/Linux 读取
  `~/.claude/.credentials.json`，并始终保持只读。
- Codex active-refresh throttling no longer imports POSIX-only `fcntl`.
- Codex 主动刷新节流不再依赖仅 POSIX 可用的 `fcntl`。
- The macOS companion app runs the bundled shared core, atomically publishes
  JSON to an App Group, and reloads WidgetKit timelines.
- macOS 伴侣 app 运行内置共享 core，原子写入 App Group，并触发 WidgetKit
  timeline 刷新。
- The WidgetKit extension supports small and medium families, provider failure
  states, stale state, countdowns, and the shared brand palette and logos.
- WidgetKit 扩展支持小号/中号、提供商失败态、缓存态、倒计时及统一品牌色和图标。
- The Windows Tauri app provides a transparent frameless window, drag region,
  saved position, tray menu, manual/periodic refresh, and autostart.
- Windows Tauri app 提供透明无边框窗口、拖动区域、位置记忆、托盘菜单、手动/
  定时刷新和开机自启。
- Windows probes `python`, `python3`, and `py -3`, validates schema version 1,
  and preserves the previous UI when a refresh fails.
- Windows 会探测 `python`、`python3` 与 `py -3`，校验 schema version 1，并在
  刷新失败时保留原画面。

## Verified Locally / 本机已验证

- Python data layer: 101 tests.
- Python 数据层：101 项测试。
- Existing Übersicht frontend: 13 tests.
- 现有 Übersicht 前端：13 项测试。
- Existing Touch Bar frontend: 2 tests and app build.
- 现有 Touch Bar 前端：2 项测试及 app 构建。
- macOS WidgetKit: 3 Swift tests and unsigned Xcode build.
- macOS WidgetKit：3 项 Swift 测试及 Xcode 无签名构建。
- Windows web UI: 15 Node tests via `node --test src\\*.test.mjs`.
- Windows Web UI：通过 `node --test src\\*.test.mjs` 运行 15 项 Node 测试。
- On the current Windows host, the Python data layer has been verified to output
  schema_version 1.
- 当前 Windows host 已验证 Python 数据层可输出 schema_version 1。
- Tauri Rust backend: 5 tests and Windows release bundling produced MSI and
  NSIS installers.
- Tauri Rust 后端：5 项测试通过，Windows release 打包已产出 MSI 与 NSIS 安装包。

## Target Validation Required / 仍需目标平台验收

1. Sign both macOS targets with the user's Apple Team and the same registered
   App Group. Confirm the companion writes and the widget reads `usage.json`.
2. 使用用户 Apple Team 与同一个已注册 App Group 签名两个 macOS target，确认
   伴侣 app 写入且 widget 能读取 `usage.json`。
3. On Windows 10/11, verify the actual Claude, Codex, and Kimi credential/session
   locations for current official CLI releases.
4. 在 Windows 10/11 上核对当前官方 Claude、Codex 与 Kimi CLI 的真实凭据和
   session 路径。
5. Build and install MSI/NSIS, then verify WebView2 transparency, tray actions,
   startup registration, saved position, `curl.exe`, and proxy behavior.
6. 构建并安装 MSI/NSIS，验证 WebView2 透明窗口、托盘操作、开机自启、位置记忆、
   `curl.exe` 与代理行为。

Items 1–2 are pending because Apple signing credentials cannot be simulated by
this build environment. The current Windows host has already verified the Python
data layer outputting schema_version 1 and produced MSI/NSIS release bundles.
The remaining Windows-specific validations—installer execution, WebView2
transparent window, tray actions, startup registration, saved position,
`curl.exe`/proxy behavior, and final confirmation of real credential/session
paths for the official CLI releases—still need to be completed on a target
Windows 10/11 host.

第 1–2 项因当前环境无法模拟 Apple 签名凭据而保持待验收。当前 Windows 宿主机已验证
Python 数据层可输出 schema_version 1，并已产出 MSI/NSIS release 安装包；其余
Windows 专项验收——安装包实际执行、WebView2 透明窗口、托盘操作、开机自启、位置记忆、
`curl.exe`/代理行为，以及官方 CLI 真实凭据/session 路径的最终确认——仍需在目标
Windows 10/11 真机上完成。
