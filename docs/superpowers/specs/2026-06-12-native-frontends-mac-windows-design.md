# 原生前端：macOS WidgetKit + Windows Tauri — 设计文档

> 日期：2026-06-12 · 层：①数据层移植 + ③新前端 · 状态：待实现（交由 Codex，分 3 份计划）
> 上位框架：三层骨架（数据/设计/组件）。本文件设计两个**新前端**及其所需的**数据层跨平台移植**。

## 1. 目标 / Goal

在现有两个前端（Übersicht 桌面组件、Touch Bar）之外，新增两个原生前端，复用同一数据契约与视觉语言：

- **macOS 原生 WidgetKit 系统小组件**（通知中心 + Sonoma 桌面，无需 Übersicht）。
- **Windows 桌面组件**（Tauri 无边框置顶窗，钉在桌面）。

并把**数据层移植为跨平台**，使其在 Windows 上可运行（Windows 是新前端的前置）。

## 2. 不变量 / Invariants

- **唯一数据源**：`core/fetch_usage.py` 输出的 JSON 契约（`schema_version:1`）。两个新前端都只消费它，**绝不重新实现 provider 逻辑**。契约形状：
  ```json
  {"schema_version":1,
   "claude":{"ok":true,"live":true,"fetched_at":1781241944,
             "five_h":{"pct":85,"resets_at":1781246400},"weekly":{"pct":29,"resets_at":1781758800}},
   "codex":{"ok":true,"as_of":1781241965,"live":true,"fetched_at":1781241965,
            "five_h":{"pct":88,"resets_at":1781243886,"stale":false},"weekly":{"pct":37,"resets_at":...,"stale":false}},
   "kimi":{"ok":true,"live":true,"fetched_at":...,"five_h":{...},"weekly":{...}}}
  ```
  失败项：`{"ok":false,"reason":"expired|error|no_data|stale|rate_limited"}`。
- **视觉语言复用**：三环 + 倒计时 + 品牌色（见 `usage-widget/index.jsx`：Claude 陶土、Codex 紫蓝渐变、Kimi 蓝）。不新增设计语言。
- **隐私/安全**：见 `AGENTS.md`（noreply 身份、无本机信息、token 不进 argv）。新前端不得把 JSON/凭证落入仓库或日志。

---

## 3. 组件 1 · 数据层跨平台移植（`core/`）

**问题**：`core/usage/claude.py` 仅支持 macOS——靠 `security find-generic-password` 读 Keychain。Windows/Linux 上 Claude Code 把凭证存为**文件** `~/.claude/.credentials.json`（结构同 `{"claudeAiOauth":{accessToken,refreshToken,expiresAt,...}}`，权限随用户目录）。Codex/Kimi 本就是文件凭证，`os.path.expanduser` 跨平台可用。

**设计**：抽象 Claude 的**凭证存取**为平台感知的读+写，其余不变。

- 新增 `core/usage/credential_store.py`：
  - `read_claude_blob() -> str|None`：`sys.platform == "darwin"` → `security ... -w`；否则读 `os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR","~/.claude")+"/.credentials.json")`。
  - `write_claude_blob(blob: str)`：macOS → `security add-generic-password -U -a <whoami> -s "Claude Code-credentials" -w`；否则**原子写**该文件（临时文件 + `os.replace`，`chmod 0600`，保留其余字段）。
- `claude.py` 改为调用 `credential_store`，删除内联的 keychain-only 逻辑；续期写回（refresh+persist）走同一抽象。
- `_proxy()` 已是 env + 本地端口探测，跨平台可用；确认 Windows 下 `socket.create_connection` 与 curl(`curl.exe`，Win10+ 自带)正常。`subprocess` 调 curl 时不要写死 `/usr/bin/python3` 等 POSIX 路径。
- Codex/Kimi：路径用 `expanduser` 已 OK；`codex`/`kimi` 可执行定位用 `shutil.which`（Windows 找 `codex.exe`），**在 Windows 实测一次**确认 session/凭证目录结构一致。

**测试**（`core/tests/`，mock 平台 + IO，不碰真 keychain/文件/网络）：
- `read_claude_blob`：monkeypatch `sys.platform="darwin"` → 走 security（mock subprocess）；`="win32"` → 读临时文件。
- `write_claude_blob`：win32 分支写临时文件后原子替换、权限 0600、保留未知字段；darwin 分支调 security（mock）。
- 既有 `test_claude.py` 全绿（重构不改外部行为）。

---

## 4. 组件 2 · macOS WidgetKit 系统小组件（`macwidget/`）

**约束**：WidgetKit 扩展在沙箱中运行，**不能 spawn python**。故需"伴侣 app 取数 + App Group 共享 + 组件读取"。

**架构**：
- **伴侣菜单栏 app**（SwiftUI/AppKit，带 **App Group** entitlement `group.<bundleid>`）：
  - 复用 `touchbar/Sources/DataSource.swift` 的取数器（`Process` 跑 `/usr/bin/python3 <bundle>/Contents/Resources/core/fetch_usage.py`，解析为 Swift 结构）。`core/` 构建时拷入 bundle（同 QuotaBar `build.sh`）。
  - 定时（如每 2–5 分钟）取数，把**原始 JSON 字符串**写入 App Group 容器文件 `Library/Application Support/usage.json`。
  - 写入后 `WidgetCenter.shared.reloadTimelines(...)` 触发组件刷新。
- **WidgetKit 扩展**（`QuotaWidget`）：
  - `TimelineProvider` 从 App Group 容器读 `usage.json`，解析同一契约 → 生成 entry。
  - SwiftUI 视图把三环 + 倒计时 + 品牌色按 `index.jsx` 的视觉**移植到 SwiftUI**（环=两条 `Circle().trim`，外环周/内环 5h，中心大字 5h%；过期/stale 置灰 + 文案同现有前端）。
  - 支持 `systemSmall`/`systemMedium`（small=单家或紧凑三家、medium=三家并排，按尺寸）。
  - timeline 刷新策略：`.after(15–30 min)`；真正的新鲜度由伴侣 app 的写入驱动（reloadTimelines）。
- **数据流**：伴侣 app（python 取数）→ App Group `usage.json` → 组件 TimelineProvider 读 → SwiftUI 渲染。
- **工程**：Xcode 项目（app target + widget extension target，共用 App Group + 一个解析契约的 Swift 文件 `UsageContract.swift`，可由 `DataSource.swift` 抽出共享）。`build.sh` + `install.sh` 仿 `touchbar/`。

**容错**：App Group 无 `usage.json`（伴侣 app 没跑）→ 组件显示"打开 QuotaWidget app"占位；provider 失败项按 `reason` 显示（复用现有文案）。

**测试**：契约解析的 Swift 单测（喂样本 JSON 断言结构）；视图用 WidgetKit 预览/快照人工核对（对照 `usage-widget/mockup-c.html` 风格）。

---

## 5. 组件 3 · Windows Tauri 桌面窗（`windows-widget/`）

**架构**：
- **Tauri app**：无边框、透明背景、置顶、`skipTaskbar`、可拖动、记忆位置；系统托盘（显示/隐藏/退出/刷新）；开机自启（Tauri autostart 插件）。
- **Web UI**：把 `usage-widget/index.jsx` 的视觉**移植为纯 HTML/CSS/JS**（无需 React；三环 SVG、倒计时、品牌色、stale/expired 文案与 mac 版一致）。一个 `render(payload)` 函数吃契约 JSON。
- **取数**：Rust 后端用 `std::process::Command` 定时（默认 60s）跑 `python core/fetch_usage.py`（python 路径可配，默认 `python`/`python3`/`py -3` 探测），把 stdout JSON 经 Tauri event/`invoke` 发给 webview。`core/` 随 app 一起分发（resource 目录）。
- **依赖**：组件 1（数据层 Windows 可用）+ 目标机有 python3（README 说明；不自带安装器）+ 本地代理（沿用 `_proxy()` 自动探测；可在配置里覆盖）。
- **倒计时**：webview 内 JS 每 60s 依 `resets_at` 本地重算（同现有前端）。

**容错**：python 缺失/退出非 0 → UI 显示"未检测到 python，请安装并重启"；provider 失败按 `reason` 渲染；取数异常保留上次渲染 + 角标。

**测试**：UI 的 `render()` 喂样本契约 JSON 的 DOM/快照测试（Node 或浏览器）；Rust 取数封装的单测（mock command 输出）。**不**在 CI 跑真 python/网络。

---

## 6. 构建顺序与依赖 / Build Order

1. **组件 1（数据层移植）** — 前置，且让现有前端在 Linux 也更稳。
2. **组件 3（Windows Tauri）** — 依赖组件 1。
3. **组件 2（macOS WidgetKit）** — 独立于以上，随时可做（数据层在 mac 已可用）。

每个组件一份独立实现计划（writing-plans），交 Codex 分头实现。

## 7. 不做 / Out of Scope

- 不新增视觉设计语言（复用三环）。
- 不新增 provider。
- 不自带/捆绑 python 运行时安装器（文档要求用户已装；后续可选增强）。
- 不做 Windows 11 原生 Widgets Board（Adaptive Cards 无法还原自定义环，且只能在弹出板）。
- Linux 前端本轮不做（但组件 1 的移植让 `core/` 在 Linux 也能跑，为以后留口）。

## 8. 开工前必须先验证 / Verify First

1. **Windows 上三家凭证的真实结构**：`%USERPROFILE%\.claude\.credentials.json` 是否同 `{"claudeAiOauth":{...}}`；`~/.codex`、`~/.kimi-code` 在 Windows 的目录与文件是否一致。（需一台 Windows 机或用户协助）
2. **App Group entitlement**：伴侣 app 与 widget extension 必须同一 App Group 且正确签名，写入/读取容器路径一致。
3. **Tauri 跑 python + 分发 `core/`**：确认 resource 打包路径与运行时定位。
4. Windows `curl.exe` 与本地代理探测在目标网络下可达 Anthropic/Kimi（必要时配置代理）。

## 9. 安全 / Security

- 沿用 `AGENTS.md`：noreply 身份、无本机信息入库、token 走 curl `--config` stdin。
- App Group `usage.json` 与 Tauri 取数结果都是**运行时产物**，必须在各自 `.gitignore` 忽略，绝不入库。
- Windows 写回 `.credentials.json` 用原子替换 + `0600`（或 Windows ACL 等价：仅当前用户可读写）。
