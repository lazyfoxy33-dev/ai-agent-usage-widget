const TONE = {
  light: { ink: "#26231F", sub: "#9a9286", track: "rgba(0,0,0,.09)", div: "rgba(0,0,0,.06)" },
  dark: { ink: "#ECEAE6", sub: "#8c887f", track: "rgba(255,255,255,.13)", div: "rgba(255,255,255,.07)" }
};

const PROVIDERS = {
  Claude: {
    key: "claude",
    name: "Claude",
    accent: "#D97757",
    tintL: "#FAF7F3",
    tintD: "#211F1C",
    logo: "assets/claude.svg"
  },
  Codex: {
    key: "codex",
    name: "Codex",
    accent: "#7B83F5",
    tintL: "#F6F6FB",
    tintD: "#1B1B23",
    logo: "assets/codex-app.png"
  },
  "Kimi Code": {
    key: "kimi",
    name: "Kimi Code",
    accent: "#1478FF",
    tintL: "#F4F7FC",
    tintD: "#181C24",
    logo: "assets/kimi-code.png"
  },
  DeepSeek: {
    key: "deepseek",
    name: "DeepSeek",
    kind: "balance",
    accent: "#4F6D7A",
    tintL: "#F3F6F7",
    tintD: "#1A2024",
    logo: "assets/deepseek.png"
  },
  SiliconFlow: {
    key: "siliconflow",
    name: "SiliconFlow",
    kind: "balance",
    accent: "#F56C6C",
    tintL: "#FDF5F5",
    tintD: "#241A1A",
    logo: "assets/siliconflow.png"
  },
  OpenRouter: {
    key: "openrouter",
    name: "OpenRouter",
    kind: "balance",
    accent: "#8B5CF6",
    tintL: "#F5F3FD",
    tintD: "#1E1A2E",
    logo: "assets/openrouter.png"
  }
};

const I18N = {
  zh: {
    cached: "缓存数据 · 等待刷新",
    cachedBalance: "缓存余额 · 等待刷新",
    rateLimited: "请求受限 · 稍后自动重试",
    networkError: "连接失败 · 检查网络或代理",
    notSignedIn: "未登录 · 请先在 {CLI} 登录",
    noApiKey: "未配置 API 密钥",
    trendEstimate: "近 {window} 日约可用 {days} 天",
    noTrend: "暂无消耗趋势",
    cmdMap: { Claude: "Claude Code", Codex: "Codex CLI", "Kimi Code": "Kimi CLI" },
    resetsSoon: "Resets soon"
  },
  en: {
    cached: "Cached · awaiting refresh",
    cachedBalance: "Cached balance · awaiting refresh",
    rateLimited: "Rate limited · retrying soon",
    networkError: "Connection failed · check network or proxy",
    notSignedIn: "Not signed in · Log in via {CLI}",
    noApiKey: "No API key configured",
    trendEstimate: "≈ {days} days left ({window}d)",
    noTrend: "No spending trend yet",
    cmdMap: { Claude: "Claude Code", Codex: "Codex CLI", "Kimi Code": "Kimi CLI" },
    resetsSoon: "Resets soon"
  }
};

function locale() {
  if (typeof window !== "undefined" && window.UW_LOCALE) return window.UW_LOCALE;
  const l = (typeof navigator !== "undefined" && navigator.language) || "zh";
  return l.toLowerCase().startsWith("en") ? "en" : "zh";
}

function isDark() {
  if (typeof window === "undefined" || !window.matchMedia) return false;
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

function hexToRgb(hex) {
  const h = hex.replace("#", "");
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}

function rgbToHex(r, g, b) {
  const f = (x) => Math.round(Math.max(0, Math.min(255, x))).toString(16).padStart(2, "0");
  return "#" + f(r) + f(g) + f(b);
}

function clampPct(value) {
  return Math.max(0, Math.min(100, Number(value) || 0));
}

function lvl(used) {
  return used >= 90 ? 2 : used >= 70 ? 1 : 0;
}

function emphasis(accent, used, dark) {
  const level = lvl(used);
  if (level === 0) return accent;
  const [r, g, b] = hexToRgb(accent);
  if (dark) {
    const t = [0, 0.20, 0.38][level];
    return rgbToHex(r + (255 - r) * t, g + (255 - g) * t, b + (255 - b) * t);
  }
  const f = [1, 0.84, 0.70][level];
  return rgbToHex(r * f, g * f, b * f);
}

function rgba(hex, alpha) {
  const [r, g, b] = hexToRgb(hex);
  return `rgba(${r},${g},${b},${alpha})`;
}

function dangerTrack(accent, tone, dark) {
  return `linear-gradient(90deg,${tone.track} 0 82%,${rgba(accent, dark ? 0.26 : 0.15)} 82% 100%)`;
}

function sl(label) {
  return label === "Weekly" ? "Wk" : label;
}

export function countdown(resetsAt, nowMs = Date.now()) {
  if (!resetsAt) return null;
  const sec = Math.max(0, Math.floor(Number(resetsAt) - nowMs / 1000));
  const min = Math.floor(sec / 60);
  if (min < 1) return null;
  if (min < 60) return `${min}m`;
  if (min < 1440) {
    const h = Math.floor(min / 60);
    const m = min % 60;
    return `${h}h` + (m ? ` ${m}m` : "");
  }
  const d = Math.floor(min / 1440);
  const h = Math.floor((min % 1440) / 60);
  return `${d}d` + (h ? ` ${h}h` : "");
}

export function providerMessage(name, data = {}) {
  const lang = locale();
  const t = I18N[lang];
  if (data.reason === "rate_limited") return t.rateLimited;
  if (data.reason === "error") return t.networkError;
  const isBalance = PROVIDERS[name]?.kind === "balance" || data.kind === "balance";
  if (isBalance) return t.noApiKey;
  const cli = t.cmdMap[name] || name;
  return t.notSignedIn.replace("{CLI}", cli);
}

function fmtBalance(amount, currency) {
  const value = Number(amount).toFixed(2);
  if (currency === "CNY") return `¥${value}`;
  if (currency === "USD") return `$${value}`;
  return `${value} ${currency}`;
}

function balanceTrendText(burnRate) {
  const lang = locale();
  const t = I18N[lang];
  if (!burnRate || burnRate.confidence === "none") return t.noTrend;
  if (burnRate.estimated_days_left == null) return t.noTrend;
  return t.trendEstimate
    .replace("{window}", String(burnRate.window_days ?? 7))
    .replace("{days}", String(burnRate.estimated_days_left));
}

function soonestWindow(wins) {
  return wins.reduce((best, win) => {
    if (!best) return win;
    if (!win.resetsAt) return best;
    if (!best.resetsAt) return win;
    return win.resetsAt < best.resetsAt ? win : best;
  }, null);
}

function usageBarRow(w, pal, tone, dark) {
  const clamped = clampPct(w.pct);
  const color = emphasis(pal.accent, w.pct, dark);
  return `
    <div class="row usage-bar">
      <span class="lbl" style="color:${tone.ink}">${sl(w.label)}</span>
      <span class="bar-track" style="background:${dangerTrack(pal.accent, tone, dark)}">
        <span class="bar-fill" style="width:${clamped}%;background:${pal.accent}"></span>
      </span>
      <span class="val" style="color:${color}">${w.pct}%</span>
    </div>`;
}

function providerCard(name, data, nowMs) {
  const pal = PROVIDERS[name];
  const dark = isDark();
  const tone = TONE[dark ? "dark" : "light"];
  const bg = dark ? pal.tintD : pal.tintL;
  const t = I18N[locale()];

  if (!data?.ok) {
    return `
      <section class="provider-card ${pal.key} failed" style="--divln:${tone.div};background:${bg};color:${tone.sub}">
        <header style="color:${tone.ink}">
          <img src="${pal.logo}" alt=""/>
          <b>${pal.name}</b>
        </header>
        <p>${providerMessage(name, data)}</p>
      </section>`;
  }

  const wins = [
    { label: "5H", pct: clampPct(data.five_h?.pct), resetsAt: data.five_h?.resets_at },
    { label: "Weekly", pct: clampPct(data.weekly?.pct), resetsAt: data.weekly?.resets_at }
  ];
  const reset = soonestWindow(wins);
  const resetText = reset && countdown(reset.resetsAt, nowMs)
    ? `${sl(reset.label)} ${countdown(reset.resetsAt, nowMs)}`
    : t.resetsSoon;

  const cached = data.live === false || data.reason === "stale"
    || data.five_h?.stale === true || data.weekly?.stale === true;

  return `
    <section class="provider-card ${pal.key}${cached ? " stale" : ""}" style="--divln:${tone.div};background:${bg};color:${tone.ink}">
      <div class="details">
        <header>
          <img src="${pal.logo}" alt=""/>
          <b>${pal.name}</b>
          <span class="reset" style="color:${tone.sub}">↻ ${resetText}</span>
        </header>
        ${cached ? `<div class="cached-note" style="color:${tone.sub}">${t.cached}</div>` : ""}
        <div class="rows" style="opacity:${cached ? 0.55 : 1}">
          ${usageBarRow(wins[0], pal, tone, dark)}
          ${usageBarRow(wins[1], pal, tone, dark)}
        </div>
      </div>
    </section>`;
}

function balanceCard(name, data) {
  const pal = PROVIDERS[name];
  const dark = isDark();
  const tone = TONE[dark ? "dark" : "light"];
  const bg = dark ? pal.tintD : pal.tintL;
  const t = I18N[locale()];

  if (!data?.ok) {
    return `
      <section class="provider-card ${pal.key} failed" style="--divln:${tone.div};background:${bg};color:${tone.sub}">
        <header style="color:${tone.ink}">
          <img src="${pal.logo}" alt=""/>
          <b>${pal.name}</b>
        </header>
        <p>${providerMessage(name, data)}</p>
      </section>`;
  }

  const cached = data.live === false || data.reason === "stale";
  const balance = data.balance || {};
  const burnRate = data.burn_rate || {};
  const trend = balanceTrendText(burnRate);

  return `
    <section class="provider-card ${pal.key}${cached ? " stale" : ""}" style="--divln:${tone.div};background:${bg};color:${tone.ink}">
      <div class="details" style="gap:11px">
        <header>
          <img src="${pal.logo}" alt=""/>
          <b>${pal.name}</b>
        </header>
        <div style="font-size:26px;font-weight:720;letter-spacing:-.5px;color:${tone.ink}">
          ${fmtBalance(balance.amount, balance.currency)}
        </div>
        ${cached ? `<div class="cached-note" style="color:${tone.sub}">${t.cachedBalance}</div>` : ""}
        <div style="font-size:12px;color:${tone.sub};opacity:${cached ? 0.55 : 1}">${trend}</div>
      </div>
    </section>`;
}

export function renderToHTML(payload, nowMs = Date.now()) {
  const card = (name) => {
    const data = payload?.[PROVIDERS[name].key];
    return PROVIDERS[name].kind === "balance"
      ? balanceCard(name, data)
      : providerCard(name, data, nowMs);
  };
  return [
    card("Claude"),
    card("Codex"),
    card("Kimi Code"),
    card("DeepSeek"),
    card("SiliconFlow"),
    card("OpenRouter")
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
