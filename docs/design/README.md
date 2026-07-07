# Usage Widget — Design System

AI Agent 用量小组件的设计规范,用于 Touch Bar、桌面 Widget、Übersicht 三端。
每个 `.html` 是自包含预览卡片,首行带 `<!-- @dsCard group="…" name="…" -->` 注释供索引。

## 核心决策
- **调和品牌底色**:品牌色收敛为强调色(环/条填充、圆点),底色统一明/暗材质 + 极淡品牌色调。
- **条形为主、同心环为备**:条对「有多满」最直观且可缩到 Touch Bar。
- **两类 provider 同屏**:订阅额度 provider 显示窗口用量;按量计费 provider 显示账户余额、可用性趋势与密钥状态。
- **语义告急色**:按已用 % 取色 — `<70` 品牌 / `70–90` 注意 / `≥90` 告急,覆盖品牌色。
- **百分比 = 已用量**;倒计时只显示 5H/Wk 中**更早重置**者。
- **两字母状态码**:`5H` · `Wk` 用于额度窗口,`Cr` 用于按量余额;同列对齐。
- **跟随系统亮/暗**。

```
foundations/
  colors.html          品牌 / 语义 / 表面 / 中性 (亮+暗)
  typography.html      SF Pro Text 类型表 + 额度码
components/
  _widget.css          组件样式(唯一来源)
  _widget.js           tokens + 样例数据 + 渲染器(window.UW),自动挂载
  widget-full.html     六家全卡 · 条形/余额 · 亮+暗
  panels.html          单家面板 · 订阅额度 + 按量余额 · 亮+暗
  meter.html           条形 / 同心环 / 语义色
  compact.html         紧凑横排 + Touch Bar
  states.html          需登录 / 缓存等待刷新 (仅两态·正常无提示·中英双语)
assets/                provider 图标 PNG
```

## 用法
卡片只放数据与挂载点,样式与逻辑统一引用 `_widget.css` + `_widget.js`:
```html
<div class="widget" data-form="bar" data-theme="dark"></div>
<div class="widget compact" data-form="compact" data-theme="light"></div>
<div class="touchbar" data-auto></div>
```
`data-form`: `bar`(主) · `ring`(备) · `compact`。`data-providers`: 省略=三家订阅 · `balance`=三家按量计费 · `all`=六家 · `credit`/`all+credit`=旧充值样例兼容。
也可直接调用 `UW.barPanel(provider, theme)` 等渲染单块。

按量计费 provider:主数字用余额(接口硬数据),趋势行显示按近期消耗估算的可用天数;无 API 密钥时显示配置状态,不伪造余额。

## 状态与语言
订阅额度 provider 只有两种需提示状态:**需登录**与**缓存等待刷新**。按量计费 provider 增加**未配置 API 密钥**;缓存态仍保留真实余额但降透明。正常态**无任何提示**。文案默认中文,英文系统(`navigator.language`)自动切英文;可用 `window.UW_LOCALE = 'en'|'zh'` 手动覆盖。词典集中在 `_widget.js` 的 `I18N`。
