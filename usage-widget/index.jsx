const SCRIPT = "$HOME/Library/Application Support/Übersicht/widgets/usage-widget/fetch_usage.py";
export const command = `/usr/bin/python3 "${SCRIPT}"`;
export const refreshFrequency = 60000;

const CL = { accent: "#D97757", soft: "#E3A77F", ink: "#26231F", sub: "#9A9286", track: "rgba(38,35,31,.09)" };
const CX = { accent: "#6676FF", soft: "#A78BFA", ink: "#ECECEC", sub: "#888894", track: "rgba(255,255,255,.10)", gradient: true };
const KM = { accent: "#1478FF", soft: "#252A33", ink: "#17181C", sub: "#737984", track: "rgba(20,24,30,.09)" };

export const className = `
  right: 40px; bottom: 40px;
  width: 300px;
  border-radius: 22px; overflow: hidden;
  box-shadow: 0 20px 44px -12px rgba(0,0,0,.6), 0 2px 6px rgba(0,0,0,.3);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
  font-feature-settings: "tnum";
`;

function fmtCountdown(resetsAt) {
  const sec = Math.max(0, Math.floor(resetsAt - Date.now() / 1000));
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  if (d > 0) return `${d} 天 ${h} 小时后重置`;
  if (h > 0) return `${h} 小时 ${m} 分后重置`;
  return `${m} 分后重置`;
}

function pctFontSize(pct) {
  return pct >= 100 ? 14 : 18;
}

function ring(pal, fivePct, weekPct) {
  const R1 = 38, R2 = 27, C1 = 2 * Math.PI * R1, C2 = 2 * Math.PI * R2;
  const off = (c, p) => c * (1 - Math.min(100, Math.max(0, p)) / 100);
  const accentStroke = pal.gradient ? "url(#codexAccentGradient)" : pal.accent;
  const softStroke = pal.gradient ? "url(#codexSoftGradient)" : pal.soft;
  return (
    <div style={{ width: 88, height: 88, position: "relative", flex: "none" }}>
      <svg width="88" height="88" viewBox="0 0 88 88" style={{ transform: "rotate(-90deg)" }}>
        {pal.gradient && (
          <defs>
            <linearGradient id="codexAccentGradient" x1="12" y1="12" x2="76" y2="76" gradientUnits="userSpaceOnUse">
              <stop offset="0" stopColor="#A98CFF" />
              <stop offset=".48" stopColor="#7284FF" />
              <stop offset="1" stopColor="#394DFF" />
            </linearGradient>
            <linearGradient id="codexSoftGradient" x1="12" y1="12" x2="76" y2="76" gradientUnits="userSpaceOnUse">
              <stop offset="0" stopColor="#C4B5FD" />
              <stop offset="1" stopColor="#7C86E8" />
            </linearGradient>
          </defs>
        )}
        <circle cx="44" cy="44" r={R1} fill="none" stroke={pal.track} strokeWidth="6.5" />
        <circle cx="44" cy="44" r={R1} fill="none" stroke={softStroke} strokeWidth="6.5" strokeLinecap="round" strokeDasharray={C1} strokeDashoffset={off(C1, weekPct)} />
        <circle cx="44" cy="44" r={R2} fill="none" stroke={pal.track} strokeWidth="6.5" />
        <circle cx="44" cy="44" r={R2} fill="none" stroke={accentStroke} strokeWidth="6.5" strokeLinecap="round" strokeDasharray={C2} strokeDashoffset={off(C2, fivePct)} />
      </svg>
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", lineHeight: 1, transform: "translateY(-1px)" }}>
        <span style={{ fontSize: pctFontSize(fivePct), fontWeight: 720, letterSpacing: "-.5px", color: pal.accent }}>{fivePct}%</span>
        <span style={{ fontSize: 8, marginTop: 3, letterSpacing: ".5px", color: pal.sub, fontWeight: 600 }}>5H</span>
      </div>
    </div>
  );
}

function providerMessage(name, data) {
  const reason = data && data.reason;
  if (name === "Kimi Code") {
    if (reason === "expired") return "登录态过期 · 去 Kimi CLI 重新登录";
    if (reason === "no_data") return "未登录 · 先在 Kimi CLI 完成登录";
    return "获取失败 · 可前往 Kimi 控制台查看";
  }
  if (reason === "expired") return "登录态过期 · 去 Claude Code 重新登录";
  return "暂无数据";
}

function panel(name, glyph, pal, bg, data) {
  if (!data || !data.ok) {
    const msg = providerMessage(name, data);
    return (
      <div style={{ padding: "17px 18px", background: bg, color: pal.sub, fontSize: 12 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          {glyph}<strong style={{ color: pal.ink, fontSize: 15 }}>{name}</strong>
        </div>
        <div style={{ marginTop: 8 }}>{msg}</div>
      </div>
    );
  }
  const cached = data.reason === "stale";
  const row = (color, label, pct, resetsAt) => (
    <div style={{ display: "flex", flexDirection: "column", gap: 3 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
        <span style={{ width: 9, height: 9, borderRadius: "50%", background: color, flex: "none" }} />
        <span style={{ fontSize: 12, fontWeight: 600, color: pal.ink }}>{label}</span>
        <span style={{ marginLeft: "auto", fontSize: 13, fontWeight: 700, color: color === pal.accent ? pal.accent : pal.ink }}>{pct}%</span>
      </div>
      <div style={{ fontSize: 10.5, marginLeft: 16, color: pal.sub }}>{fmtCountdown(resetsAt)}</div>
    </div>
  );
  return (
    <div style={{ padding: "17px 18px 16px", display: "flex", alignItems: "center", gap: 17, background: bg, color: pal.ink }}>
      {ring(pal, data.five_h.pct, data.weekly.pct)}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 11 }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>{glyph}<span style={{ fontSize: 15, fontWeight: 650 }}>{name}</span></div>
          {cached && <span style={{ fontSize: 9.5, color: pal.sub, marginLeft: 32 }}>缓存数据 · 等待下次刷新</span>}
        </div>
        {row(pal.accent, "5 小时", data.five_h.pct, data.five_h.resets_at)}
        {row(pal.soft, "本周", data.weekly.pct, data.weekly.resets_at)}
      </div>
    </div>
  );
}

function codexPanel(glyph, pal, bg, data) {
  if (!data || !data.ok) {
    const msg = data && data.reason === "stale" ? "数据较旧" : "暂无数据 · 先使用一次 Codex";
    return (
      <div style={{ padding: "17px 18px", background: bg, color: pal.sub, fontSize: 12 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          {glyph}<strong style={{ color: pal.ink, fontSize: 15 }}>Codex</strong>
        </div>
        <div style={{ marginTop: 8 }}>{msg}</div>
      </div>
    );
  }
  const anyStale = (data.five_h && data.five_h.stale) || (data.weekly && data.weekly.stale);
  const asOfStr = anyStale && data.as_of
    ? (() => { const d = new Date(data.as_of * 1000); return `${String(d.getHours()).padStart(2,"0")}:${String(d.getMinutes()).padStart(2,"0")}`; })()
    : null;
  const row = (baseColor, label, win) => {
    const pctColor = win.stale ? pal.sub : (baseColor === pal.accent ? pal.accent : pal.ink);
    const dotFill = baseColor === pal.accent
      ? "linear-gradient(135deg,#A98CFF,#394DFF)"
      : "linear-gradient(135deg,#C4B5FD,#7C86E8)";
    return (
      <div style={{ display: "flex", flexDirection: "column", gap: 3 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
          <span style={{ width: 9, height: 9, borderRadius: "50%", background: dotFill, flex: "none" }} />
          <span style={{ fontSize: 12, fontWeight: 600, color: pal.ink }}>{label}</span>
          <span style={{ marginLeft: "auto", fontSize: 13, fontWeight: 700, color: pctColor }}>{win.pct}%</span>
        </div>
        <div style={{ fontSize: 10.5, marginLeft: 16, color: pal.sub }}>{fmtCountdown(win.resets_at)}</div>
      </div>
    );
  };
  return (
    <div style={{ padding: "17px 18px 16px", display: "flex", alignItems: "center", gap: 17, background: bg, color: pal.ink }}>
      {ring(pal, data.five_h.pct, data.weekly.pct)}
      <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 11 }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>{glyph}<span style={{ fontSize: 15, fontWeight: 650 }}>Codex</span></div>
          {asOfStr && <span style={{ fontSize: 9.5, color: pal.sub, marginLeft: 32 }}>{"数据截至 " + asOfStr}</span>}
        </div>
        {row(pal.accent, "5 小时", data.five_h)}
        {row(pal.soft, "本周", data.weekly)}
      </div>
    </div>
  );
}

const claudeGlyph = (
  <svg width="24" height="24" viewBox="0 0 24 24" fill="none"><g stroke="#D97757" strokeWidth="2.1" strokeLinecap="round"><path d="M12 3v18M3 12h18M5.6 5.6l12.8 12.8M18.4 5.6L5.6 18.4" /></g></svg>
);
const codexGlyph = (
  <img src="./assets/codex-app.png" width="27" height="27" alt="Codex" style={{ objectFit: "contain", flex: "none" }} />
);
const kimiGlyph = (
  <img src="./assets/kimi-code.png" width="27" height="27" alt="Kimi Code" style={{ objectFit: "contain", borderRadius: 7, flex: "none" }} />
);

export const render = ({ output }) => {
  let data = {};
  try { data = JSON.parse(output); } catch (e) { data = {}; }
  return (
    <div>
      {panel("Claude", claudeGlyph, CL, "linear-gradient(180deg,#FAF9F5,#F0EEE6)", data.claude)}
      <div style={{ height: 1, background: "rgba(0,0,0,.06)" }} />
      {codexPanel(codexGlyph, CX, "linear-gradient(180deg,#17171A,#0E0E10)", data.codex)}
      <div style={{ height: 1, background: "rgba(0,0,0,.08)" }} />
      {panel("Kimi Code", kimiGlyph, KM, "linear-gradient(180deg,#FBFBFC,#F1F3F7)", data.kimi)}
    </div>
  );
};
