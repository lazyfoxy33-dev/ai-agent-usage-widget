# 组件 2：macOS WidgetKit 系统小组件 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development 或 executing-plans。
> 配套 spec：`docs/superpowers/specs/2026-06-12-native-frontends-mac-windows-design.md` §4。
> 独立于组件 1/3（数据层在 mac 已可用）。

**Goal:** 一个原生 macOS WidgetKit 小组件（通知中心 + 桌面），显示三家用量三环，数据由伴侣菜单栏 app 跑 `core/fetch_usage.py` 经 App Group 共享。

**Architecture:** 伴侣 app（带 App Group entitlement）定时跑 python 取数 → 写 App Group 容器 `usage.json` → `WidgetCenter.reloadTimelines` → Widget 扩展 TimelineProvider 读取 → SwiftUI 渲染。复用 `touchbar/Sources/DataSource.swift` 的取数器与契约解析。

**Tech Stack:** Swift / SwiftUI / WidgetKit；Xcode 项目；App Group。新目录 `macwidget/`。

> **先验门槛（开工第一步必须先过）**：在 Xcode 建 app + widget-extension 双 target，配同一 App Group `group.com.quotawidget.shared` 并能签名；跑通"app 写容器文件 → widget 读到"最小链路。**链路不通则先解决签名/entitlement，再继续。**

---

### Task 1：脚手架 + App Group 直通验证
- [ ] 建 `macwidget/` Xcode 工程：`QuotaWidgetApp`（菜单栏 app target）+ `QuotaWidgetExtension`（widget extension target），二者均加 App Group `group.com.quotawidget.shared`。
- [ ] 最小验证：app 启动写 `<AppGroupContainer>/usage.json = {"hello":1}`；widget 的 placeholder 读该文件并显示其内容。在 Xcode 预览 + 真机各确认一次。
- [ ] 提交：`feat(macwidget): scaffold app + widget extension sharing an App Group`
- **验收**：widget 能显示 app 写入的内容（证明 App Group 直通）。

### Task 2：契约解析（共享 Swift 文件）+ 单测
- [ ] 从 `touchbar/Sources/DataSource.swift` 抽出契约模型到共享文件 `macwidget/Shared/UsageContract.swift`：`struct Payload{schemaVersion; claude/codex/kimi: Provider}`、`struct Provider{ok; reason?; live?; fetchedAt?; asOf?; fiveH/weekly: Window?}`、`struct Window{pct; resetsAt; stale?}`（字段名/可选性对齐 §2 契约与 `DataSource.swift:19-`）。
- [ ] 加 Swift 单测 `macwidget/Tests/UsageContractTests.swift`：喂一段样本 JSON（含 stale/expired/缺字段三种），断言解析正确、失败项 `ok=false` 带 `reason`。
- [ ] 提交：`feat(macwidget): shared contract model + decode tests`
- **验收**：`swift test`（或 Xcode test）绿。

### Task 3：伴侣 app 取数器（复用 DataSource）
- [ ] 在 app target 复用 `DataSource.swift` 的取数逻辑：`Process` 跑 `/usr/bin/python3 <bundle>/Contents/Resources/core/fetch_usage.py`，`core/` 构建期拷入 bundle（仿 `touchbar/build.sh`：脚本把仓库 `core/` 复制到 `Contents/Resources/core`）。支持 `QUOTAWIDGET_FETCH` env 覆盖（dev）。
- [ ] 菜单栏 app：`Timer` 每 180s 取数 → 把**原始 JSON 字符串**原子写入 App Group `usage.json`（临时文件 + `FileManager.replaceItem`）→ `WidgetCenter.shared.reloadAllTimelines()`。菜单含"立即刷新""退出"。
- [ ] 取数失败（python 非 0/超时）→ 不覆盖旧 `usage.json`，仅记 app 内状态。
- [ ] 提交：`feat(macwidget): companion app fetches via core and publishes to App Group`
- **验收**：运行 app 后，App Group `usage.json` 出现真实三家 JSON（手动 `cat` 容器路径确认）。

### Task 4：TimelineProvider 读取
- [ ] Widget `TimelineProvider`：`getTimeline` 读 App Group `usage.json` → 用 `UsageContract` 解析 → 生成单条 entry，`policy: .after(Date()+25min)`（伴侣 app 的 `reloadAllTimelines` 才是主刷新驱动）。无文件 → 占位 entry（`needsSetup=true`）。
- [ ] `getSnapshot`/`placeholder` 用内置样本（避免预览空白）。
- [ ] 提交：`feat(macwidget): timeline provider reads shared usage.json`

### Task 5：SwiftUI 三环视图（移植设计语言）
- [ ] 实现 `RingView`：两条 `Circle().trim(from:0,to:pct/100).stroke(...,lineCap:.round)` 旋转 -90°，外环=周(浅)、内环=5h(深)，中心 5h% 大字 + "5H" 小字。品牌色对齐 `usage-widget/index.jsx`（Claude `#D97757`/`#E3A77F`；Codex 紫蓝渐变 `#A98CFF→#394DFF`，用 `AngularGradient`/`LinearGradient`；Kimi `#1478FF`）。
- [ ] `ProviderRow`：环 + 名称 + 5h/周 两行(圆点+标签+百分比+倒计时)。倒计时由 entry 的 `resets_at` 在渲染时算（`Text(_:style:.timer)` 或预算字符串）。
- [ ] 失败/stale：`live==false||reason=="stale"` → 环置灰 + "缓存数据"；`reason` 文案复用 `index.jsx providerMessage`（过期/未登录/受限）。
- [ ] 尺寸族：`systemSmall`=单家(可配/默认 Claude)；`systemMedium`=三家并排紧凑。`@main WidgetBundle` 暴露。
- [ ] 提交：`feat(macwidget): SwiftUI tri-ring views matching the design language`
- **验收（人工）**：Xcode Widget 预览 + 加到桌面，三家渲染对照 `usage-widget/mockup-c.html` 风格；过期/stale 态正确。

### Task 6：build.sh / install.sh / README + .gitignore
- [ ] `macwidget/build.sh`（archive/导出 .app，拷 `core/` 进 bundle）、`install.sh`（拷到 `/Applications` 或注册 LaunchAgent 让伴侣 app 开机启动）、`README.md`（中英，装/用/排错）。
- [ ] `.gitignore` 忽略构建产物与任何 `usage.json`（运行时产物，绝不入库）。
- [ ] 提交：`chore(macwidget): build/install scripts, readme, gitignore`

---

## Self-review
- **Spec §4 覆盖**：App Group 直通→T1；契约解析→T2；伴侣取数→T3；timeline→T4；三环视图/尺寸/失败态→T5；打包→T6。✅
- **复用**：DataSource.swift（T3）、index.jsx 视觉（T5）。✅
- **隐私**：`usage.json` 入 `.gitignore`（T6）；无本机信息入库。✅
- **风险**：App Group 签名是最大不确定项 → 设为 T1 先验门槛。
