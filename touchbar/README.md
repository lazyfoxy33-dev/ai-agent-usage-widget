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

```bash
./install.sh          # 编译 + 开机自启（LaunchAgent）
```

安装脚本把稳定副本放到 `~/Applications/QuotaBar.app`，登录项只运行这个副本；
仓库内的 `QuotaBar.app` 仅是可重新生成的构建产物。

The installer puts the stable app at `~/Applications/QuotaBar.app`. The login
agent runs only that installed copy; the bundle inside the repository remains
a disposable build artifact.

首次可能弹一次 Keychain 授权（Claude 只读登录态）——点“始终允许”。Claude 不
写回；当前 Kimi 凭据只在官方锁内安全续期。

A one-time Keychain prompt may appear for read-only Claude access; choose
“Always Allow.” Claude is never written back. Current Kimi credentials refresh
only under the official lock.

卸载 / Uninstall:

```bash
launchctl bootout "gui/$(id -u)/com.quotabar.app"
rm -rf ~/Applications/QuotaBar.app
rm ~/Library/LaunchAgents/com.quotabar.app.plist
```

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
