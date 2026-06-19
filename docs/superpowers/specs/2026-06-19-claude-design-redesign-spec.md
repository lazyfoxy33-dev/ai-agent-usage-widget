# Redesign spec — sync all frontends to the Claude Design iteration

Source of truth: `docs/design/` (especially `components/_widget.css` + `components/_widget.js`
and `README.md`). This doc translates that iteration into per-frontend tasks so each end
shares one visual + textual language. Coding is delegated to Kimi CLI; this file is the
acceptance contract.

## Decisions (confirmed with user)
- Apply to **all** frontends, and any future end uses the same system.
- **Large widgets keep the dual ring; compact ends use bars.** → Übersicht, Windows,
  macOS Widget keep rings. Touch Bar keeps its horizontal bars.
- **Credits (`Cr`) panel is style-only** — not wired to data (core has no credit provider).
- `docs/design-language.md` must be updated so it no longer conflicts with the new
  countdown/term rules below.

## Canonical rules (apply to every frontend)

1. **Semantic emphasis by used %** — `lvl = used>=90?2 : used>=70?1 : 0` (0 充足 / 1 注意 / 2 告急).
   In-hue emphasis of the accent:
   - light theme: multiply each channel by `[1, .84, .70][lvl]`
   - dark theme: lerp each channel toward white by `[0, .20, .38][lvl]`
   The **fill / arc stays the brand accent**; emphasis is applied to the **value text**
   and the **ring stroke / row dot**. (Ref `emph`/`meter`/`style` in `_widget.js`.)
2. **Danger track zone** — the track is `base 0→82%` then a brand-tinted cap zone
   `rgba(accent, dark?.26:.15) 82→100%` (ref `dangerTrack`). Bars/rings only; optional on
   native rings if hard to express.
3. **Subtle brand-tint backgrounds following system light/dark** (replaces fixed
   per-provider gradients; Codex is no longer a hard dark card):
   | provider | accent | tint light | tint dark |
   |----------|--------|-----------|-----------|
   | Claude | `#D97757` | `#FAF7F3` | `#211F1C` |
   | Codex  | `#7B83F5` (no gradient) | `#F6F6FB` | `#1B1B23` |
   | Kimi   | `#1478FF` | `#F4F7FC` | `#181C24` |
   Tone tokens by theme — light: ink `#26231F`, sub `#9a9286`, track `rgba(0,0,0,.09)`,
   div `rgba(0,0,0,.06)`; dark: ink `#ECEAE6`, sub `#8c887f`, track `rgba(255,255,255,.13)`,
   div `rgba(255,255,255,.07)`.
4. **Two-letter quota codes**: `5H`, `Wk` (Weekly→Wk), `Cr`. Same column alignment.
5. **Header countdown = soonest reset only**: `↻ {code} {dur}` (e.g. `↻ Wk 4d 12h`) in the
   provider header next to the name. Drop the per-row "Resets in …" lines. Duration grammar
   (single source): `{d}d {h}h` / `{h}h {m}m` / `{m}m`, past/unknown → `Resets soon`.
6. **Only two states needing a prompt** — normal shows **no message**:
   - `cached` (have data but stale: `live==false` / `reason=="stale"` / window `stale`):
     dim the data + caption `缓存数据 · 等待刷新` / `Cached · awaiting refresh`.
   - `login` (no usable data, `ok==false`): dimmed panel + sign-in message. Map by reason:
     `expired`/`no_data` → `未登录 · 请先在 {CLI} 登录` (cmdMap: Claude→Claude Code,
     Codex→Codex CLI, Kimi Code→Kimi CLI); `rate_limited` → `请求受限 · 稍后自动重试`.
7. **i18n** — default Chinese; auto English when the system locale starts with `en`
   (web: `navigator.language`, override `window.UW_LOCALE`; Swift: `Locale.current`).
   The three terms `5H` / `Wk` / `Resets`(glyph ↻) stay fixed; status text is localized.
   Keep the dictionary in one place per frontend.
8. Provider order always Claude · Codex · Kimi Code. Icons = scaled app PNGs (no letters)
   wherever the surface already shows an icon.

## Per-frontend tasks

### A. Übersicht — `usage-widget/index.jsx` (+ `tests/test_widget_source.py`)
- Keep dual ring. Port `ringPanel` look: header `icon + name + ↻ soonest`; two rows
  `dot + code(5H/Wk) + value`, value & dot use semantic color, ring strokes use semantic
  color per window. Tint bg + tone tokens chosen from `matchMedia('(prefers-color-scheme:dark)')`.
- Codex: accent `#7B83F5`, **remove the gradient defs/stroke**; render it the same as Claude/Kimi.
- Collapse the many `providerMessage`/`codexPanel` branches into the two-state model + the
  shared i18n dictionary. Remove the separate `codexPanel`; one `panel` for all three.
- Keep `pctFontSize` (3-digit shrink) and the bottom-right anchor (`right:40px;bottom:40px`).
- **Rewrite `tests/test_widget_source.py`** to assert the new design (accent `#7B83F5`,
  no `codexAccentGradient`, `Wk` code, soonest `↻` header, two-state strings, tint bgs).

### B. Windows — `windows-widget/src/render.mjs` + `styles.css` (+ `render.test.mjs`)
- Same ring port as A in vanilla template strings + CSS. Theme from `matchMedia`.
- Codex accent `#7B83F5`, drop gradient. Two-state model + i18n dictionary; `Wk`; soonest
  `↻` header; semantic colors; tint backgrounds.
- **Update `render.test.mjs`** to the new strings/markup.

### C. macOS Widget — `macwidget/Widget/QuotaWidget.swift` + `Shared/UsageContract.swift`
  (+ `Tests/*`)
- Keep `DualRing` (small + medium). Add a Swift `emph(accent, lvl, isDark)` and use it for
  ring strokes, the center %, row values, row dots.
- Palette: drive tint background + tone from `@Environment(\.colorScheme)` (subtle tint,
  Codex no longer hard-dark; accent `#7B83F5`).
- Replace per-row `Resets in` with one soonest `↻ {code} {dur}` in the card header.
  Rows become `dot + code(5H/Wk) + value` (no countdown line).
- `ProviderPresentation`: update `countdown` to the bare `{d}d {h}h`/`{h}h {m}m`/`{m}m`
  grammar; add `soonest(provider)`; collapse `message` to the two-state model; add
  locale-aware (zh/en) strings.
- Update Swift tests that assert old countdown/message text.

### D. Touch Bar — `touchbar/Sources/ProviderGauge.swift` + `TouchBarController.swift`
- Keep the horizontal two-bar gauge. Apply: semantic accent via `emph(..., isDark:true)`
  (brighten variant) on fills + value; `Weekly` label → `Wk`; Codex accent `#7B83F5`
  (`0x7B,0x83,0xF5`). Keep letter badges (icon bundling out of scope for this pass — note it).
- Tray glance + soonest reset logic unchanged except the `Wk` label.

### E. Docs — `docs/design-language.md`
- Update the "Canonical text" reset section to the soonest-only `↻ {code} {dur}` header
  format and the bare duration grammar; note `Wk` two-letter code; note bars-vs-rings rule
  (rings on roomy widgets, bars on compact). Remove the now-conflicting `Resets in …` wording.

## Verification (acceptance gates)
- `python3 -m pytest usage-widget/tests core/tests -q` → green (after test rewrite).
- `node --test windows-widget/src/render.test.mjs` → green.
- `cd touchbar && ./build.sh` (or `swiftc` compile) → builds clean.
- macwidget: `xcodebuild -project macwidget/QuotaWidget.xcodeproj -scheme QuotaWidget build`
  (or at minimum `swift -frontend -typecheck` of changed files) → compiles.
- Visual spot-check the design reference (`docs/design/components/widget-full.html`,
  `panels.html`, `states.html`) and confirm each frontend matches: semantic colors at
  47/91%, tint bgs in light+dark, `Wk` code, `↻` soonest header, two states only.
- `git grep -n "Resets in"` should only remain where intentionally kept (none in widgets).
</content>
</invoke>
