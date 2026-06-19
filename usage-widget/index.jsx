const SCRIPT = "$HOME/Library/Application Support/Übersicht/widgets/usage-widget/fetch_usage.py";
export const command = `/usr/bin/python3 "${SCRIPT}"`;
export const refreshFrequency = 60000;

const TONE = {
  light: { ink: "#26231F", sub: "#9a9286", track: "rgba(0,0,0,.09)", div: "rgba(0,0,0,.06)" },
  dark: { ink: "#ECEAE6", sub: "#8c887f", track: "rgba(255,255,255,.13)", div: "rgba(255,255,255,.07)" }
};

const PROVIDERS = {
  claude: { name: "Claude", accent: "#D97757", tintL: "#FAF7F3", tintD: "#211F1C" },
  codex: { name: "Codex", accent: "#7B83F5", tintL: "#F6F6FB", tintD: "#1B1B23" },
  kimi: { name: "Kimi Code", accent: "#1478FF", tintL: "#F4F7FC", tintD: "#181C24" }
};

const I18N = {
  zh: {
    cached: "缓存数据 · 等待刷新",
    rateLimited: "请求受限 · 稍后自动重试",
    notSignedIn: "未登录 · 请先在 {CLI} 登录",
    cmdMap: { "Claude": "Claude Code", "Codex": "Codex CLI", "Kimi Code": "Kimi CLI" },
    resetsSoon: "Resets soon"
  },
  en: {
    cached: "Cached · awaiting refresh",
    rateLimited: "Rate limited · retrying soon",
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

function pctFontSize(pct) {
  return pct >= 100 ? 14 : 18;
}

function ring(pal, tone, fivePct, weekPct, isDark) {
  const R1 = 38, R2 = 27, C1 = 2 * Math.PI * R1, C2 = 2 * Math.PI * R2;
  const off = (c, p) => c * (1 - Math.min(100, Math.max(0, p)) / 100);
  const cWeek = emphasis(pal.accent, weekPct, isDark);
  const cFive = emphasis(pal.accent, fivePct, isDark);
  const urgent = fivePct >= weekPct ? { pct: fivePct, label: "5H" } : { pct: weekPct, label: "Wk" };
  return (
    <div style={{ width: 88, height: 88, position: "relative", flex: "none" }}>
      <svg width="88" height="88" viewBox="0 0 88 88" style={{ transform: "rotate(-90deg)" }}>
        <circle cx="44" cy="44" r={R1} fill="none" stroke={tone.track} strokeWidth="6.5" />
        <circle cx="44" cy="44" r={R1} fill="none" stroke={cWeek} strokeWidth="6.5" strokeLinecap="round" strokeDasharray={C1} strokeDashoffset={off(C1, weekPct)} />
        <circle cx="44" cy="44" r={R2} fill="none" stroke={tone.track} strokeWidth="6.5" />
        <circle cx="44" cy="44" r={R2} fill="none" stroke={cFive} strokeWidth="6.5" strokeLinecap="round" strokeDasharray={C2} strokeDashoffset={off(C2, fivePct)} />
      </svg>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", lineHeight: 1, transform: "translateY(-1px)" }}>
        <span style={{ fontSize: pctFontSize(urgent.pct), fontWeight: 720, letterSpacing: "-.5px", color: emphasis(pal.accent, urgent.pct, isDark) }}>{urgent.pct}%</span>
        <span style={{ fontSize: 8, marginTop: 3, letterSpacing: ".5px", color: tone.sub, fontWeight: 600 }}>{sl(urgent.label).toUpperCase()}</span>
      </div>
    </div>
  );
}

function panel(name, glyph, pal, data) {
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const tone = TONE[isDark ? "dark" : "light"];
  const bg = isDark ? pal.tintD : pal.tintL;
  const t = I18N[locale()];

  if (!data || !data.ok) {
    const reason = data && data.reason;
    let msg;
    if (reason === "rate_limited") {
      msg = t.rateLimited;
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
  const row = (w) => {
    const color = emphasis(pal.accent, w.pct, isDark);
    const dur = fmtDuration(w.resetsAt);
    return (
      <div key={w.label} style={{ display: "flex", alignItems: "center", gap: 7 }}>
        <span style={{ width: 9, height: 9, borderRadius: "50%", background: color, flex: "none" }} />
        <span style={{ fontSize: 12, fontWeight: 600, color: tone.ink }}>{sl(w.label)}</span>
        <span style={{ marginLeft: "auto", fontSize: 10.5, color: tone.sub, whiteSpace: "nowrap", display: "flex", alignItems: "center", gap: 3 }}>
          <span style={{ fontSize: 10, opacity: 0.75 }}>↻</span>{dur || t.resetsSoon}
        </span>
        <span style={{ marginLeft: 8, fontSize: 13, fontWeight: 700, color: color, minWidth: 34, textAlign: "right" }}>{w.pct}%</span>
      </div>
    );
  };

  return (
    <div style={{ padding: "17px 18px 16px", display: "flex", alignItems: "center", gap: 17, background: bg, color: tone.ink }}>
      <div style={{ opacity: cached ? 0.55 : 1 }}>{ring(pal, tone, wins[0].pct, wins[1].pct, isDark)}</div>
      <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 11 }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            {glyph}
            <span style={{ fontSize: 15, fontWeight: 650 }}>{name}</span>
          </div>
          {cached && <span style={{ fontSize: 9.5, color: tone.sub, marginLeft: 32 }}>{t.cached}</span>}
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 9, opacity: cached ? 0.55 : 1 }}>
          {row(wins[0])}
          {row(wins[1])}
        </div>
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
      {panel("Claude", claudeGlyph, PROVIDERS.claude, data.claude)}
      <div style={{ height: 1, background: divColor }} />
      {panel("Codex", codexGlyph, PROVIDERS.codex, data.codex)}
      <div style={{ height: 1, background: divColor }} />
      {panel("Kimi Code", kimiGlyph, PROVIDERS.kimi, data.kimi)}
    </div>
  );
};
