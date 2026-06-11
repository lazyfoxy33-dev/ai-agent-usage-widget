# Claude Refresh And Codex Corners Design / Claude 刷新与 Codex 圆角设计

## Goal / 目标

Document Claude's effective refresh behavior and make the Codex App icon match
Apple's rounded app-icon presentation.

说明 Claude 的实际刷新机制，并让 Codex App 图标使用符合 Apple App 图标观感的
连续圆角。

## Current Behavior / 当前行为

Übersicht runs `fetch_usage.py` every 60 seconds. Claude successful responses
are cached for 300 seconds, so four out of five executions normally return the
same cached value without contacting Anthropic. When the request fails, the
last successful response is returned with `reason: "stale"`.

Übersicht 每 60 秒运行一次 `fetch_usage.py`。Claude 成功响应会缓存 300 秒，
因此通常五次执行中有四次只读取相同缓存，不会请求 Anthropic。请求失败时，
组件会返回最后一次成功响应，并标记 `reason: "stale"`。

The Codex image currently has no clipping or corner radius. Its PNG contains a
square canvas, which appears as a sharp rectangular frame against the dark
panel.

Codex 图片目前没有裁切或圆角。PNG 自带方形画布，在深色面板上会显示成突兀的
直角框。

## Design / 设计

- Keep Übersicht's 60-second `refreshFrequency`.
- Keep the five-minute success cache. A live diagnostic found the Anthropic
  usage endpoint returning HTTP 429 even though the local token was valid;
  increasing request frequency would make rate limiting worse.
- Preserve stale-cache fallback when Claude's API request fails or is
  rate-limited.
- Render Codex inside a 27×27 image with `borderRadius: 8`,
  `overflow: "hidden"`, and `WebkitMaskImage:
  "-webkit-radial-gradient(white, black)"`. The mask forces reliable clipping
  in Übersicht's WebKit view and produces an Apple-style continuous corner.
- Update Chinese and English documentation to state the effective refresh
  behavior precisely.

- 保留 Übersicht 的 60 秒 `refreshFrequency`。
- 保留五分钟成功缓存。实际诊断发现本地令牌有效时 Anthropic 用量接口仍返回
  HTTP 429；提高请求频率会加重限流。
- Claude API 请求失败或被限流时继续回退到旧缓存。
- Codex 保持 27×27 图片，增加 `borderRadius: 8`、
  `overflow: "hidden"` 与 `WebkitMaskImage:
  "-webkit-radial-gradient(white, black)"`。遮罩确保 Übersicht 的 WebKit
  视图可靠裁切，呈现 Apple 风格连续圆角。
- 同步更新中英文文档，准确说明实际刷新机制。

## Verification / 验证

- Unit tests assert provider success responses retain the 300-second TTL.
- Source tests assert the Codex image has the continuous-corner styles.
- The full test suite passes.
- The installed widget matches the repository and is inspected in Übersicht.

- 单元测试约束成功响应继续使用 300 秒 TTL。
- 源码测试约束 Codex 图片具备连续圆角样式。
- 完整测试套件通过。
- 安装后的组件与仓库一致，并在 Übersicht 中实际检查。
