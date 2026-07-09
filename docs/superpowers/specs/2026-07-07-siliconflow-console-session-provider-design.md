# SiliconFlow Console Session Provider Design

> Date: 2026-07-07
> Scope: optional SiliconFlow balance source for the macOS control app and shared display payload

## Context

SiliconFlow currently exposes two different balance surfaces:

- The public API-key endpoint, `https://api.siliconflow.cn/v1/user/info`, is documented in the OpenAPI file and returns `balance`, `chargeBalance`, and `totalBalance`.
- The web console balance card uses an authenticated wallet service endpoint under `walletd.siliconflow.cn`, reached by the console frontend as `wallet("/api/v1/subject/profile/peek")`.

The API-key endpoint can return a negative `totalBalance` while the console shows a positive recharge balance. The wallet endpoint rejects the same API key as an invalid token. Therefore the console balance is not safely available through the current API-key provider.

The existing API-key provider should keep treating negative SiliconFlow balances as unavailable instead of displaying misleading values.

## Goal

Add a separate, opt-in SiliconFlow Console Session Provider that can read the same balance shown in the SiliconFlow web console while keeping web session credentials isolated from widgets, scripts, and display layers.

This provider is not a replacement for the API-key provider. It is a second source with a stronger credential boundary and a clear user-controlled setup flow.

## Non-Goals

- Do not read Chrome, Safari, or any other browser's cookies.
- Do not scrape arbitrary SiliconFlow HTML pages.
- Do not store cookies, bearer tokens, or web session material in the shared usage JSON.
- Do not let WidgetKit, Uebersicht, menu bar display views, or Python providers access web session credentials.
- Do not silently enable this provider when only an API key is configured.

## Proposed Architecture

### Components

1. `SiliconFlowAPIKeyProvider`
   - Existing provider.
   - Uses `SILICONFLOW_API_KEY`.
   - Calls the public `/v1/user/info` endpoint.
   - Returns `balance_unavailable` when the upstream balance is negative or otherwise unsafe to display.

2. `SiliconFlowConsoleSessionProvider`
   - New optional provider owned by the macOS control app.
   - Uses an app-owned WebKit session or other app-owned login container.
   - Requests only the allowlisted wallet profile endpoint.
   - Converts the response into a minimal balance snapshot.

3. `SiliconFlowSessionStore`
   - Stores session material only in the app sandbox or Keychain.
   - Does not write session material to App Group storage.
   - Exposes only session status to the UI: not configured, login required, active, expired, or error.

4. Shared usage payload
   - Stores only sanitized provider output:

```json
{
  "siliconflow": {
    "ok": true,
    "kind": "balance",
    "source": "console_session",
    "live": true,
    "fetched_at": 1783420000,
    "balance": {
      "amount": 0,
      "currency": "CNY",
      "available": true,
      "label": "Console Balance"
    }
  }
}
```

The example amount is intentionally neutral. Documentation and tests must avoid real personal usage numbers.

## Data Flow

1. User opens QuotaWidget settings.
2. User explicitly enables "SiliconFlow Console Balance".
3. The app opens an embedded login view for SiliconFlow.
4. After login, the app stores the session and the console subject id in its
   private credential boundary.
5. On refresh, the app calls only:

```text
https://walletd.siliconflow.cn/api/v1/subject/profile/peek
```

6. The app passes the subject id as the wallet profile `SubjectId` parameter and
   extracts the finance balance fields needed for display.
7. The app writes a sanitized balance result into the shared usage payload.
8. WidgetKit, Uebersicht, and future display layers read only the shared payload.

## Security Model

### Credential Isolation

- API keys remain in the existing API-key Keychain entries.
- Web session credentials use a separate service/account namespace.
- Session cookies or tokens never enter environment variables, command-line arguments, logs, Python subprocesses, or shared JSON.
- Display layers never receive web credentials.

### Network Allowlist

The console session provider may request only:

- Host: `walletd.siliconflow.cn`
- Path: `/api/v1/subject/profile/peek`
- Method: `GET`

All redirects should be rejected unless they remain within the known SiliconFlow login or wallet domains required by the embedded login flow. Refresh calls must not follow arbitrary cross-site redirects.

### User Consent

The settings UI must explain that this provider uses a SiliconFlow web console session, not the API key. Enabling it is a separate user action.

Recommended states:

- `API Key only`
- `Console balance not enabled`
- `Login required`
- `Console balance active`
- `Console balance expired`
- `Console balance unavailable`

### Failure Behavior

- If the console session is missing or expired, return `login_required`.
- If the wallet response shape changes, return `balance_unavailable`.
- If the request is blocked or rate-limited, return `error` or `rate_limited`.
- Never fall back from a failed console-session fetch to a stale or negative API-key balance without marking the source and status clearly.

## Provider Selection

If both SiliconFlow sources are configured:

1. Prefer a fresh console-session balance.
2. If the console session requires login, show that state.
3. If only the API-key provider is configured, use the API-key provider.
4. If the API-key provider returns a negative balance, display `balance_unavailable`.

The shared payload should include `source` so every display can label and debug the value without guessing.

## UI Implications

In the settings app, SiliconFlow should show two separate configuration rows or a segmented source section:

- `API Key`
  - Existing key entry.
  - Good for API status and public `/v1/user/info`.

- `Console Balance`
  - Connect / Reconnect / Disconnect buttons.
  - Status text for login freshness.
  - Clear copy: "Uses SiliconFlow web console session to read billing balance."

Display layers should not expose setup controls. They only show the current sanitized state.

## Testing

Core tests:

- API-key provider maps negative SiliconFlow balances to `balance_unavailable`.
- Cache fallback does not display stale negative SiliconFlow balances.
- Contract schema accepts `source: "api_key"` and `source: "console_session"` if the field is added.

macOS app tests:

- Session provider refuses non-allowlisted hosts and paths.
- Session provider redacts credential-bearing fields before writing shared payload.
- Expired or missing session maps to `login_required`.
- Malformed wallet response maps to `balance_unavailable`.

Display tests:

- WidgetKit and Uebersicht show the console-session balance when present.
- They show login-required and balance-unavailable messages without touching credentials.

Manual verification:

- Configure only API key and confirm negative SiliconFlow values are not displayed.
- Enable console session and confirm the shown balance matches the SiliconFlow console.
- Disconnect console session and confirm the display returns to a safe noncredential state.

## Implementation Plan

1. Keep the current API-key negative-balance guard.
2. Add `source` and `login_required` to the shared contract if not already present.
3. Add a macOS-only console session store and allowlisted fetcher.
4. Add settings UI for connect, reconnect, and disconnect.
5. Wire sanitized console-session output into the shared usage payload.
6. Update WidgetKit and Uebersicht copy for the new states.
7. Add tests for provider selection and credential isolation.

## Open Questions

- Whether the embedded login flow can complete inside `WKWebView` without SiliconFlow blocking embedded browsers.
- Which exact `financialInfo` field should be treated as the canonical display balance. This must be confirmed from a sanitized response sample before implementation.
- Whether SiliconFlow publishes or will publish an official billing endpoint for API-key use. If they do, prefer the official API over this console-session provider.
