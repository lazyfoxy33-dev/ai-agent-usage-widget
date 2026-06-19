# Design language — AI Agent Usage Widget

One shared visual + textual language across every frontend (macOS WidgetKit,
Übersicht, Touch Bar, Windows). New frontends and changes to existing ones must
follow this document. The authoritative, runnable reference is the Claude Design
iteration under `docs/design/` (especially `components/_widget.css` +
`components/_widget.js`); this doc is the prose summary.

## Providers

Three providers, always in this order: **Claude**, **Codex**, **Kimi Code**.

Each provider has one brand accent and a subtle background tint:

| Provider | accent | tint (light) | tint (dark) |
|----------|--------|--------------|-------------|
| Claude   | `#D97757` | `#FAF7F3` | `#211F1C` |
| Codex    | `#7B83F5` | `#F6F6FB` | `#1B1B23` |
| Kimi     | `#1478FF` | `#F4F7FC` | `#181C24` |

- **accent** is the single brand hue per provider. Both windows (5H and Weekly) are
  drawn in that hue — there is no longer a separate "soft" weekly color.
- **Card background** is a subtle brand tint that **follows the system appearance**
  (light/dark). Codex is no longer a hard dark card. Tone tokens by theme:
  light → ink `#26231F`, sub `#9a9286`; dark → ink `#ECEAE6`, sub `#8c887f`.
- **Semantic emphasis** — the color is deepened (light) / brightened (dark) *in-hue*
  by how full a window is: `<70%` plain accent · `70–90%` attention · `≥90%` urgent.
  Emphasis applies to the metric value, the ring stroke and the row dot; a bar's fill
  stays the plain accent (with an optional brand-tinted danger zone in the track's last
  ~18%). Exact math: `emph` / `meter` / `style` in `docs/design/components/_widget.js`.

## Icons

Every provider is represented by its **app icon**, scaled down — never a glyph or
letter. Assets live alongside each frontend (`claude-app.png`, `codex-app.png`,
`kimi-code.png`, or the SVG equivalents on Windows). Render at ~18–20pt with a
small rounded-corner clip. (The Touch Bar, being severely space-constrained, is the
one exception and may use single-letter brand badges.)

## Chart form: rings on roomy surfaces, bars when compact

- **Roomy widgets** (macOS WidgetKit, Übersicht, Windows) use the **dual ring**.
- **Compact strips** (Touch Bar) use two stacked **bars** instead.

The color mapping is identical either way.

### Dual ring

- **outer ring = Weekly**, **inner ring = 5H** — both in the provider accent,
  each emphasized by *its own* fill %.
- **center label = the more-full (urgent) window's %**, in that window's emphasis color,
  with its two-letter code (`5H` / `Wk`) beneath.

Each ring has a faint track under the filled arc; arcs start at 12 o'clock and fill
clockwise. The center figure is constrained to the inner ring's hole so it never
overlaps the stroke.

## Canonical text

Use these exact terms everywhere. Do not localize them.

| Concept | Term |
|---------|------|
| 5-hour window | `5H` |
| weekly window | `Wk` |
| reset countdown | `↻ {dur}` |

On the roomy widgets (Übersicht, macOS Widget) each metric row shows **its own**
window's reset inline, between the code and the percentage, as `↻ {dur}` — e.g.
`● 5H  ↻ 2h 14m  47%`. The Touch Bar, which has no room for per-row countdowns,
shows the single soonest reset in its strip. There is no `Resets in` prefix anywhere.

Duration grammar (single source of truth):

- days remaining: `{d}d {h}h`
- hours remaining: `{h}h {m}m`
- under an hour: `{m}m`
- already past / unknown: `Resets soon`

On platforms that can detect the foreground app, the small/collapsed view follows
whichever AI client is frontmost (Claude / Codex / Kimi), falling back to the most
recently used — see the Touch Bar implementation as the reference for the keyword
matching.

## States & language

Only **two** states ever show a message; the normal state is silent:

- **cached** — data exists but is stale (`live == false` / `reason == "stale"` / a
  window's `stale`): dim the metrics and add a short caption
  (`缓存数据 · 等待刷新` / `Cached · awaiting refresh`).
- **login** — no usable data (`ok == false`): a dimmed panel with a sign-in line.
  Map by reason: `expired` / `no_data` → `未登录 · 请先在 {CLI} 登录`
  (Claude → Claude Code, Codex → Codex CLI, Kimi Code → Kimi CLI);
  `rate_limited` → `请求受限 · 稍后自动重试`.

Status text follows the user's language (default Chinese; English when the system
locale starts with `en`). The fixed tokens above (`5H` / `Wk` / the ↻ glyph) stay as
written regardless of language.

## Layouts by size

- **Small / single-provider** — one provider card, top-to-bottom: icon + name, dual ring,
  then the `5H` and `Wk` rows (color dot + code + inline `↻ {dur}` + percentage).
- **Medium / multi-provider** — the three provider cards side by side, each with the dual
  ring and `5H` / `Wk` rows, content distributed to fill the card height (no large empty
  band at the bottom). Keep type small enough that a row never wraps.
</content>
