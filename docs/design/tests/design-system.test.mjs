import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";

const root = path.resolve(import.meta.dirname, "..");

function loadUW() {
  const context = {
    window: {},
    document: {
      readyState: "complete",
      querySelectorAll: () => [],
    },
    navigator: { language: "zh-CN" },
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(
    fs.readFileSync(path.join(root, "components", "_widget.js"), "utf8"),
    context,
    { filename: "_widget.js" },
  );
  return context.window.UW;
}

test("design system models real balance providers", () => {
  const UW = loadUW();

  assert.deepEqual(Array.from(UW.BALANCE, (provider) => provider.name), [
    "DeepSeek",
    "SiliconFlow",
    "OpenRouter",
  ]);
  assert.equal(UW.BALANCE[0].amount, "¥45.83");
  assert.equal(UW.BALANCE[1].state, "no_api_key");
  assert.deepEqual(Array.from(UW.BALANCE, (provider) => provider.icon), [
    "../assets/deepseek.png",
    "../assets/siliconflow.png",
    "../assets/openrouter.png",
  ]);
});

test("design system uses image logos for every provider", () => {
  const UW = loadUW();
  const providers = [...UW.P, ...UW.BALANCE];

  assert.deepEqual(
    providers.map((provider) => provider.icon),
    [
      "../assets/claude-app.png",
      "../assets/codex-app.png?v=logo-fix",
      "../assets/kimi-code.png",
      "../assets/deepseek.png",
      "../assets/siliconflow.png",
      "../assets/openrouter.png",
    ],
  );

  const html = UW.widgetPanels("bar", "light", "all");
  for (const provider of providers) {
    assert.ok(html.includes(`src="${provider.icon}"`));
    assert.ok(html.includes(`alt="${provider.name}"`));
  }
});

test("bar-primary widget includes quota and balance providers", () => {
  const UW = loadUW();
  const html = UW.widgetPanels("bar", "light", "all");

  assert.match(html, /Claude/);
  assert.match(html, /DeepSeek/);
  assert.match(html, /balance-main/);
  assert.match(html, /src="\.\.\/assets\/deepseek\.png"/);
  assert.match(html, /src="\.\.\/assets\/siliconflow\.png"/);
  assert.match(html, /src="\.\.\/assets\/openrouter\.png"/);
  assert.match(html, /¥45\.83/);
  assert.match(html, /未配置 API 密钥/);
});

test("compact and touch bar have balance-specific renderers", () => {
  const UW = loadUW();

  assert.match(UW.compactRow(UW.BALANCE[0], "light"), /balance-mini/);
  assert.match(UW.touchCell(UW.BALANCE[2]), /OpenRouter/);
  assert.match(UW.touchCell(UW.BALANCE[2]), /\$75\.42/);
});

test("states include balance cache and missing key", () => {
  const UW = loadUW();

  assert.match(UW.statePanel(UW.BALANCE[0], "light", "cached", "zh"), /缓存余额/);
  assert.match(UW.statePanel(UW.BALANCE[1], "light", "no_api_key", "zh"), /未配置 API 密钥/);
});
