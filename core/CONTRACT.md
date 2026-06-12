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
  "kimi": {}
}
```

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
- `error`：其他网络、解析或系统错误。
- `stale`：显示的是过期缓存。

- `expired`: credentials are missing, expired, or rejected.
- `rate_limited`: the provider returned HTTP 429.
- `no_data`: no local or remote usage data is available.
- `error`: another network, parsing, or system error occurred.
- `stale`: displayed values came from an expired cache.

机器可读定义见 `contract.schema.json`。

See `contract.schema.json` for the machine-readable definition.
