# Balance Providers Design

## Goal

Add DeepSeek, SiliconFlow, and OpenRouter to the shared usage data layer as
balance-first providers. These providers should show current account credit and,
when there is enough trustworthy data, estimate how long the balance may last
based on recent spend.

## Current Context

The project currently has one shared Python data layer in `core/`. All frontends
consume the JSON emitted by `core/fetch_usage.py`.

Existing providers are quota-window providers:

- Claude: live remote OAuth usage with `five_h` and `weekly` quota windows.
- Codex: local or live quota snapshots with `five_h` and `weekly` quota windows.
- Kimi Code: live remote OAuth usage with `five_h` and `weekly` quota windows.

The new providers do not expose equivalent five-hour and weekly quota windows.
They expose account balance and, in OpenRouter's case, key/account usage fields.
The UI must not convert balance into fake percentage rings.

## Data Sources

### DeepSeek

- Endpoint: `GET https://api.deepseek.com/user/balance`
- Auth: `Authorization: Bearer <token>`
- Useful fields:
  - `is_available`
  - `balance_infos[].currency`
  - `balance_infos[].total_balance`
  - `balance_infos[].granted_balance`
  - `balance_infos[].topped_up_balance`

### SiliconFlow

- Endpoint: `GET https://api.siliconflow.com/v1/user/info`
- Auth: `Authorization: Bearer <token>`
- Useful fields:
  - `data.balance`
  - `data.chargeBalance`
  - `data.totalBalance`
  - `data.status`

### OpenRouter

- Endpoint: `GET https://openrouter.ai/api/v1/credits`
- Auth: `Authorization: Bearer <token>`
- Useful fields:
  - `data.total_credits`
  - `data.total_usage`
- Optional endpoint: `GET https://openrouter.ai/api/v1/key`
- Useful fields:
  - `data.limit`
  - `data.limit_remaining`
  - `data.usage`
  - `data.usage_daily`
  - `data.usage_weekly`
  - `data.usage_monthly`
  - `data.is_free_tier`

## Contract

Keep schema version `1` for backward compatibility, but extend provider payloads
with a `kind` discriminator. Existing quota providers may omit `kind` or use
`"quota"`. New providers use `"balance"`.

Balance provider success payload:

```json
{
  "ok": true,
  "kind": "balance",
  "fetched_at": 1781234567,
  "live": true,
  "balance": {
    "amount": 88.88,
    "currency": "USD",
    "available": true,
    "label": "Balance"
  },
  "burn_rate": {
    "amount_per_day": 3.2,
    "window_days": 7,
    "estimated_days_left": 27,
    "confidence": "medium"
  }
}
```

Balance provider failure payload:

```json
{
  "ok": false,
  "kind": "balance",
  "fetched_at": null,
  "live": false,
  "reason": "no_data"
}
```

Allowed `burn_rate.confidence` values:

- `none`: no useful estimate exists.
- `low`: estimate is based on fewer than three points or less than 24 hours.
- `medium`: estimate is based on at least three points over at least 24 hours.
- `high`: estimate is based on at least seven days of samples.

If the estimate is not useful, omit `estimated_days_left` and set
`confidence: "none"` with a `reason`, such as:

- `insufficient_history`
- `no_recent_spend`
- `balance_increased`

## Credentials

First implementation uses environment variables only:

- `DEEPSEEK_API_KEY`
- `SILICONFLOW_API_KEY`
- `OPENROUTER_API_KEY`

Tokens must never appear in process argv, logs, committed files, test fixtures,
or docs examples. HTTP helpers must pass secrets through request headers held in
process memory, not through shell-expanded command strings.

Future work can add Keychain, Windows Credential Manager, or config-file
support, but this design keeps the first implementation narrow and safe.

## Caching And History

Continue using the existing five-minute success cache policy from
`core/fetch_usage.py`. On transient failure, show the last successful stale cache
with `reason: "stale"` and `upstream_reason` populated.

Add a small local history store for balance estimates:

- `~/.cache/usage-widget/deepseek-history.jsonl`
- `~/.cache/usage-widget/siliconflow-history.jsonl`
- `~/.cache/usage-widget/openrouter-history.jsonl`

Each successful fetch appends one compact record:

```json
{"ts":1781234567,"amount":88.88,"currency":"USD"}
```

History retention:

- Keep at most 45 days.
- Keep at most 500 records per provider.
- Ignore records with a different currency from the current balance.

Trend calculation:

1. Use only records older than the current sample.
2. Prefer the newest point at least seven days old.
3. Fall back to the newest point at least 24 hours old.
4. Calculate spend as `old_amount - current_amount`.
5. If spend is less than or equal to zero, return `confidence: "none"` and
   `reason: "no_recent_spend"` or `reason: "balance_increased"`.
6. Calculate `amount_per_day = spend / elapsed_days`.
7. Calculate `estimated_days_left = current_amount / amount_per_day`.
8. Round display values in frontends, but keep machine values numeric.

For OpenRouter, prefer official `usage_daily`, `usage_weekly`, and
`usage_monthly` fields when `/api/v1/key` is available. Use local balance
history as fallback.

## Frontend Behavior

Frontends choose the card renderer based on provider kind:

- quota provider: current ring UI with `five_h` and `weekly`
- balance provider: balance card with currency, account status, and optional
  estimated days remaining

Balance card text examples:

- `¥110.00`
- `$24.58`
- `近 7 日约可用 34 天`
- `No spending trend yet`
- `Cached balance`

Provider order:

1. Claude
2. Codex
3. Kimi Code
4. DeepSeek
5. SiliconFlow
6. OpenRouter

If a balance provider has no API key, show a compact failure card. A missing key
must not hide other providers.

## Testing

Core tests should cover:

- API key missing returns `no_data`.
- Token is not exposed in argv.
- 401/403 maps to `expired`.
- 429 maps to `rate_limited`.
- DeepSeek balance parsing.
- SiliconFlow balance parsing.
- OpenRouter credits and key parsing.
- Local history appending, retention, currency filtering, and burn-rate
  estimation.
- `fetch_usage.build_payload()` includes all six providers with freshness
  fields.
- Stale cache fallback works for balance providers.

Frontend tests should cover:

- Existing quota card rendering still works.
- Balance card renders amount and currency.
- Balance card renders estimate when present.
- Balance card renders no-trend copy when estimate is absent.
- Missing-key and stale states render correctly.

## Acceptance Criteria

- Running `python3 -m unittest discover -s tests` from `core/` passes.
- Running `node --test src/render.test.mjs` from `windows-widget/` passes.
- `core/fetch_usage.py` returns valid JSON when no new API keys are configured.
- No token appears in command argv, test output, docs examples, or committed
  files.
- The old Claude/Codex/Kimi cards continue to render as quota cards.
- DeepSeek, SiliconFlow, and OpenRouter render as balance cards.
