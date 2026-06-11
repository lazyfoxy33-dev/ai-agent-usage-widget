# Kimi Code Usage Panel Design

## Goal

Add Kimi Code usage to the Übersicht widget while preserving the existing
provider isolation, privacy guarantees, visual hierarchy, and automatic refresh
behavior. Also replace the clipped hand-drawn Codex glyph with the complete
Codex App cloud icon.

## Data Source

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

The widget is a read-only consumer:

- It does not read browser cookies.
- It does not scrape the Kimi web console.
- It does not refresh or rotate OAuth tokens.
- It does not write credentials into cache files.
- It does not put the access token in process arguments.

If no usable local Kimi login exists, the panel instructs the user to sign in
with Kimi CLI. The Kimi console URL is documentation and manual-viewing
fallback only.

## Parsing And Mapping

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

## Fetching And Cache

The provider uses `curl` through Python's subprocess API, matching the existing
Claude integration's proxy behavior and token-safety pattern.

- The Authorization header is supplied through curl configuration on stdin.
- `HTTPS_PROXY` and `https_proxy` are honored.
- Successful Kimi data is cached for five minutes.
- A temporary fetch failure may return cached data marked stale.
- Authentication failures do not trigger token refresh and instruct the user
  to sign in with Kimi CLI.
- Kimi failures remain independent from Claude and Codex failures.

## Interface

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

## Brand Assets

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

## Error States

Kimi panel states:

- `no_data`: Kimi CLI is not installed or has not created credentials.
- `expired`: the local OAuth access token is expired or rejected.
- `error`: network or unexpected response failure.
- `stale`: cached data is shown after a temporary fetch failure.

Provider errors never hide the other two panels.

## Tests

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

## Documentation

README changes explain:

- Kimi CLI installation/login prerequisite
- The official `/usages` data source
- Five-minute cache and one-minute widget refresh
- Manual console fallback link
- The no-cookie and no-token-refresh policy
- Troubleshooting for missing or expired Kimi credentials
- Third-party trademark and unofficial-project status
