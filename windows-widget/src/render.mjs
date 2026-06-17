const palettes = {
  Claude: {
    key: "claude",
    accent: "#D97757",
    soft: "#E3A77F",
    logo: "assets/claude.svg",
  },
  Codex: {
    key: "codex",
    accent: "#6676FF",
    soft: "#A78BFA",
    logo: "assets/codex-app.png",
  },
  "Kimi Code": {
    key: "kimi",
    accent: "#1478FF",
    soft: "#252A33",
    logo: "assets/kimi-code.png",
  },
};

function clamp(value) {
  return Math.max(0, Math.min(100, Number(value) || 0));
}

export function providerMessage(name, data = {}) {
  if (data.reason === "rate_limited") return "请求受限 · 稍后自动重试";
  if (name === "Kimi Code") {
    if (data.reason === "expired") return "登录态过期 · 去 Kimi CLI 重新登录";
    if (data.reason === "no_data") return "未登录 · 先在 Kimi CLI 完成登录";
    return "获取失败 · 可前往 Kimi 控制台查看";
  }
  if (name === "Codex") return "暂无数据 · 先使用一次 Codex";
  if (data.reason === "expired") return "登录态过期 · 去 Claude Code 重新登录";
  return "暂无数据";
}

export function countdown(resetsAt, nowMs = Date.now()) {
  if (!resetsAt) return "Resets soon";
  const seconds = Math.max(0, Math.floor(Number(resetsAt) - nowMs / 1000));
  const days = Math.floor(seconds / 86_400);
  const hours = Math.floor((seconds % 86_400) / 3_600);
  const minutes = Math.floor((seconds % 3_600) / 60);
  if (days > 0) return `Resets in ${days}d ${hours}h`;
  if (hours > 0) return `Resets in ${hours}h ${minutes}m`;
  return `Resets in ${minutes}m`;
}

function ring(name, five, weekly) {
  const palette = palettes[name];
  const outer = 2 * Math.PI * 38;
  const inner = 2 * Math.PI * 27;
  const fivePct = clamp(five);
  const weekPct = clamp(weekly);
  const id = palette.key;
  const accent = name === "Codex" ? `url(#${id}-accent)` : palette.accent;
  const soft = name === "Codex" ? `url(#${id}-soft)` : palette.soft;
  return `
    <div class="ring">
      <svg viewBox="0 0 88 88" aria-hidden="true">
        <defs>
          <linearGradient id="${id}-accent" x1="12" y1="12" x2="76" y2="76">
            <stop stop-color="#A98CFF"/><stop offset=".48" stop-color="#7284FF"/>
            <stop offset="1" stop-color="#394DFF"/>
          </linearGradient>
          <linearGradient id="${id}-soft" x1="12" y1="12" x2="76" y2="76">
            <stop stop-color="#C4B5FD"/><stop offset="1" stop-color="#7C86E8"/>
          </linearGradient>
        </defs>
        <circle class="track" cx="44" cy="44" r="38"/>
        <circle class="progress" cx="44" cy="44" r="38" stroke="${soft}"
          stroke-dasharray="${outer}" stroke-dashoffset="${outer * (1 - weekPct / 100)}"/>
        <circle class="track" cx="44" cy="44" r="27"/>
        <circle class="progress" cx="44" cy="44" r="27" stroke="${accent}"
          stroke-dasharray="${inner}" stroke-dashoffset="${inner * (1 - fivePct / 100)}"/>
      </svg>
      <div class="ring-value" style="color:${palette.accent}">
        <strong class="${fivePct >= 100 ? "three-digit" : ""}">${fivePct}%</strong>
        <span>5H</span>
      </div>
    </div>`;
}

function metric(label, window, color, nowMs) {
  return `<div class="metric">
    <div class="metric-line">
      <i style="background:${color}"></i><span>${label}</span>
      <strong style="color:${color}">${clamp(window.pct)}%</strong>
    </div>
    <small>${countdown(window.resets_at, nowMs)}</small>
  </div>`;
}

function providerCard(name, data, nowMs) {
  const palette = palettes[name];
  if (!data?.ok || !data.five_h || !data.weekly) {
    return `<section class="provider-card ${palette.key} failed">
      <header><img src="${palette.logo}" alt=""/><b>${name}</b></header>
      <p>${providerMessage(name, data)}</p>
    </section>`;
  }
  const stale = data.live === false || data.reason === "stale"
    || data.five_h.stale === true || data.weekly.stale === true;
  return `<section class="provider-card ${palette.key}${stale ? " stale" : ""}">
    ${ring(name, data.five_h.pct, data.weekly.pct)}
    <div class="details">
      <header><img src="${palette.logo}" alt=""/><b>${name}</b></header>
      ${stale ? '<div class="stale-note">缓存数据 · 等待下次刷新</div>' : ""}
      ${metric("5H", data.five_h, palette.accent, nowMs)}
      ${metric("Weekly", data.weekly, palette.soft, nowMs)}
    </div>
  </section>`;
}

export function renderToHTML(payload, nowMs = Date.now()) {
  return [
    providerCard("Claude", payload?.claude, nowMs),
    providerCard("Codex", payload?.codex, nowMs),
    providerCard("Kimi Code", payload?.kimi, nowMs),
  ].join("");
}

let lastPayload = null;

export function render(payload) {
  lastPayload = payload;
  const root = document.querySelector("#providers");
  if (root) root.innerHTML = renderToHTML(payload);
}

export function rerenderCountdowns() {
  if (lastPayload) render(lastPayload);
}
