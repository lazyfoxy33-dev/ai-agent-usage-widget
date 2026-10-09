# 数据契约 / Data Contract

`fetch_usage.py` 向所有前端输出同一份 JSON。当前契约版本为 `1`。

`fetch_usage.py` emits one shared JSON payload for every frontend. The current
contract version is `1`.

```json
{
  "schema_version": 1,
  "claude": {
    "ok": true,
    "fetched_at": 1781234567,
    "live": true,
    "five_h": {"pct": 12, "resets_at": 1781240000},
    "weekly": {"pct": 34, "resets_at": 1781800000}
  },
  "codex": {},
  "kimi": {},
  "deepseek": {
    "ok": true,
    "kind": "balance",
    "fetched_at": 1781234567,
    "live": true,
    "balance": {"amount": 110.0, "currency": "CNY", "available": true, "label": "Balance"},
    "burn_rate": {"amount_per_day": 3.2, "window_days": 7, "estimated_days_left": 34, "confidence": "medium"}
  },
  "siliconflow": {
    "ok": false,
    "kind": "balance",
    "source": "console_session",
    "fetched_at": null,
    "live": false,
    "reason": "login_required"
  },
  "openrouter": {
    "ok": true,
    "kind": "balance",
    "fetched_at": 1781234567,
    "live": true,
    "balance": {"amount": 75.42, "currency": "USD", "available": true, "label": "Balance"},
    "burn_rate": {"confidence": "none", "reason": "insufficient_history"}
  }
}
```

## Provider 类型 / Provider Kind

- `kind=quota`（或省略）：五小时与每周用量窗口，用于 Claude、Codex、Kimi。
- `kind=balance`：账户余额与可选的近期消耗估算，用于 DeepSeek、SiliconFlow、OpenRouter。

- `kind=quota` (or omitted): five-hour and weekly usage windows for Claude,
  Codex, and Kimi.
- `kind=balance`: account balance with an optional recent-spend estimate for
  DeepSeek, SiliconFlow, and OpenRouter.

## 数据来源 / Source

- `source=api_key`：使用 provider 的公开 API Key 接口。
- `source=console_session`：使用主 app 内保存的 provider 后台网页登录态。该值只出现在
  共享 payload 中；cookie 或 session token 不会写入共享 payload。

- `source=api_key`: data came from the provider's public API-key endpoint.
- `source=console_session`: data came from a provider console web session kept
  inside the main app. Only the sanitized payload contains this marker; cookies
  or session tokens are never written to the shared payload.


## 新鲜度 / Freshness

- `fetched_at`：该数据对应的 Unix 秒级时间；无数据时为 `null`。
- `live`：数据是否仍处于该 provider 的可信新鲜窗口。
- `reason=stale`：实时请求失败，当前数值来自过期缓存。
- `upstream_reason`：触发缓存回退的原始失败原因。

- `fetched_at`: Unix timestamp in seconds for the represented data, or `null`
  when no data is available.
- `live`: whether the data is still inside the provider's trusted freshness
  window.
- `reason=stale`: the live request failed and values came from an expired
  cache.
- `upstream_reason`: the original failure that caused the cache fallback.

Claude 和 Kimi 的实时响应及五分钟内缓存为 `live=true`。Codex 最近 session
事件在 30 分钟内为 `live=true`。过期缓存始终为 `live=false`。

Claude and Kimi live responses and caches younger than five minutes are
`live=true`. Codex is live when its latest session event is no older than 30
minutes. Expired cache fallbacks are always `live=false`.

## 失败原因 / Failure Reasons

- `expired`：凭据缺失、过期或被服务端拒绝。
- `rate_limited`：服务端返回 HTTP 429。
- `no_data`：没有可读取的本地或远端数据。
- `balance_unavailable`：服务端余额字段不适合展示，需要到 provider 后台核对。
- `error`：其他网络、解析或系统错误。
- `stale`：显示的是过期缓存。
- `balance_unavailable`：上游返回的余额口径不适合展示。
- `login_required`：后台网页登录态缺失或过期，需要用户重新登录。

- `expired`: credentials are missing, expired, or rejected.
- `rate_limited`: the provider returned HTTP 429.
- `no_data`: no local or remote usage data is available.
- `balance_unavailable`: provider balance fields are not suitable for display;
  verify the balance in the provider console.
- `error`: another network, parsing, or system error occurred.
- `stale`: displayed values came from an expired cache.
- `balance_unavailable`: the upstream balance semantics are unsafe to display.
- `login_required`: a provider console web session is missing or expired.

## 余额提供商配置 / Balance Provider Setup

余额提供商通过环境变量读取 API 密钥（不读取命令行参数）。SiliconFlow 只使用
macOS 主 app 的 Console Session Provider：

- `DEEPSEEK_API_KEY`
- `OPENROUTER_API_KEY`

SiliconFlow 由 macOS 主 app 启用 Console Session Provider。该模式
使用 app 自己的 WebKit 登录态读取 SiliconFlow 后台余额，并只把裁剪后的余额结果写入
共享 payload。Touch Bar 和其他展示层不得读取或接收网页登录态。

Balance providers read API keys from environment variables (never from command
line arguments). SiliconFlow only uses the macOS main app's Console Session
Provider:

- `DEEPSEEK_API_KEY`
- `OPENROUTER_API_KEY`

SiliconFlow uses the Console Session Provider in the macOS main app. That mode
uses the app-owned WebKit session to read the SiliconFlow console
balance and writes only the sanitized balance result into the shared payload.
The Touch Bar and other display layers must not read or receive web session
credentials.

机器可读定义见 `contract.schema.json`。

See `contract.schema.json` for the machine-readable definition.
