# Design language — AI Agent Usage Widget

One shared visual + textual language across every frontend (macOS WidgetKit,
Übersicht, Touch Bar, Windows). New frontends and changes to existing ones must
follow this document.

## Providers

Three providers, always in this order: **Claude**, **Codex**, **Kimi Code**.

Each provider has a fixed brand palette:

| Provider | accent (5H) | soft (weekly) | card background | text on card |
|----------|-------------|----------------|-----------------|--------------|
| Claude   | `#D97757`   | `#E3A77F`      | cream `#FAF9F5 → #F0EEE6` | ink `#26231F`, sub `#9A9286` |
| Codex    | `#6676FF`   | `#A78BFA`      | dark `#17171A → #0E0E10`  | ink `#ECECEC`, sub `#888894` |
| Kimi     | `#1478FF`   | `#9AA0AC`      | light `#FBFBFC → #F1F3F7` | ink `#17181C`, sub `#737984` |

- **accent** = the 5-hour window color, also the large percentage.
- **soft** = the weekly window color.
- Card background is per-provider (Claude warm, Codex dark, Kimi light); pick text
  ink/sub from the same row so it stays legible on that card.

## Icons

Every provider is represented by its **app icon**, scaled down — never a glyph or
letter. Assets live alongside each frontend (`claude-app.png`, `codex-app.png`,
`kimi-code.png`, or the SVG equivalents on Windows). Render at ~18–20pt with a
small rounded-corner clip.

## Rings

The canonical chart is a **dual ring**:

- **outer ring = Weekly** (soft color)
- **inner ring = 5H** (accent color)
- **center label = the 5H percentage** (accent color)

Each ring has a faint track (same color, low opacity) under the filled arc; arcs
start at 12 o’clock and fill clockwise. The center percentage must be constrained
to the inner ring’s hole so it never overlaps the stroke.

(Horizontal form factors like the Touch Bar may lay the two rings out as two
stacked bars instead, but the color mapping — accent = 5H, soft = weekly — is the
same.)

## Canonical text

Use these exact terms everywhere. Do not localize them.

| Concept | Term |
|---------|------|
| 5-hour window | `5H` |
| weekly window | `Weekly` |
| reset countdown | `Resets in …` |

Reset countdown format (single source of truth):

- days remaining: `Resets in {d}d {h}h`
- hours remaining: `Resets in {h}h {m}m`
- under an hour: `Resets in {m}m`
- already past / unknown: `Resets soon`

Compact strips (Touch Bar) may drop the `Resets in` prefix and show the bare
duration (`4h47m`) next to a ⟳ glyph, but the duration grammar above is unchanged.

Status messages (no data, expired, rate-limited, etc.) stay in the user’s language
— only the three terms above are fixed English.

## Layouts by size

- **Small / single-provider** — one provider card, laid out top-to-bottom: icon +
  name, dual ring, then `5H` and `Weekly` rows (color dot + label + percentage,
  with the `Resets in …` line under each). On platforms that can detect the
  foreground app, the small/collapsed view follows whichever AI client is frontmost
  (Claude / Codex / Kimi), falling back to the most recently used — see the Touch
  Bar implementation as the reference for the keyword matching.
- **Medium / multi-provider** — the three provider cards side by side, each with the
  dual ring and `5H` / `Weekly` rows + reset times, content distributed to fill the
  card height (no large empty band at the bottom).
