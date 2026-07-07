const SHARED_USAGE_DEFAULT = "$HOME/Library/Group Containers/group.dev.lazyfoxy.QuotaWidget/Library/Application Support/usage.json";
const SCRIPT_DIRS = [
  "$HOME/Library/Application Support/Übersicht/widgets/usage-widget",
  "$HOME/Library/Application Support/Übersicht/widgets/usage-widget"
];
const FETCHER_DIRS = SCRIPT_DIRS.map((d) => `"${d}"`).join(" ");
export const command = `/bin/sh -lc 'shared="\${QUOTAWIDGET_SHARED_USAGE:-${SHARED_USAGE_DEFAULT}}"; if [ -f "$shared" ]; then cat "$shared"; exit 0; fi; for d in ${FETCHER_DIRS}; do if [ -f "$d/fetch_usage.py" ]; then exec /usr/bin/python3 "$d/fetch_usage.py"; fi; done; exit 1'`;
export const refreshFrequency = 60000;

const TONE = {
  light: { ink: "#26231F", sub: "#9a9286", track: "rgba(0,0,0,.09)", div: "rgba(0,0,0,.06)" },
  dark: { ink: "#ECEAE6", sub: "#8c887f", track: "rgba(255,255,255,.13)", div: "rgba(255,255,255,.07)" }
};

const PROVIDERS = {
  claude: { name: "Claude", accent: "#D97757", tintL: "#FAF7F3", tintD: "#211F1C" },
  codex: { name: "Codex", accent: "#7B83F5", tintL: "#F6F6FB", tintD: "#1B1B23" },
  kimi: { name: "Kimi Code", accent: "#1478FF", tintL: "#F4F7FC", tintD: "#181C24" },
  deepseek: { name: "DeepSeek", kind: "balance", accent: "#4F6D7A", tintL: "#F3F6F7", tintD: "#1A2024" },
  siliconflow: { name: "SiliconFlow", kind: "balance", accent: "#F56C6C", tintL: "#FDF5F5", tintD: "#241A1A" },
  openrouter: { name: "OpenRouter", kind: "balance", accent: "#8B5CF6", tintL: "#F5F3FD", tintD: "#1E1A2E" }
};

const I18N = {
  zh: {
    cached: "缓存数据 · 等待刷新",
    cachedBalance: "缓存余额 · 等待刷新",
    rateLimited: "请求受限 · 稍后自动重试",
    networkError: "连接失败 · 检查网络或代理",
    noApiKey: "未配置 API 密钥",
    balanceUnavailable: "余额口径异常 · 请到后台核对",
    trendEstimate: "近 {window} 日约可用 {days} 天",
    noTrend: "暂无消耗趋势",
    notSignedIn: "未登录 · 请先在 {CLI} 登录",
    cmdMap: { "Claude": "Claude Code", "Codex": "Codex CLI", "Kimi Code": "Kimi CLI" },
    resetsSoon: "Resets soon"
  },
  en: {
    cached: "Cached · awaiting refresh",
    cachedBalance: "Cached balance · awaiting refresh",
    rateLimited: "Rate limited · retrying soon",
    networkError: "Connection failed · check network or proxy",
    noApiKey: "No API key configured",
    balanceUnavailable: "Balance unavailable · check provider console",
    trendEstimate: "≈ {days} days left ({window}d)",
    noTrend: "No spending trend yet",
    notSignedIn: "Not signed in · Log in via {CLI}",
    cmdMap: { "Claude": "Claude Code", "Codex": "Codex CLI", "Kimi Code": "Kimi CLI" },
    resetsSoon: "Resets soon"
  }
};

function locale() {
  if (window.UW_LOCALE) return window.UW_LOCALE;
  const l = (navigator.language || "zh").toLowerCase();
  return l.startsWith("en") ? "en" : "zh";
}

function hexToRgb(hex) {
  const h = hex.replace("#", "");
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}

function rgbToHex(r, g, b) {
  const f = (x) => Math.round(Math.max(0, Math.min(255, x))).toString(16).padStart(2, "0");
  return "#" + f(r) + f(g) + f(b);
}

function lvl(used) {
  return used >= 90 ? 2 : used >= 70 ? 1 : 0;
}

function emphasis(accent, used, isDark) {
  const level = lvl(used);
  if (level === 0) return accent;
  const [r, g, b] = hexToRgb(accent);
  if (isDark) {
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

function dangerTrack(accent, tone, isDark) {
  return `linear-gradient(90deg,${tone.track} 0 82%,${rgba(accent, isDark ? 0.26 : 0.15)} 82% 100%)`;
}

function sl(label) {
  return label === "Weekly" ? "Wk" : label;
}

function fmtDuration(resetsAt) {
  if (!resetsAt) return null;
  const min = Math.max(0, Math.floor((resetsAt - Date.now() / 1000) / 60));
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

function fmtBalance(amount, currency) {
  const value = Number(amount || 0).toFixed(2);
  const code = String(currency || "").toUpperCase();
  if (code === "CNY") return `¥${value}`;
  if (code === "USD") return `$${value}`;
  return code ? `${value} ${code}` : value;
}

function balanceTrendText(burnRate) {
  const t = I18N[locale()];
  if (!burnRate || burnRate.confidence === "none" || burnRate.estimated_days_left == null) {
    return t.noTrend;
  }
  return t.trendEstimate
    .replace("{window}", String(burnRate.window_days || 7))
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

function usageBarRow(w, pal, tone, isDark) {
  const clamped = Math.min(100, Math.max(0, w.pct));
  const color = emphasis(pal.accent, w.pct, isDark);
  return (
    <div key={w.label} style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <span style={{ width: 46, flex: "none", fontSize: 12, fontWeight: 600, color: tone.ink }}>{sl(w.label)}</span>
      <span style={{ flex: 1, height: 7, borderRadius: 4, overflow: "hidden", position: "relative", background: dangerTrack(pal.accent, tone, isDark) }}>
        <span style={{ position: "absolute", left: 0, top: 0, height: "100%", width: `${clamped}%`, borderRadius: 4, background: pal.accent }} />
      </span>
      <span style={{ width: 38, textAlign: "right", fontSize: 13, fontWeight: 700, color: color }}>{w.pct}%</span>
    </div>
  );
}

function usagePanel(name, glyph, pal, data) {
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const tone = TONE[isDark ? "dark" : "light"];
  const bg = isDark ? pal.tintD : pal.tintL;
  const t = I18N[locale()];

  if (!data || !data.ok) {
    const reason = data && data.reason;
    let msg;
    if (reason === "rate_limited") {
      msg = t.rateLimited;
    } else if (reason === "error") {
      msg = t.networkError;
    } else {
      const cli = t.cmdMap[name] || name;
      msg = t.notSignedIn.replace("{CLI}", cli);
    }
    return (
      <div style={{ padding: "17px 18px", background: bg, color: tone.sub, fontSize: 12 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          {glyph}<strong style={{ color: tone.ink, fontSize: 15 }}>{name}</strong>
        </div>
        <div style={{ marginTop: 8 }}>{msg}</div>
      </div>
    );
  }

  const cached = data.reason === "stale" || data.live === false
    || (data.five_h && data.five_h.stale)
    || (data.weekly && data.weekly.stale);

  const wins = [
    { label: "5H", pct: (data.five_h && data.five_h.pct) || 0, resetsAt: data.five_h && data.five_h.resets_at },
    { label: "Weekly", pct: (data.weekly && data.weekly.pct) || 0, resetsAt: data.weekly && data.weekly.resets_at }
  ];
  const reset = soonestWindow(wins);
  const resetText = reset && fmtDuration(reset.resetsAt) ? `${sl(reset.label)} ${fmtDuration(reset.resetsAt)}` : t.resetsSoon;

  return (
    <div style={{ padding: "17px 18px 16px", display: "flex", flexDirection: "column", gap: 11, background: bg, color: tone.ink }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        {glyph}
        <span style={{ fontSize: 15, fontWeight: 650 }}>{name}</span>
        <span style={{ marginLeft: "auto", fontSize: 10.5, color: tone.sub, whiteSpace: "nowrap", display: "flex", alignItems: "center", gap: 3 }}>
          <span style={{ fontSize: 10, opacity: 0.75 }}>↻</span>{resetText}
        </span>
      </div>
      {cached && <span style={{ fontSize: 9.5, color: tone.sub, marginTop: -4 }}>{t.cached}</span>}
      <div style={{ display: "flex", flexDirection: "column", gap: 9, opacity: cached ? 0.55 : 1 }}>
        {usageBarRow(wins[0], pal, tone, isDark)}
        {usageBarRow(wins[1], pal, tone, isDark)}
      </div>
    </div>
  );
}

function balancePanel(name, glyph, pal, data) {
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const tone = TONE[isDark ? "dark" : "light"];
  const bg = isDark ? pal.tintD : pal.tintL;
  const t = I18N[locale()];

  if (!data || !data.ok) {
    const reason = data && data.reason;
    const msg = reason === "rate_limited"
      ? t.rateLimited
      : reason === "balance_unavailable"
        ? t.balanceUnavailable
        : reason === "error"
          ? t.networkError
          : t.noApiKey;
    return (
      <div style={{ padding: "17px 18px", background: bg, color: tone.sub, fontSize: 12 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          {glyph}<strong style={{ color: tone.ink, fontSize: 15 }}>{name}</strong>
        </div>
        <div style={{ marginTop: 8 }}>{msg}</div>
      </div>
    );
  }

  const cached = data.reason === "stale" || data.live === false;
  const balance = data.balance || {};
  return (
    <div style={{ padding: "17px 18px 16px", display: "flex", flexDirection: "column", gap: 10, background: bg, color: tone.ink }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
        {glyph}
        <span style={{ fontSize: 15, fontWeight: 650 }}>{name}</span>
      </div>
      {cached && <span style={{ fontSize: 9.5, color: tone.sub, marginLeft: 32 }}>{t.cachedBalance}</span>}
      <div style={{ fontSize: 26, fontWeight: 720, color: tone.ink, opacity: cached ? 0.55 : 1 }}>
        {fmtBalance(balance.amount, balance.currency)}
      </div>
      <div style={{ fontSize: 12, color: tone.sub, opacity: cached ? 0.55 : 1 }}>
        {balanceTrendText(data.burn_rate)}
      </div>
    </div>
  );
}

// One uniform icon treatment for all providers (design `.ico`: contain + rounded clip).
const ICON_STYLE = { objectFit: "contain", borderRadius: 7, overflow: "hidden", WebkitMaskImage: "-webkit-radial-gradient(white, black)", flex: "none" };
const claudeGlyph = (
  <img src="/usage-widget/assets/claude-app.png" width="27" height="27" alt="Claude" style={ICON_STYLE} />
);
const codexGlyph = (
  <img src="/usage-widget/assets/codex-app.png" width="27" height="27" alt="Codex" style={ICON_STYLE} />
);
const kimiGlyph = (
  <img src="/usage-widget/assets/kimi-code.png" width="27" height="27" alt="Kimi Code" style={ICON_STYLE} />
);
const deepseekGlyph = (
  <img src="/usage-widget/assets/deepseek.png" width="27" height="27" alt="DeepSeek" style={ICON_STYLE} />
);
const siliconflowGlyph = (
  <img src="/usage-widget/assets/siliconflow.png" width="27" height="27" alt="SiliconFlow" style={ICON_STYLE} />
);
const openrouterGlyph = (
  <img src="/usage-widget/assets/openrouter.png" width="27" height="27" alt="OpenRouter" style={ICON_STYLE} />
);

export const className = `
  left: 40px; top: 40px;
  width: 300px;
  border-radius: 22px; overflow: hidden;
  box-shadow: 0 20px 44px -12px rgba(0,0,0,.6), 0 2px 6px rgba(0,0,0,.3);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
  font-feature-settings: "tnum";
`;

export const render = ({ output }) => {
  let data = {};
  try { data = JSON.parse(output); } catch (e) { data = {}; }
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const divColor = isDark ? "rgba(255,255,255,.07)" : "rgba(0,0,0,.06)";
  return (
    <div>
      {usagePanel("Claude", claudeGlyph, PROVIDERS.claude, data.claude)}
      <div style={{ height: 1, background: divColor }} />
      {usagePanel("Codex", codexGlyph, PROVIDERS.codex, data.codex)}
      <div style={{ height: 1, background: divColor }} />
      {usagePanel("Kimi Code", kimiGlyph, PROVIDERS.kimi, data.kimi)}
      <div style={{ height: 1, background: divColor }} />
      {balancePanel("DeepSeek", deepseekGlyph, PROVIDERS.deepseek, data.deepseek)}
      <div style={{ height: 1, background: divColor }} />
      {balancePanel("SiliconFlow", siliconflowGlyph, PROVIDERS.siliconflow, data.siliconflow)}
      <div style={{ height: 1, background: divColor }} />
      {balancePanel("OpenRouter", openrouterGlyph, PROVIDERS.openrouter, data.openrouter)}
    </div>
  );
};
