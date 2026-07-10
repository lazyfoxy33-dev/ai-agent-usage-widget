# Balance Providers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add DeepSeek, SiliconFlow, and OpenRouter as balance-first providers with cached balance data and recent-spend estimates.

**Architecture:** Keep the shared Python data layer as the only fetch implementation. Add a reusable API-key HTTP helper, a reusable balance-history estimator, provider-specific parser/fetch modules, then update all frontends to render quota or balance cards by provider kind.

**Tech Stack:** Python standard library, `unittest`, JSON schema, Übersicht JSX, Windows Tauri HTML renderer, Swift model decoding.

---

## File Structure

- Create `core/usage/api_key_http.py`: shared Bearer HTTP helper with proxy support and provider-neutral error classes.
- Create `core/usage/balance_history.py`: JSONL history append, retention, and burn-rate estimation.
- Create `core/usage/deepseek.py`: DeepSeek balance parser and fetcher.
- Create `core/usage/siliconflow.py`: SiliconFlow user info parser and fetcher.
- Create `core/usage/openrouter.py`: OpenRouter credits/key parser and fetcher.
- Modify `core/fetch_usage.py`: import new providers, cache them, and include them in the payload.
- Modify `core/contract.schema.json` and `core/CONTRACT.md`: document balance-provider shape.
- Create tests under `core/tests/` for the new shared modules and providers.
- Modify `usage-widget/index.jsx`: add balance card rendering.
- Modify `windows-widget/src/render.mjs` and `windows-widget/src/render.test.mjs`: add balance card rendering/tests.
- Modify `macwidget/Shared/UsageContract.swift`: decode balance providers and add provider presentations.
- Modify `touchbar/Sources/DataSource.swift`: parse balance provider fields without breaking quota parsing.
- Modify README files with API key setup and privacy notes.

## Task 1: API-Key HTTP Helper

**Files:**
- Create: `core/usage/api_key_http.py`
- Test: `core/tests/test_api_key_http.py`

- [ ] Write tests for missing token validation, newline rejection, 401/403, 429, generic HTTP errors, JSON parsing, and proxy propagation.
- [ ] Implement `ApiAuthError`, `ApiRateLimitError`, `ApiHttpError`, `ApiResponseError`.
- [ ] Implement `bearer_get_json(url, token, timeout=25, extra_headers=None)` with `urllib.request`.
- [ ] Ensure tokens never enter argv; do not use shell commands.
- [ ] Run: `cd core && python3 -m unittest tests.test_api_key_http -v`.

## Task 2: Balance History And Burn Rate

**Files:**
- Create: `core/usage/balance_history.py`
- Test: `core/tests/test_balance_history.py`

- [ ] Write tests for appending samples, pruning samples older than 45 days, limiting to 500 samples, ignoring currency mismatches, insufficient history, balance increase, 24-hour fallback, and seven-day estimate.
- [ ] Implement JSONL read/write helpers using only compact non-secret records: `ts`, `amount`, `currency`.
- [ ] Implement `estimate(history, current_amount, currency, now)` returning `amount_per_day`, `window_days`, `estimated_days_left`, `confidence`, and optional `reason`.
- [ ] Implement `record_and_estimate(path, amount, currency, now=None)`.
- [ ] Run: `cd core && python3 -m unittest tests.test_balance_history -v`.

## Task 3: DeepSeek Provider

**Files:**
- Create: `core/usage/deepseek.py`
- Test: `core/tests/test_deepseek.py`
- Fixture: `core/tests/fixtures/deepseek_balance.json`

- [ ] Write parser tests for CNY/USD balance info, unavailable balance, numeric strings, and malformed payloads.
- [ ] Write fetch tests for missing `DEEPSEEK_API_KEY`, auth failure, rate limit, generic error, and successful history estimate.
- [ ] Implement `parse_deepseek_balance(payload, now=None)`.
- [ ] Implement `fetch_deepseek(now=None)` using `DEEPSEEK_API_KEY` and `api_key_http.bearer_get_json`.
- [ ] Add history path `~/.cache/usage-widget/deepseek-history.jsonl`.
- [ ] Run: `cd core && python3 -m unittest tests.test_deepseek -v`.

## Task 4: SiliconFlow Provider

**Files:**
- Create: `core/usage/siliconflow.py`
- Test: `core/tests/test_siliconflow.py`
- Fixture: `core/tests/fixtures/siliconflow_user_info.json`

- [ ] Write parser tests for `data.totalBalance`, `data.balance`, `data.chargeBalance`, status handling, numeric strings, and malformed payloads.
- [ ] Write fetch tests for missing `SILICONFLOW_API_KEY`, auth failure, rate limit, generic error, and successful history estimate.
- [ ] Implement `parse_siliconflow_info(payload, now=None)`.
- [ ] Implement `fetch_siliconflow(now=None)` using `SILICONFLOW_API_KEY` and `api_key_http.bearer_get_json`.
- [ ] Treat CNY as the default display currency unless the API returns a currency field.
- [ ] Add history path `~/.cache/usage-widget/siliconflow-history.jsonl`.
- [ ] Run: `cd core && python3 -m unittest tests.test_siliconflow -v`.

## Task 5: OpenRouter Provider

**Files:**
- Create: `core/usage/openrouter.py`
- Test: `core/tests/test_openrouter.py`
- Fixtures:
  - `core/tests/fixtures/openrouter_credits.json`
  - `core/tests/fixtures/openrouter_key.json`

- [ ] Write parser tests for credits balance: `total_credits - total_usage`.
- [ ] Write parser tests for key usage: limit, remaining, daily, weekly, monthly, free-tier flag.
- [ ] Write fetch tests for missing `OPENROUTER_API_KEY`, auth failure, rate limit, credits success, key endpoint fallback, and history fallback.
- [ ] Implement `parse_openrouter_credits(payload)`.
- [ ] Implement `parse_openrouter_key(payload)`.
- [ ] Implement `estimate_from_key_usage(key_data, balance_amount)` using daily/weekly/monthly usage when available.
- [ ] Implement `fetch_openrouter(now=None)` using `/api/v1/credits` and best-effort `/api/v1/key`.
- [ ] Add history path `~/.cache/usage-widget/openrouter-history.jsonl`.
- [ ] Run: `cd core && python3 -m unittest tests.test_openrouter -v`.

## Task 6: Shared Payload And Contract

**Files:**
- Modify: `core/fetch_usage.py`
- Modify: `core/contract.schema.json`
- Modify: `core/CONTRACT.md`
- Modify: `core/tests/test_fetch.py`
- Modify: `core/tests/test_contract.py`

- [ ] Add cache paths for `deepseek`, `siliconflow`, and `openrouter`.
- [ ] Add `deepseek_with_cache()`, `siliconflow_with_cache()`, and `openrouter_with_cache()` through the existing `_provider_with_cache()` helper.
- [ ] Include all three providers in `build_payload()`.
- [ ] Extend schema provider definition with optional `kind`, `balance`, and `burn_rate`.
- [ ] Update contract docs with quota-vs-balance examples and env var setup.
- [ ] Update tests so payload shape checks all six providers.
- [ ] Run: `cd core && python3 -m unittest tests.test_fetch tests.test_contract -v`.

## Task 7: Übersicht Balance Cards

**Files:**
- Modify: `usage-widget/index.jsx`

- [ ] Add provider metadata for DeepSeek, SiliconFlow, and OpenRouter.
- [ ] Split card rendering into quota and balance paths based on `data.kind === "balance"` or presence of `data.balance`.
- [ ] Render balance amount with currency-aware prefixes for CNY/USD and plain currency fallback.
- [ ] Render estimate copy when `burn_rate.estimated_days_left` exists.
- [ ] Render no-trend copy when `burn_rate.confidence === "none"` or no estimate exists.
- [ ] Keep existing quota card output unchanged for Claude/Codex/Kimi.

## Task 8: Windows Renderer And Tests

**Files:**
- Modify: `windows-widget/src/render.mjs`
- Modify: `windows-widget/src/render.test.mjs`

- [ ] Add provider metadata for DeepSeek, SiliconFlow, and OpenRouter.
- [ ] Add balance-card HTML rendering.
- [ ] Add tests for balance amount, estimate, no-trend, stale balance, and missing-key message.
- [ ] Run: `cd windows-widget && node --test src/render.test.mjs`.

## Task 9: Swift Contract Parsing

**Files:**
- Modify: `macwidget/Shared/UsageContract.swift`
- Modify: `macwidget/Tests/UsageContractTests.swift`
- Modify: `touchbar/Sources/DataSource.swift`

- [ ] Add `BalanceInfo` and `BurnRateInfo` Codable structs.
- [ ] Extend `UsageProvider` with `kind`, `balance`, and `burnRate`.
- [ ] Extend `UsagePayload` with `deepseek`, `siliconflow`, and `openrouter`.
- [ ] Extend provider enum/presentation strings.
- [ ] Update preview payloads to include balance providers.
- [ ] Update Touch Bar parser to read balance fields while preserving existing quota parsing.

## Task 10: Documentation And Privacy Review

**Files:**
- Modify: `README.md`
- Modify: `windows-widget/README.md`
- Optionally modify: `usage-widget/README.md`, `macwidget/README.md`, `touchbar/README.md`

- [ ] Document supported env vars without showing real tokens.
- [ ] Document that balance history stores only timestamp, amount, and currency.
- [ ] Document that tokens are never passed in argv.
- [ ] Update feature/provider descriptions from three providers to six providers.
- [ ] Run a diff privacy scan for local usernames, home paths, and personal email before commit.

## Task 11: Final Verification

- [ ] Run: `cd core && python3 -m unittest discover -s tests`.
- [ ] Run: `cd windows-widget && node --test src/render.test.mjs`.
- [ ] Run: `git status --short`.
- [ ] Inspect `git diff --stat`.
- [ ] Inspect sensitive-string scan with the repository pre-commit hook and a
  local grep for the current machine identity. Do not commit the literal
  machine username, home path, personal email, hostnames, account ids, or
  tokens.

```bash
git config core.hooksPath .githooks
git diff --check
git diff | grep -F "$HOME" || true
git diff | grep -F "$(id -un)" || true
```

Also inspect the diff manually for personal email addresses, provider token
prefixes, hostnames, account ids, and any credential-like values.

- [ ] Do not claim completion unless these commands have been run after the final code changes.
