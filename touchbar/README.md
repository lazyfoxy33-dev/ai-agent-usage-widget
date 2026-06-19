# QuotaBar — Touch Bar 组件 / Touch Bar frontend

把 **Claude / Codex / Kimi** 的 5 小时与周用量常驻到 macOS Touch Bar。与 Übersicht 桌面
组件**共用同一套数据层**（`../core`）及其安全的新鲜度与凭据策略。

Pins **Claude / Codex / Kimi** 5-hour and weekly usage onto the macOS Touch Bar.
Shares the same data layer (`../core`) as the Übersicht widget, including its
safe freshness and credential policy.

## 设计 / Design

macOS（含 26 Tahoe）给单个 app 在控制条只有**一格、宽约 6 字符、不能加宽**，所以分两段：

- **常驻小格（瞄一眼）** —— 跟随**你正在用的 AI 应用**：前台是 Claude / Codex / Kimi 时显示
  对应额度；前台不是 AI 应用时回退到**最近用过的那个**（持久化，重启仍记得）；都无数据时
  再回退到用量最高的窗口。`C`=Claude `X`=Codex `K`=Kimi，用各自品牌色（按**已用** %）；
  数据过期/非实时时置灰。
- **点一下 → 整条详情**（系统模态触控栏，全宽）：每个 provider 一张紧凑「仪表卡」——
  品牌徽章 + 两条迷你进度条（`5H` 主色 / `7D` 柔色）+ 百分比，右侧 `⟳` 为最近一个窗口的
  重置倒计时。固定卡宽让整条长度收敛、不溢出。左侧 `✕`（或再点小格）收回。

macOS, including 26 Tahoe, gives each app only one narrow Control Strip slot,
so the UI has two levels:

- The persistent tray cell follows the AI app you're using: it shows the
  quota of whichever Claude / Codex / Kimi app is frontmost, falls back to the
  most recently used one (persisted across launches), and finally to the
  most-drained window when none has data. `C`, `X`, and `K` identify the
  providers in their brand colors; stale / non-live data is dimmed.
- Tapping the cell opens a full-width modal Touch Bar with one compact gauge
  per provider — a brand badge, two mini bars (`5H` accent, `7D` soft tint) and
  percentages — plus the nearest reset countdown. Fixed-width cards keep the
  bar's total length bounded. Tap `✕` or the tray cell again to close it.

## 数据来源 / Data

不重复实现取数：运行共享的 `core/fetch_usage.py`（构建时拷入 `QuotaBar.app/Contents/Resources/core`），
解析其 JSON。Codex 全本地；Claude/Kimi 用各自 CLI 的本地凭据调官方接口、5 分钟缓存。
详见 [项目 README](../README.md) 与 [core](../core)。

QuotaBar does not reimplement provider fetching. It runs the shared
`core/fetch_usage.py`, bundled under `QuotaBar.app/Contents/Resources/core`,
and parses the same JSON as Übersicht. See the [project README](../README.md)
and [core contract](../core/CONTRACT.md).

## 安装 / Install

最简单的方式：从
[Releases](https://github.com/lazyfoxy33-dev/ai-agent-usage-widget/releases) 下载
已公证的 `QuotaBar.dmg`，拖入「应用程序」并打开（已 Developer ID 签名 + 公证，
无 Gatekeeper 拦截；仍需 `python3`）。要开机自启，可改用下面的源码安装。

Easiest: download the notarized `QuotaBar.dmg` from
[Releases](https://github.com/lazyfoxy33-dev/ai-agent-usage-widget/releases), drag
it to Applications, and open it (Developer ID-signed + notarized, so no Gatekeeper
warning; still needs `python3`). For launch-at-login, build from source instead:

```bash
./install.sh          # 编译 + 开机自启（LaunchAgent）
```

安装脚本把稳定副本放到 `~/Applications/QuotaBar.app`，登录项只运行这个副本；
仓库内的 `QuotaBar.app` 仅是可重新生成的构建产物。

The installer puts the stable app at `~/Applications/QuotaBar.app`. The login
agent runs only that installed copy; the bundle inside the repository remains
a disposable build artifact.

首次可能弹一次 Keychain 授权（读取 Claude 登录态）——点“始终允许”。Claude 与
当前 Kimi 凭据在过期时都于官方锁内续期并原子写回；续期失败回退过期态。

A one-time Keychain prompt may appear to read the Claude login; choose “Always
Allow.” Both Claude and current Kimi credentials are refreshed under the
official lock and written back atomically when expired, falling back to the
expired state on failure.

卸载 / Uninstall:

```bash
launchctl bootout "gui/$(id -u)/com.quotabar.app"
rm -rf ~/Applications/QuotaBar.app
rm ~/Library/LaunchAgents/com.quotabar.app.plist
```

## 分发 / Distribution

把 QuotaBar 打包成别人可下载、直接运行（不弹 Gatekeeper 警告）的 `.dmg`：

```bash
export QUOTABAR_TEAM="YOUR_TEAM_ID"
export QUOTABAR_NOTARY_PROFILE="quotabar-notary"
./distribute.sh        # 产物在 build/dist/QuotaBar.dmg
```

一次性前置（仅首次）：

1. 钥匙串里要有 **Developer ID Application** 证书
   （Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ ＋ ▸ Developer ID Application）。
   QuotaBar 没有 App Groups / 沙盒权限，**无需**注册 App ID 或描述文件。
2. 存一次公证凭据：
   `xcrun notarytool store-credentials quotabar-notary --apple-id <id> --team-id <TEAMID> --password <app专用密码>`。

`distribute.sh` 会编译、用 Developer ID 强化运行时签名、公证并装订（staple）app 与 dmg。
不设 `QUOTABAR_NOTARY_PROFILE` 则只签名不公证，接收方需右键打开绕过 Gatekeeper。

> 运行依赖：QuotaBar 启动时调用 `/usr/bin/python3`（来自 Xcode Command Line Tools）。
> 干净系统首次运行可能提示安装命令行工具——这是 macOS 的标准行为。

To package QuotaBar as a downloadable, Gatekeeper-clean `.dmg`, run `./distribute.sh`
with `QUOTABAR_TEAM` and `QUOTABAR_NOTARY_PROFILE` set (see the one-time prerequisites
above). It Developer ID-signs with the hardened runtime, notarizes and staples both the
app and the dmg. Recipients need `/usr/bin/python3` (Xcode Command Line Tools) at runtime.

## 调试 / Debug

```bash
./build.sh                                  # 仅编译
./QuotaBar.app/Contents/MacOS/QuotaBar --once   # 打印三家用量后退出
```

## 说明 / Notes

- 需带 Touch Bar 的 Mac（已在 M1 13" MacBook Pro / macOS 26.5 上验证）。
- 私有接口：`DFRFoundation` 的 `DFRElementSetControlStripPresenceForIdentifier`、
  `NSTouchBarItem +addSystemTrayItem:`（小格）、
  `NSTouchBar +presentSystemModalTouchBar:…` / `+minimizeSystemModalTouchBar:`（整条），
  均经 ObjC runtime / dlsym 调用。
- 运行需要 `/usr/bin/python3`（macOS 自带）。app 为 ad-hoc 签名，仅本机使用。

- Requires a Mac with a Touch Bar; verified on an M1 13-inch MacBook Pro with
  macOS 26.5.
- Uses private Touch Bar APIs through the Objective-C runtime and `dlsym`.
- Requires macOS `/usr/bin/python3`. The app is ad-hoc signed for local use.
