# Usage Widget — Design System

AI Agent 用量小组件的设计规范,用于 Touch Bar、桌面 Widget、Übersicht 三端。
每个 `.html` 是自包含预览卡片,首行带 `<!-- @dsCard group="…" name="…" -->` 注释供索引。

## 核心决策
- **调和品牌底色**:品牌色收敛为强调色(环/条填充、圆点),底色统一明/暗材质 + 极淡品牌色调。
- **条形为主、同心环为备**:条对「有多满」最直观且可缩到 Touch Bar。
- **语义告急色**:按已用 % 取色 — `<70` 品牌 / `70–90` 注意 / `≥90` 告急,覆盖品牌色。
- **百分比 = 已用量**;倒计时只显示 5H/Wk 中**更早重置**者。
- **两字母额度码**:`5H` · `Wk` · `Cr`(充值余额),同列对齐。
- **跟随系统亮/暗**。

```
foundations/
  colors.html          品牌 / 语义 / 表面 / 中性 (亮+暗)
  typography.html      SF Pro Text 类型表 + 额度码
components/
  _widget.css          组件样式(唯一来源)
  _widget.js           tokens + 样例数据 + 渲染器(window.UW),自动挂载
  widget-full.html     三家全卡 · 条形 · 亮+暗
  panels.html          单家面板 · 含充值型 · 亮+暗
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
`data-form`: `bar`(主) · `ring`(备) · `compact`。`data-providers`: 省略=三家订阅 · `credit`=Claude+充值 · `all+credit`=全部。
也可直接调用 `UW.barPanel(provider, theme)` 等渲染单块。

充值消耗型 provider:主数字用余额(接口硬数据),续航(`~9d est.`)为按消耗速率的估算、可省。

## 状态与语言
只有两种需提示的状态:**需登录**与**缓存等待刷新**(数据变淡加说明);正常态**无任何提示**。文案默认中文,英文系统(`navigator.language`)自动切英文;可用 `window.UW_LOCALE = 'en'|'zh'` 手动覆盖。词典集中在 `_widget.js` 的 `I18N`。
