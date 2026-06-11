# Kimi Code Usage Panel Design / Kimi Code 用量面板设计

## Goal / 目标

Add Kimi Code usage to the Übersicht widget while preserving the existing
provider isolation, privacy guarantees, visual hierarchy, and automatic refresh
behavior. Also replace the clipped hand-drawn Codex glyph with the complete
Codex App cloud icon.

在保持现有提供商隔离、隐私保障、视觉层级和自动刷新行为的前提下，为 Übersicht
组件增加 Kimi Code 用量信息。同时用完整的 Codex App 云朵图标替换当前被裁切的
自绘图标。

## Data Source / 数据来源

The Kimi panel uses the same official endpoint as Kimi CLI's interactive
`/usage` command:

```text
GET https://api.kimi.com/coding/v1/usages
Authorization: Bearer <Kimi Code OAuth access token>
```

The widget reads the OAuth token from:

```text
${KIMI_SHARE_DIR:-$HOME/.kimi}/credentials/kimi-code.json
```

组件读取上述路径中的 OAuth 令牌。它是只读使用方：

- It does not read browser cookies.
- It does not scrape the Kimi web console.
- It does not refresh or rotate OAuth tokens.
- It does not write credentials into cache files.
- It does not put the access token in process arguments.

- 不读取浏览器 Cookie。
- 不抓取 Kimi 网页控制台。
- 不刷新或轮换 OAuth 令牌。
- 不把凭据写入缓存文件。
- 不把访问令牌放入进程参数。

If no usable local Kimi login exists, the panel instructs the user to sign in
with Kimi CLI. The Kimi console URL is documentation and manual-viewing
fallback only.

如果本机没有可用的 Kimi 登录状态，面板提示用户通过 Kimi CLI 登录。Kimi
控制台网址仅作为文档和手动查看入口。

## Parsing And Mapping / 解析与映射

The `/usages` response contains a weekly summary in `usage` and one or more
rate-limit entries in `limits`.

- Weekly usage comes from `usage`.
- Five-hour usage selects the limit whose window is 300 minutes.
- Usage percentage is calculated as `(limit - remaining) / limit * 100`, or
  from `used / limit * 100` when `used` is supplied.
- Percentages are clamped to `0..100` and rounded to whole numbers.
- Reset timestamps accept the Kimi response's supported timestamp forms and
  are normalized to Unix seconds.

Missing windows produce an explicit unavailable state instead of substituting
unrelated limits.

`usage` 映射为本周用量，`limits` 中 300 分钟窗口映射为五小时用量。使用率通过
`(limit - remaining) / limit` 或 `used / limit` 计算，限制在 `0..100` 并取整。
重置时间统一转换为 Unix 秒。缺少目标窗口时显示不可用，不用其他限额冒充。

## Fetching And Cache / 请求与缓存

The provider uses `curl` through Python's subprocess API, matching the existing
Claude integration's proxy behavior and token-safety pattern.

- The Authorization header is supplied through curl configuration on stdin.
- `HTTPS_PROXY` and `https_proxy` are honored.
- Successful Kimi data is cached for five minutes.
- A temporary fetch failure may return cached data marked stale.
- Authentication failures do not trigger token refresh and instruct the user
  to sign in with Kimi CLI.
- Kimi failures remain independent from Claude and Codex failures.

提供商通过 Python 子进程调用 `curl`，并沿用 Claude 集成的代理和令牌安全模式。
Authorization 头只通过标准输入传给 curl。成功数据缓存五分钟；临时请求失败时可
显示标记为旧数据的缓存。认证失败不刷新令牌，Kimi 失败也不影响其他面板。

## Interface / 界面

Kimi is a third stacked panel below Codex. It keeps the current panel geometry:

- Inner ring: five-hour usage
- Outer ring: weekly usage
- Rows: `5 小时` and `本周`
- Reset countdown below each row

The chosen visual direction is "A: official console":

- Kimi CLI's official black granular `K` logo
- White-to-light-gray panel background
- Kimi blue as the primary usage accent
- Near-black as the secondary accent
- Existing typography, spacing, and ring sizing

The panel stays within the widget's current 300-pixel width. Overall height
increases by one panel while retaining the bottom-right 40-pixel anchor.

Kimi 作为第三块面板放在 Codex 下方，继续使用内环表示五小时、外环表示本周。
采用已确认的 A 方案：官方黑色颗粒 `K` Logo、白灰背景、Kimi 蓝主色和近黑辅助
色。宽度保持 300 像素，整体仍固定在桌面右下角 40 像素处。

## Brand Assets / 品牌图片

The repository includes local copies of:

- The official Kimi CLI logo from `MoonshotAI/kimi-cli`
- The complete Codex App cloud icon extracted from the installed Codex App

The installer copies these assets into the installed widget directory. The
renderer references local relative asset paths, so no network request is
needed to draw either logo.

The Codex icon uses an image element with proportional sizing and inset space.
It replaces the hand-drawn SVG that currently exceeds its view box and clips
the cloud edge.

The README identifies product names and logos as trademarks of their respective
owners and states that the project is unofficial.

仓库内保存 Kimi CLI 官方 Logo 和 Codex App 完整云朵图标，由安装脚本复制到组件
目录。渲染只使用本地相对路径，不依赖网络。Codex 图片保持等比缩放并留出内边距。
README 会说明项目为非官方项目，相关名称和 Logo 归各自权利方所有。

## Error States / 错误状态

Kimi panel states:

- `no_data`: Kimi CLI is not installed or has not created credentials.
- `expired`: the local OAuth access token is expired or rejected.
- `error`: network or unexpected response failure.
- `stale`: cached data is shown after a temporary fetch failure.

Provider errors never hide the other two panels.

`no_data` 表示未安装或未登录 Kimi CLI，`expired` 表示令牌过期或被拒绝，
`error` 表示网络或响应异常，`stale` 表示显示请求失败前的缓存。任何单一提供商
错误都不会隐藏另外两个面板。

## Tests / 测试

Tests cover:

- Kimi credential path resolution, including `KIMI_SHARE_DIR`
- OAuth token parsing and expiry handling
- Five-hour and weekly response parsing
- Used/remaining percentage conversion and clamping
- Timestamp normalization
- Access token absence from process arguments
- Cache use and stale fallback
- Combined payload containing Claude, Codex, and Kimi independently
- Kimi brand colors and local logo rendering
- Codex local image rendering without the clipped hand-drawn path
- Installer copying both image assets
- Bottom-right widget positioning remaining unchanged

测试覆盖凭据路径与过期判断、用量解析、百分比与时间转换、令牌进程参数安全、缓存
降级、三提供商组合数据、Kimi 品牌渲染、Codex 完整图片、安装脚本以及右下角定位。

## Documentation / 文档

README changes explain:

- Kimi CLI installation/login prerequisite
- The official `/usages` data source
- Five-minute cache and one-minute widget refresh
- Manual console fallback link
- The no-cookie and no-token-refresh policy
- Troubleshooting for missing or expired Kimi credentials
- Third-party trademark and unofficial-project status

根 README、组件 README、贡献与安全文档、GitHub 模板以及本设计/实施文档均提供
中英双语。文档说明 Kimi CLI 登录、官方接口、缓存与刷新、控制台手动入口、无
Cookie/无令牌刷新策略、排错信息和第三方品牌归属。
