import assert from "node:assert/strict";
import test from "node:test";

import { providerMessage, renderToHTML } from "./render.mjs";

const livePayload = {
  schema_version: 1,
  claude: {
    ok: true,
    live: true,
    five_h: { pct: 85, resets_at: 2_000_000_000 },
    weekly: { pct: 29, resets_at: 2_000_100_000 },
  },
  codex: {
    ok: true,
    live: false,
    as_of: 1_900_000_000,
    five_h: { pct: 88, resets_at: 2_000_000_000, stale: true },
    weekly: { pct: 37, resets_at: 2_000_100_000, stale: false },
  },
  kimi: { ok: false, reason: "expired", live: false },
};

test("render includes percentages and stale state", () => {
  const html = renderToHTML(livePayload, 1_999_999_000_000);
  assert.match(html, />85%<\//);
  assert.match(html, />88%<\//);
  assert.match(html, /provider-card codex stale/);
  assert.match(html, /登录态过期 · 去 Kimi CLI 重新登录/);
});

test("provider messages distinguish rate limits", () => {
  assert.equal(
    providerMessage("Claude", { reason: "rate_limited" }),
    "请求受限 · 稍后自动重试",
  );
});
