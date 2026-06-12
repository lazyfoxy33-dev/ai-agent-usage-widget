# 组件 3：Windows Tauri 桌面窗 — Implementation Plan

> 状态 / Status：前端、Rust 后端、托盘、自启和位置记忆已实现并在 macOS
> 主机编译测试；Windows 安装包与真实 CLI 登录态待真机验收。Implemented and
> host-tested; Windows packaging and real CLI sessions require a Windows host.

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development 或 executing-plans。
> 配套 spec：`docs/superpowers/specs/2026-06-12-native-frontends-mac-windows-design.md` §5。
> **依赖：组件 1（数据层移植）必须先完成**（Windows 才能读 Claude 凭证）。

**Goal:** 一个 Tauri 无边框、透明、置顶、钉桌面的 Windows 小窗，复用现有 HTML/SVG 设计显示三家用量；Rust 后端定时跑 `python core/fetch_usage.py` 取数。

**Architecture:** Tauri app；前端 = 把 `usage-widget/index.jsx` 视觉移植成纯 HTML/CSS/JS（`render(payload)` 吃契约 JSON）；Rust 后端 `Command` 跑 python 取数，经 event 推给 webview。`core/` 作为 resource 随 app 分发。新目录 `windows-widget/`。

**Tech Stack:** Tauri (Rust + system webview)；纯 HTML/CSS/JS（无框架）；目标机需 python3。

> **先验门槛（开工第一步）**：在 Windows 上 `npm create tauri-app` 起最小窗 → Rust `Command` 跑 `python --version` 把输出送到 webview 显示出来。**这条链路（Tauri 起窗 + 调 python + IPC）不通则先解决，再继续。**

---

### Task 1：脚手架 + python 直通验证（Windows）
- [ ] `windows-widget/` 起 Tauri 工程；窗口配置 `decorations:false, transparent:true, alwaysOnTop:true, skipTaskbar:true, resizable:false`，尺寸约 320×二段高。
- [ ] Rust `#[tauri::command] fn probe_python()`：`std::process::Command` 试 `python`/`python3`/`py -3 --version`，返回首个成功的解释器与版本；webview 启动时调用并显示。
- [ ] 提交：`feat(win): scaffold tauri widget + python probe`
- **验收**：Windows 上窗口出现、显示探测到的 python 版本。

### Task 2：取数封装（Rust）+ 单测
- [ ] Rust `fetch_usage(py: &str, core_dir: &Path) -> Result<String>`：跑 `<py> <core_dir>/fetch_usage.py`，30s 超时，返回 stdout（原始 JSON 字符串）；非 0/超时 → `Err`。代理：若目标网络需要，透传 `HTTPS_PROXY` env（沿用 `core` 的 `_proxy()` 自动探测，无需在此设）。
- [ ] 单测（Rust，mock command）：把 `fetch_usage` 的"组命令 + 解析退出码"逻辑抽成可测函数 `parse_fetch_output(stdout, status) -> Result<String>`，断言：status 成功+合法 JSON→Ok；非 0→Err；空输出→Err。`cargo test`。
- [ ] `core/` 定位：dev 用 `../core`，打包用 Tauri `resource_dir()/core`。
- [ ] 提交：`feat(win): rust core-fetch wrapper with tests`

### Task 3：前端渲染（移植 index.jsx 设计）
- [ ] `windows-widget/src/render.js`：`render(payload)` 纯函数 → 注入 DOM。把 `usage-widget/index.jsx` 的视觉移植为原生：
  - 三环 SVG（外环周/内环 5h，中心 5h% 大字）、品牌色（Claude `#D97757`；Codex 紫蓝渐变 `#A98CFF→#394DFF`；Kimi `#1478FF`）、倒计时（JS 每 60s 依 `resets_at` 重算）。
  - 失败/stale 态：`live===false||reason==='stale'` 置灰 + "缓存数据"；`reason` 文案对齐 `index.jsx providerMessage`（过期/未登录/受限/暂无数据）。
- [ ] **DOM 测试**（jsdom 或 Vitest）：喂 3 段样本契约 JSON（全 live / 一家 stale / 一家 expired），断言渲染出正确的百分比文本、置灰类、文案。`npm test`。
- [ ] 提交：`feat(win): port tri-ring UI to plain HTML/JS with render tests`

### Task 4：接线（定时取数 → 渲染）
- [ ] Rust：启动后定时（默认 60s）`fetch_usage` → `app.emit("usage", json)`；前端 `listen("usage", e => render(JSON.parse(e.payload)))`。首帧立即取一次。
- [ ] python 缺失/取数失败 → emit 一个 `{error:"no_python"}`/`{error:"fetch_failed"}`，前端显示"未检测到 python，请安装并重启"/保留上次渲染 + 角标。
- [ ] 窗口可拖动（`data-tauri-drag-region`）、记忆位置（tauri store 或 window state 插件）。
- [ ] 提交：`feat(win): wire periodic fetch to render with error states`

### Task 5：托盘 + 自启 + 打包
- [ ] 系统托盘：显示/隐藏窗口、立即刷新、退出。
- [ ] 开机自启：tauri autostart 插件（默认开，托盘可关）。
- [ ] `tauri.conf.json` 把仓库 `core/` 列为 bundle resource；`npm run tauri build` 产出 `.msi`/`.exe`。
- [ ] `README.md`（中英）：装/用/排错（需 python3、代理说明）；`.gitignore` 忽略 `target/`、`dist/`、任何运行时 JSON。
- [ ] 提交：`feat(win): tray, autostart, packaging, readme`
- **验收（人工，Windows）**：装好后桌面出现小窗、三家真实数据、置顶钉桌面、拖动/记忆位置、重启自启。

---

## Self-review
- **Spec §5 覆盖**：脚手架/窗口属性→T1；Rust 取数→T2；UI 移植→T3；接线/错误态→T4；托盘/自启/打包→T5。✅
- **依赖**：组件 1（数据层 Windows 可用）已在文首声明为前置。✅
- **复用**：index.jsx 视觉（T3）。**隐私**：运行时 JSON 入 `.gitignore`（T5）。✅
- **风险**：Tauri+python IPC 直通设为 T1 先验门槛；目标机 python 依赖在 README 明示，不自带安装器（本轮 out of scope）。
