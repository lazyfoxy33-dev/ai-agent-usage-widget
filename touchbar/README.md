# QuotaBar — Touch Bar 组件 / Touch Bar frontend

把 **Claude / Codex / Kimi** 的 5 小时与周用量常驻到 macOS Touch Bar。与菜单栏
app**共用同一套数据层**（`../core`）及其安全的新鲜度与凭据策略。

Pins **Claude / Codex / Kimi** 5-hour and weekly usage onto the macOS Touch Bar.
Shares the same data layer (`../core`) as the menu bar app, including its
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

## 显示哪些 provider / Which providers

Touch Bar 上显示谁、按什么顺序，可在 **QuotaWidget.app → 设置… → Touch Bar 显示** 里配置：勾选的
provider 按列表顺序排列，用行内 ▲▼ 调整顺序。六个 provider 都可以选——Claude / Codex / Kimi 是额度仪表，
DeepSeek / SiliconFlow / OpenRouter 显示余额金额与估算可用天数。默认是 `Claude, Codex, Kimi`。

设置写入共享配置 `~/.config/ai-agent-usage-widget/config.json` 的 `touchbar_providers`，QuotaBar 每
60 秒刷新时重读一次，因此**改完一分钟内生效，无需重启**。

收起那一小格**不受这个选择影响**：它始终回答「我面前这个 coding 工具现在怎么样」——优先显示**前台**的
Claude / Codex / Kimi，没有前台 AI 应用时显示最近用过的，再退到用量最高的那个。设置只决定**展开后**显示
谁、按什么顺序。

选择的 provider 越多，展开后的格子会自动**变窄**，否则超出条宽的部分会被系统直接丢掉（这是 macOS 的
静默行为：放不下的 item 直接不显示）。实测 13" MacBook Pro 的 modal 条给格子的预算约 600pt：3 个以内保持
原 170pt，5 个为 105pt，6 个为 86pt；格子窄于 122pt 时自动改用紧凑排版（省掉 `5H`/`Wk` 行标签、字号略小）。
若某台机器的条更窄，QuotaBar 还会在呈现后自检——发现格子被丢弃就自动再收窄重试（最多 3 次）。

排查命令：

```bash
# 当前生效的选择与格子宽度
./QuotaBar.app/Contents/MacOS/QuotaBar --layout

# 真机自检：实际呈现一次，报告每个格子是否被显示（高度 0 = 被系统丢弃）
./QuotaBar.app/Contents/MacOS/QuotaBar --present-test

# 依次用 170→90pt 呈现，量出这台机器能放下多少个格子
./QuotaBar.app/Contents/MacOS/QuotaBar --present-test --measure
```

Which providers appear, and in what order, is configured in **QuotaWidget.app → 设置… →
Touch Bar 显示**: selected providers are listed in display order and reordered with the
inline ▲▼ buttons. All six are selectable — Claude / Codex / Kimi render quota gauges,
while DeepSeek / SiliconFlow / OpenRouter render a balance amount with an estimated
days-left trend. The default is `Claude, Codex, Kimi`.

The choice is stored as `touchbar_providers` in the shared
`~/.config/ai-agent-usage-widget/config.json`; QuotaBar re-reads it on its 60-second
refresh, so **changes apply within a minute without a restart**.

The collapsed tray cell is **not affected by the selection**: it always answers "what is
the coding tool in front of me doing" — preferring the frontmost Claude / Codex / Kimi,
then the most recently used one, then the most-drained window. The setting only decides
what the **expanded** bar shows, and in which order.

The more providers you select, the narrower each cell becomes, because macOS silently
drops items that do not fit. Measured on a 13" MacBook Pro the modal strip offers cells
about 600pt: up to three keep the original 170pt card, five use 105pt and six use 86pt,
and below 122pt a cell switches to a compact layout (no `5H`/`Wk` labels, smaller
figures). If a Mac turns out to be tighter, the agent re-checks its own presentation and
retries narrower (up to three times).

Diagnostics:

```bash
./QuotaBar.app/Contents/MacOS/QuotaBar --layout          # effective selection and widths
./QuotaBar.app/Contents/MacOS/QuotaBar --present-test    # present once, report dropped cells
./QuotaBar.app/Contents/MacOS/QuotaBar --present-test --measure   # measure this Mac's capacity
```

## 余额数据的来源 / Where balances come from

额度 provider（Claude / Codex / Kimi）由共享 `core/` 数据层直接读取本地客户端，Touch Bar 自己就能拿到。

**余额 provider（DeepSeek / SiliconFlow / OpenRouter）不同**：凭据在 macOS 钥匙串里，而 SiliconFlow 还要走
控制台会话（WebView 登录），这些只有菜单栏 app 能做——共享数据层里 `siliconflow` 是一个固定的
`login_required` 占位，真实值由 app 算出后覆盖。

所以菜单栏 app 每次刷新后会把自己那份**脱敏 payload 镜像**到
`~/.config/ai-agent-usage-widget/usage.json`（权限 0600），Touch Bar 会**优先读这份镜像**（15 分钟内视为
有效），过期或缺失时才回退到共享数据层。这样 Touch Bar 与设置页显示的 SiliconFlow 状态一致；若菜单栏 app
没在运行，余额 provider 会显示为未配置/取不到，额度 provider 不受影响。

排查：

```bash
./QuotaBar.app/Contents/MacOS/QuotaBar --once   # 首行会显示 source: app / core 以及各 provider 的状态
```

Quota providers (Claude / Codex / Kimi) are read from the local clients by the shared
`core/` layer, which the agent can run itself. **Balance providers are different**: their
credentials live in the macOS Keychain and SiliconFlow additionally needs a console
session (WebView login), so only the menu bar app can fetch them — the shared layer
reports `siliconflow` as a fixed `login_required` placeholder that the app replaces.

The app therefore mirrors its sanitized payload to
`~/.config/ai-agent-usage-widget/usage.json` (mode 0600) after every refresh, and the
agent prefers that mirror when it is under 15 minutes old, falling back to the shared
layer otherwise. That keeps the strip and the settings window showing the same state; with
the app closed, balance providers report as unconfigured while quota providers are
unaffected.

## 数据来源 / Data

不重复实现取数：运行共享的 `core/fetch_usage.py`（构建时拷入 `QuotaBar.app/Contents/Resources/core`），
解析其 JSON。Codex 全本地；Claude/Kimi 用各自 CLI 的本地凭据调官方接口、5 分钟缓存。
详见 [项目 README](../README.md) 与 [core](../core)。

QuotaBar does not reimplement provider fetching. It runs the shared
`core/fetch_usage.py`, bundled under `QuotaBar.app/Contents/Resources/core`,
and parses the same JSON as the menu bar app. See the [project README](../README.md)
and [core contract](../core/CONTRACT.md).

## 安装 / Install

Recommended installation is through `QuotaWidget.app` > Settings... > Touch Bar (installs to `/Applications/QuotaBar.app`). Manual `./install.sh` installs to `~/Applications/QuotaBar.app`; the control center treats both locations as installed. Manual installation remains available for development.

最简单的方式：从
[Releases](https://github.com/lazyfoxy33-dev/ai-agent-usage-widget/releases) 下载
`QuotaBar.dmg`（Developer ID 签名），拖入「应用程序」并打开；若对应 Release 说明
标注未公证，首次打开请在 Finder 中右键 → 打开（仍需 `python3`）。要开机自启，可改用下面的源码安装。

Easiest: download the Developer ID-signed `QuotaBar.dmg` from
[Releases](https://github.com/lazyfoxy33-dev/ai-agent-usage-widget/releases), drag
it to Applications, and open it (if the release note says it is not notarized,
right-click → Open on first launch; still needs `python3`). For launch-at-login,
build from source instead:

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
