function startDrag(e) {
  if (!window.__TAURI__) return;
  e.preventDefault();
  window.__TAURI__.core.invoke("get_window_position").then(([baseX, baseY]) => {
    const startX = e.screenX;
    const startY = e.screenY;
    let dragging = true;
    const onMove = (ev) => {
      if (!dragging) return;
      const newX = baseX + (ev.screenX - startX);
      const newY = baseY + (ev.screenY - startY);
      window.__TAURI__.core.invoke("set_window_position", { x: newX, y: newY });
    };
    const onUp = () => {
      dragging = false;
      document.removeEventListener("mousemove", onMove);
      document.removeEventListener("mouseup", onUp);
    };
    document.addEventListener("mousemove", onMove);
    document.addEventListener("mouseup", onUp);
  });
}

function enableDragFallback(selector) {
  if (!window.__TAURI__) return;
  const el = document.querySelector(selector);
  if (!el) return;
  el.addEventListener("mousedown", startDrag);
}

export function createWidget({ statusEl, refreshBtn, tauri, render, rerenderCountdowns }) {
  function setStatus(message, isError = false) {
    statusEl.textContent = message;
    statusEl.classList.toggle("error", isError);
  }

  async function refresh() {
    setStatus("正在刷新…");
    try {
      const raw = await tauri.core.invoke("refresh_usage");
      render(JSON.parse(raw));
      setStatus("数据已更新");
    } catch (error) {
      const message = String(error).includes("no_python")
        ? "未检测到 Python，请安装并重启"
        : "刷新失败 · 保留上次数据";
      setStatus(message, true);
    }
  }

  if (refreshBtn) {
    refreshBtn.addEventListener("click", refresh);
  }

  let intervalId;
  const listeners = [];

  async function start() {
    enableDragFallback(".toolbar");
    const usageListener = await tauri.event.listen("usage", ({ payload }) => {
      render(JSON.parse(payload));
      setStatus("数据已更新");
    });
    listeners.push(usageListener);

    const errorListener = await tauri.event.listen("usage-error", ({ payload }) => {
      setStatus(payload === "no_python"
        ? "未检测到 Python，请安装并重启"
        : "刷新失败 · 保留上次数据", true);
    });
    listeners.push(errorListener);

    intervalId = setInterval(rerenderCountdowns, 60_000);
    refresh();
  }

  function stop() {
    for (const unsubscribe of listeners) {
      if (typeof unsubscribe === "function") unsubscribe();
    }
    listeners.length = 0;
    clearInterval(intervalId);
  }

  return { refresh, start, stop, setStatus };
}
