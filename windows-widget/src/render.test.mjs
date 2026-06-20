import assert from "node:assert/strict";
import test from "node:test";

import { providerMessage, countdown, renderToHTML } from "./render.mjs";

// Pin tests to Chinese strings (Node's navigator may default to en).
global.window = { UW_LOCALE: "zh" };

const NOW_S = 2_000_000_000;
const NOW_MS = NOW_S * 1000;

const livePayload = {
  schema_version: 1,
  claude: {
    ok: true,
    live: true,
    five_h: { pct: 85, resets_at: NOW_S + 3600 },      // 1h
    weekly: { pct: 91, resets_at: NOW_S + 432000 },    // 5d
  },
  codex: {
    ok: true,
    live: false,
    as_of: 1_900_000_000,
    five_h: { pct: 88, resets_at: NOW_S + 1800, stale: true },  // 30m
    weekly: { pct: 37, resets_at: NOW_S + 86400, stale: false }, // 1d
  },
  kimi: { ok: false, reason: "expired", live: false },
};

test("countdown returns bare duration grammar", () => {
  assert.equal(countdown(NOW_S + 86400 * 5 + 3600 * 12, NOW_MS), "5d 12h");
  assert.equal(countdown(NOW_S + 3600 * 2 + 60 * 30, NOW_MS), "2h 30m");
  assert.equal(countdown(NOW_S + 60 * 45, NOW_MS), "45m");
  assert.equal(countdown(NOW_S + 59, NOW_MS), null);
  assert.equal(countdown(null, NOW_MS), null);
});

test("provider messages use two-state model", () => {
  assert.equal(
    providerMessage("Claude", { reason: "rate_limited" }),
    "请求受限 · 稍后自动重试"
  );
  assert.equal(
    providerMessage("Claude", { reason: "expired" }),
    "未登录 · 请先在 Claude Code 登录"
  );
  assert.equal(
    providerMessage("Codex", { reason: "no_data" }),
    "未登录 · 请先在 Codex CLI 登录"
  );
  assert.equal(
    providerMessage("Kimi Code", { reason: "expired" }),
    "未登录 · 请先在 Kimi CLI 登录"
  );
});

test("render uses new design tokens and structure", () => {
  const html = renderToHTML(livePayload, NOW_MS);

  // Codex accent updated, no gradient
  assert.match(html, /#7B83F5/);
  assert.doesNotMatch(html, /<linearGradient/);
  assert.doesNotMatch(html, /url\(#.*-accent\)/);

  // Two-letter quota code
  assert.match(html, />Wk</);
  assert.match(html, />5H</);

  // Each row shows its own reset countdown (matching macwidget MetricRow)
  assert.match(html, /↻\s*30m/); // Codex 5H = 30m
  assert.match(html, /↻\s*1h/);  // Claude 5H = 1h

  // Center shows most-full (urgent) window: Claude weekly 91%
  assert.match(html, />91%</);
});

test("render marks stale/cached state", () => {
  const html = renderToHTML(livePayload, NOW_MS);
  assert.match(html, /provider-card codex stale/);
  assert.match(html, /缓存数据 · 等待刷新/);
});

test("render shows login failure for Kimi", () => {
  const html = renderToHTML(livePayload, NOW_MS);
  assert.match(html, /provider-card kimi failed/);
  assert.match(html, /未登录 · 请先在 Kimi CLI 登录/);
});

test("render preserves expected percentages in rows", () => {
  const html = renderToHTML(livePayload, NOW_MS);
  assert.match(html, />85%</);
  assert.match(html, />88%</);
  assert.match(html, />37%</);
});

test("english locale switches strings", () => {
  const prev = global.window.UW_LOCALE;
  global.window.UW_LOCALE = "en";
  try {
    assert.equal(
      providerMessage("Claude", { reason: "expired" }),
      "Not signed in · Log in via Claude Code"
    );
    const html = renderToHTML(livePayload, NOW_MS);
    assert.match(html, /Cached · awaiting refresh/);
    assert.match(html, /Not signed in · Log in via Kimi CLI/);
  } finally {
    global.window.UW_LOCALE = prev;
  }
});
