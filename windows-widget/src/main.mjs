import { render, rerenderCountdowns } from "./render.mjs";
import { createWidget } from "./widget.mjs";

const status = document.querySelector("#status");
const tauri = window.__TAURI__;

const widget = createWidget({
  statusEl: status,
  refreshBtn: document.querySelector("#refresh"),
  tauri,
  render,
  rerenderCountdowns,
});

await widget.start();
