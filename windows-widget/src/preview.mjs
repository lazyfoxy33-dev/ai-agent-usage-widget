import { render } from "./render.mjs";

const now = Math.floor(Date.now() / 1000);
render({
  schema_version: 1,
  claude: {
    ok: true,
    live: true,
    five_h: { pct: 85, resets_at: now + 4_800 },
    weekly: { pct: 29, resets_at: now + 500_000 },
  },
  codex: {
    ok: true,
    live: false,
    as_of: now - 4_000,
    five_h: { pct: 100, resets_at: now + 6_000, stale: true },
    weekly: { pct: 37, resets_at: now + 600_000, stale: false },
  },
  kimi: {
    ok: true,
    live: true,
    five_h: { pct: 36, resets_at: now + 8_000 },
    weekly: { pct: 9, resets_at: now + 700_000 },
  },
});
