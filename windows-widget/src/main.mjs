import { render, rerenderCountdowns } from "./render.mjs";

const status = document.querySelector("#status");
const tauri = window.__TAURI__;

function setStatus(message, isError = false) {
  status.textContent = message;
  status.classList.toggle("error", isError);
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

document.querySelector("#refresh").addEventListener("click", refresh);
await tauri.event.listen("usage", ({ payload }) => {
  render(JSON.parse(payload));
  setStatus("数据已更新");
});
await tauri.event.listen("usage-error", ({ payload }) => {
  setStatus(payload === "no_python"
    ? "未检测到 Python，请安装并重启"
    : "刷新失败 · 保留上次数据", true);
});

setInterval(rerenderCountdowns, 60_000);
refresh();
