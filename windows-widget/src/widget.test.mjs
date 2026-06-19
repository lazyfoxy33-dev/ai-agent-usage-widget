import assert from "node:assert/strict";
import test from "node:test";

import { createWidget } from "./widget.mjs";

global.window = {};

function makeMock() {
  let statusText = "";
  let statusError = false;
  const invokeCalls = [];
  const listenEvents = [];
  let renderedPayload = null;

  const statusEl = {
    get textContent() { return statusText; },
    set textContent(v) { statusText = v; },
    classList: {
      toggle: (cls, active) => {
        if (cls === "error") statusError = active;
      },
    },
  };

  const refreshBtn = {
    addEventListener: (type, handler) => {
      refreshBtn._clickHandler = handler;
    },
  };

  const tauri = {
    core: {
      invoke: async (cmd, ...args) => {
        invokeCalls.push({ cmd, args });
        return JSON.stringify({ schema_version: 1, claude: {}, codex: {}, kimi: {} });
      },
    },
    event: {
      listen: async (event, handler) => {
        listenEvents.push({ event, handler });
        return () => {};
      },
    },
  };

  function render(payload) {
    renderedPayload = payload;
  }

  function rerenderCountdowns() {}

  return {
    statusEl, refreshBtn, tauri, render, rerenderCountdowns,
    getStatusText: () => statusText,
    getStatusError: () => statusError,
    getInvokeCalls: () => invokeCalls,
    getListenEvents: () => listenEvents,
    getRenderedPayload: () => renderedPayload,
    fireUsageEvent: (payload) => {
      const ev = listenEvents.find(e => e.event === "usage");
      if (ev) ev.handler({ payload: JSON.stringify(payload) });
    },
    fireUsageError: (payload) => {
      const ev = listenEvents.find(e => e.event === "usage-error");
      if (ev) ev.handler({ payload });
    },
    clickRefresh: () => {
      if (refreshBtn._clickHandler) refreshBtn._clickHandler();
    },
  };
}

test("refresh invokes tauri and renders on success", async () => {
  const m = makeMock();
  const widget = createWidget(m);
  await widget.refresh();

  assert.equal(m.getInvokeCalls().length, 1);
  assert.equal(m.getInvokeCalls()[0].cmd, "refresh_usage");
  assert.deepStrictEqual(m.getRenderedPayload(), { schema_version: 1, claude: {}, codex: {}, kimi: {} });
  assert.equal(m.getStatusText(), "数据已更新");
  assert.equal(m.getStatusError(), false);
});

test("refresh handles no_python error", async () => {
  const m = makeMock();
  m.tauri.core.invoke = async () => { throw new Error("no_python"); };
  const widget = createWidget(m);
  await widget.refresh();

  assert.equal(m.getStatusText(), "未检测到 Python，请安装并重启");
  assert.equal(m.getStatusError(), true);
});

test("refresh handles generic error", async () => {
  const m = makeMock();
  m.tauri.core.invoke = async () => { throw new Error("network timeout"); };
  const widget = createWidget(m);
  await widget.refresh();

  assert.equal(m.getStatusText(), "刷新失败 · 保留上次数据");
  assert.equal(m.getStatusError(), true);
});

test("clicking refresh button triggers refresh", async () => {
  const m = makeMock();
  const widget = createWidget(m);
  m.clickRefresh();
  await new Promise(r => setTimeout(r, 10));

  assert.equal(m.getInvokeCalls().length, 1);
  assert.equal(m.getInvokeCalls()[0].cmd, "refresh_usage");
});

test("usage event renders and updates status", async () => {
  const m = makeMock();
  const widget = createWidget(m);
  await widget.start();

  const payload = { schema_version: 1, claude: { ok: true }, codex: {}, kimi: {} };
  m.fireUsageEvent(payload);

  assert.deepStrictEqual(m.getRenderedPayload(), payload);
  assert.equal(m.getStatusText(), "数据已更新");
  assert.equal(m.getStatusError(), false);
  widget.stop();
});

test("usage-error with no_python updates status", async () => {
  const m = makeMock();
  const widget = createWidget(m);
  await widget.start();

  m.fireUsageError("no_python");
  assert.equal(m.getStatusText(), "未检测到 Python，请安装并重启");
  assert.equal(m.getStatusError(), true);
  widget.stop();
});

test("usage-error with generic error updates status", async () => {
  const m = makeMock();
  const widget = createWidget(m);
  await widget.start();

  m.fireUsageError("fetch_failed");
  assert.equal(m.getStatusText(), "刷新失败 · 保留上次数据");
  assert.equal(m.getStatusError(), true);
  widget.stop();
});

test("start registers listeners and calls refresh", async () => {
  const m = makeMock();
  const widget = createWidget(m);
  await widget.start();

  const events = m.getListenEvents();
  assert.equal(events.length, 2);
  assert.equal(events[0].event, "usage");
  assert.equal(events[1].event, "usage-error");
  assert.equal(m.getInvokeCalls().length, 1);
  widget.stop();
});
