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
  }
};

const I18N = {
  zh: {
    cached: "缓存数据 · 等待刷新",
    rateLimited: "请求受限 · 稍后自动重试",
    notSignedIn: "未登录 · 请先在 {CLI} 登录",
    cmdMap: { Claude: "Claude Code", Codex: "Codex CLI", "Kimi Code": "Kimi CLI" },
    resetsSoon: "Resets soon"
  },
  en: {
    cached: "Cached · awaiting refresh",
    rateLimited: "Rate limited · retrying soon",
    notSignedIn: "Not signed in · Log in via {CLI}",
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
  const cli = t.cmdMap[name] || name;
  return t.notSignedIn.replace("{CLI}", cli);
}

function pctFontSize(pct) {
  return pct >= 100 ? 14 : 18;
}

function ring(pal, tone, fivePct, weekPct, dark) {
  const R1 = 38, R2 = 27;
  const C1 = 2 * Math.PI * R1;
  const C2 = 2 * Math.PI * R2;
  const off = (c, p) => c * (1 - clampPct(p) / 100);
  const cWeek = emphasis(pal.accent, weekPct, dark);
  const cFive = emphasis(pal.accent, fivePct, dark);
  const urgent = fivePct >= weekPct ? { pct: fivePct, label: "5H" } : { pct: weekPct, label: "Wk" };
  return `
    <div class="ring">
      <svg viewBox="0 0 88 88" aria-hidden="true">
        <circle class="track" cx="44" cy="44" r="38" stroke="${tone.track}"/>
        <circle class="progress" cx="44" cy="44" r="38" stroke="${cWeek}"
          stroke-dasharray="${C1}" stroke-dashoffset="${off(C1, weekPct)}"/>
        <circle class="track" cx="44" cy="44" r="27" stroke="${tone.track}"/>
        <circle class="progress" cx="44" cy="44" r="27" stroke="${cFive}"
          stroke-dasharray="${C2}" stroke-dashoffset="${off(C2, fivePct)}"/>
      </svg>
      <div class="ring-value">
        <strong style="font-size:${pctFontSize(urgent.pct)}px;color:${emphasis(pal.accent, urgent.pct, dark)}">${urgent.pct}%</strong>
        <span style="color:${tone.sub}">${sl(urgent.label).toUpperCase()}</span>
      </div>
    </div>`;
}

function row(w, accent, tone, dark) {
  const color = emphasis(accent, w.pct, dark);
  return `
    <div class="row">
      <span class="dot" style="background:${color}"></span>
      <span class="lbl" style="color:${tone.ink}">${sl(w.label)}</span>
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
  const soonest = wins.slice().sort((a, b) => (a.resetsAt || Infinity) - (b.resetsAt || Infinity))[0];
  const dur = countdown(soonest?.resetsAt, nowMs) || t.resetsSoon;

  const cached = data.live === false || data.reason === "stale"
    || data.five_h?.stale === true || data.weekly?.stale === true;

  return `
    <section class="provider-card ${pal.key}${cached ? " stale" : ""}" style="--divln:${tone.div};background:${bg};color:${tone.ink}">
      <div class="ring-wrap" style="opacity:${cached ? 0.55 : 1}">
        ${ring(pal, tone, wins[0].pct, wins[1].pct, dark)}
      </div>
      <div class="details">
        <header>
          <img src="${pal.logo}" alt=""/>
          <b>${pal.name}</b>
          <span class="countdown" style="color:${tone.sub}">
            <span class="rr">↻</span>${sl(soonest.label)} ${dur}
          </span>
        </header>
        ${cached ? `<div class="cached-note" style="color:${tone.sub}">${t.cached}</div>` : ""}
        <div class="rows" style="opacity:${cached ? 0.55 : 1}">
          ${row(wins[0], pal.accent, tone, dark)}
          ${row(wins[1], pal.accent, tone, dark)}
        </div>
      </div>
    </section>`;
}

export function renderToHTML(payload, nowMs = Date.now()) {
  return [
    providerCard("Claude", payload?.claude, nowMs),
    providerCard("Codex", payload?.codex, nowMs),
    providerCard("Kimi Code", payload?.kimi, nowMs)
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
