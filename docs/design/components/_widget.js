/* Usage Widget — shared tokens, sample data & renderers (single source of truth)
   Exposes window.UW and auto-mounts on DOMContentLoaded. */
window.UW = (function(){

  /* ---------- tokens ---------- */
  const TONE = {
    light:{ ink:'#26231F', sub:'#9a9286', track:'rgba(0,0,0,.09)', div:'rgba(0,0,0,.06)' },
    dark :{ ink:'#ECEAE6', sub:'#8c887f', track:'rgba(255,255,255,.13)', div:'rgba(255,255,255,.07)' }
  };

  /* ---- color math:告急只在品牌色相内加深 (C) + 轨道危险区 (D) ---- */
  function hexRGB(h){ h=h.replace('#',''); return [parseInt(h.slice(0,2),16),parseInt(h.slice(2,4),16),parseInt(h.slice(4,6),16)]; }
  function rgbHex(r,g,b){ const f=x=>Math.round(Math.max(0,Math.min(255,x))).toString(16).padStart(2,'0'); return '#'+f(r)+f(g)+f(b); }
  function rgba(h,a){ const c=hexRGB(h); return 'rgba('+c[0]+','+c[1]+','+c[2]+','+a+')'; }
  function lvl(used){ return used>=90 ? 2 : used>=70 ? 1 : 0; }   /* 0 充足 · 1 注意 · 2 告急 */
  function emph(h, level, theme){                                  /* deepen (light) / brighten (dark) in-hue */
    if(!level) return h;
    const c = hexRGB(h);
    if(theme==='dark'){ const t=[0,.20,.38][level]; return rgbHex(c[0]+(255-c[0])*t, c[1]+(255-c[1])*t, c[2]+(255-c[2])*t); }
    const f=[1,.84,.70][level]; return rgbHex(c[0]*f, c[1]*f, c[2]*f);
  }
  function dangerTrack(accent, theme){                             /* D: brand-tinted cap zone, last 18% */
    const base = TONE[theme].track, zone = rgba(accent, theme==='dark'? .26 : .15);
    return 'linear-gradient(90deg,'+base+' 0 82%,'+zone+' 82% 100%)';
  }
  function style(used, accent, theme){                             /* fill stays brand; emphasis via val + track */
    const l = lvl(used), e = emph(accent, l, theme);
    return { fill:accent, val:e, stroke:e, track:dangerTrack(accent, theme) };
  }
  function meter(used, accent, theme){ return emph(accent, lvl(used), theme); }  /* in-hue emphasis color */

  /* ---------- sample data ---------- */
  const P = [
    { k:'claude', name:'Claude', icon:'../assets/claude-app.png', accent:'#D97757',
      tintL:'#FAF7F3', tintD:'#211F1C',
      windows:[ {label:'5H', used:47, reset:214}, {label:'Weekly', used:91, reset:6480} ] },
    { k:'codex', name:'Codex', icon:'../assets/codex-app.png', accent:'#7B83F5',
      tintL:'#F6F6FB', tintD:'#1B1B23',
      windows:[ {label:'5H', used:4, reset:221}, {label:'Weekly', used:1, reset:9960} ] },
    { k:'kimi', name:'Kimi Code', icon:'../assets/kimi-code.png', accent:'#1478FF',
      tintL:'#F4F7FC', tintD:'#181C24',
      windows:[ {label:'5H', used:1, reset:277}, {label:'Weekly', used:1, reset:9000} ] }
  ];
  const CREDIT = { k:'credit', name:'Credits', glyph:'$', accent:'#1FA37A',
      tintL:'#F2F8F5', tintD:'#171F1B',
      credit:true, used:75, spent:'$37.60', total:'$50.00', remain:'$12.40', runway:'~9d' };

  /* ---------- helpers ---------- */
  function fmt(min){
    if(min < 60) return min + 'm';
    if(min < 1440){ const h=Math.floor(min/60), m=min%60; return h+'h'+(m?(' '+m+'m'):''); }
    const d=Math.floor(min/1440), h=Math.floor((min%1440)/60); return d+'d'+(h?(' '+h+'h'):'');
  }
  function soonest(ws){ return ws.reduce((a,b)=> b.reset<a.reset? b:a); }      /* nearest reset */
  function urgentWin(ws){ return ws.reduce((a,b)=> b.used>a.used? b:a); }      /* most full */
  function sl(l){ return l==='Weekly' ? 'Wk' : l; }                           /* 2-letter quota code */

  function glyph(p, cls){
    cls = cls || 'ico';
    if(p.icon) return '<img class="'+cls+'" src="'+p.icon+'">';
    return '<span class="'+cls+' gl" style="background:'+p.accent+'">'+(p.glyph||'?')+'</span>';
  }

  function ringSVG(p, theme){
    const t = TONE[theme], Co = 238.76, Ci = 169.65;
    const w5 = p.windows[0], ww = p.windows[1];
    const cw = emph(p.accent, lvl(ww.used), theme), c5 = emph(p.accent, lvl(w5.used), theme);
    return '<svg width="84" height="84" viewBox="0 0 88 88" style="transform:rotate(-90deg)">'
     + '<circle cx="44" cy="44" r="38" fill="none" stroke="'+t.track+'" stroke-width="6.5"/>'
     + '<circle cx="44" cy="44" r="38" fill="none" stroke="'+cw+'" stroke-width="6.5" stroke-linecap="round" stroke-dasharray="'+Co+'" stroke-dashoffset="'+(Co*(1-ww.used/100)).toFixed(1)+'"/>'
     + '<circle cx="44" cy="44" r="27" fill="none" stroke="'+t.track+'" stroke-width="6.5"/>'
     + '<circle cx="44" cy="44" r="27" fill="none" stroke="'+c5+'" stroke-width="6.5" stroke-linecap="round" stroke-dasharray="'+Ci+'" stroke-dashoffset="'+(Ci*(1-w5.used/100)).toFixed(1)+'"/>'
     + '</svg>';
  }

  /* ---------- builders ---------- */
  function barRow(w, accent, theme){
    const s = style(w.used, accent, theme);
    return '<div class="brow"><span class="blbl">'+sl(w.label)+'</span>'
      + '<span class="track" style="background:'+s.track+'"><span class="fill" style="width:'+w.used+'%;background:'+s.fill+'"></span></span>'
      + '<span class="bval" style="color:'+s.val+'">'+w.used+'%</span></div>';
  }

  function barPanel(p, theme){                                   /* PRIMARY form */
    const t = TONE[theme], tint = theme==='light'? p.tintL : p.tintD;
    if(p.credit){
      const s = style(p.used, p.accent, theme);
      return '<div class="panel col" style="background:'+tint+';color:'+t.ink+'">'
        + '<div class="hdr">'+glyph(p)+'<span class="name">'+p.name+'</span><span class="cd" style="color:'+t.sub+'">'+p.remain+' left</span></div>'
        + '<div class="bars">'
        +   '<div class="brow"><span class="blbl">Cr</span><span class="track" style="background:'+s.track+'"><span class="fill" style="width:'+p.used+'%;background:'+s.fill+'"></span></span><span class="bval" style="color:'+s.val+'">'+p.used+'%</span></div>'
        +   '<div class="bcap" style="color:'+t.sub+'">'+p.spent+' / '+p.total+' · '+p.runway+' est.</div>'
        + '</div></div>';
    }
    const sc = soonest(p.windows);
    const bars = p.windows.map(w=> barRow(w, p.accent, theme)).join('');
    return '<div class="panel col" style="background:'+tint+';color:'+t.ink+'">'
      + '<div class="hdr">'+glyph(p)+'<span class="name">'+p.name+'</span><span class="cd" style="color:'+t.sub+'"><span class="rr">↻</span>'+sl(sc.label)+' '+fmt(sc.reset)+'</span></div>'
      + '<div class="bars">'+bars+'</div></div>';
  }

  function ringPanel(p, theme){                                  /* ALTERNATE form */
    const t = TONE[theme], tint = theme==='light'? p.tintL : p.tintD;
    const u = urgentWin(p.windows), sc = soonest(p.windows);
    const rows = p.windows.map(w=>{
      const c = meter(w.used, p.accent, theme);
      return '<div class="mrow"><span class="dot" style="background:'+c+'"></span><span class="lbl">'+sl(w.label)+'</span><span class="val" style="color:'+c+'">'+w.used+'%</span></div>';
    }).join('');
    return '<div class="panel" style="background:'+tint+';color:'+t.ink+'">'
      + '<div class="ringwrap">'+ringSVG(p,theme)
      +   '<div class="ringtxt"><span class="pct" style="color:'+meter(u.used,p.accent,theme)+'">'+u.used+'%</span><span class="h5" style="color:'+t.sub+'">'+sl(u.label).toUpperCase()+'</span></div>'
      + '</div>'
      + '<div class="body"><div class="hdr">'+glyph(p)+'<span class="name">'+p.name+'</span><span class="cd" style="color:'+t.sub+'"><span class="rr">↻</span>'+sl(sc.label)+' '+fmt(sc.reset)+'</span></div>'
      + '<div class="rows">'+rows+'</div></div></div>';
  }

  function compactRow(p, theme){                                 /* Direction B */
    const t = TONE[theme], tint = theme==='light'? p.tintL : p.tintD;
    const wins = p.windows.map(w=>{
      const s = style(w.used, p.accent, theme);
      return '<div class="mini"><span class="mlbl" style="color:'+t.sub+'">'+sl(w.label)+'</span>'
        + '<span class="mtrack" style="background:'+s.track+'"><span class="mfill" style="width:'+w.used+'%;background:'+s.fill+'"></span></span>'
        + '<span class="mval" style="color:'+s.val+'">'+w.used+'%</span></div>';
    }).join('');
    return '<div class="striprow" style="background:'+tint+';color:'+t.ink+'">'
      + glyph(p) + '<span class="sname">'+p.name+'</span><div class="wins">'+wins+'</div></div>';
  }

  function touchCell(p){                                         /* Touch Bar */
    const u = urgentWin(p.windows), c = meter(u.used, p.accent, 'dark');
    const bars = p.windows.map(w=>{
      return '<span class="tbar"><i style="width:'+w.used+'%;background:'+p.accent+'"></i></span>';
    }).join('');
    return '<div class="tcell">'+glyph(p,'tico')
      + '<div class="tmid"><span class="tval" style="color:'+c+'">'+u.used+'%</span></div>'
      + '<div class="tmid">'+bars+'</div></div>';
  }

  /* ---------- auto-mount ---------- */
  function fillWidget(el){
    const form = el.dataset.form, theme = el.dataset.theme || 'light';
    el.style.setProperty('--divln', TONE[theme].div);
    const list = (el.dataset.providers === 'credit')
      ? [P[0], CREDIT]
      : (el.dataset.providers === 'all+credit') ? P.concat([CREDIT]) : P;
    if(form==='ring')    el.innerHTML = list.map(p=> ringPanel(p, theme)).join('');
    else if(form==='compact') el.innerHTML = list.map(p=> compactRow(p, theme)).join('');
    else                 el.innerHTML = list.map(p=> barPanel(p, theme)).join('');
  }
  /* ---------- i18n: 默认中文 · 英文系统自动切 ---------- */
  const I18N = {
    zh:{ login:'未登录 · 请先在', loginTail:'登录', cached:'缓存数据 · 等待刷新', resetsPre:'', cmdMap:{ 'Claude':'Claude Code', 'Codex':'Codex CLI', 'Kimi Code':'Kimi CLI', 'Credits':'控制台' } },
    en:{ login:'Not signed in · Log in via', loginTail:'', cached:'Cached · awaiting refresh', resetsPre:'', cmdMap:{ 'Claude':'Claude Code', 'Codex':'Codex CLI', 'Kimi Code':'Kimi CLI', 'Credits':'the console' } }
  };
  function locale(){
    if(window.UW_LOCALE) return window.UW_LOCALE;                 /* manual override */
    const l = (navigator.language || 'zh').toLowerCase();
    return l.startsWith('en') ? 'en' : 'zh';
  }
  function t9n(lang){ return I18N[lang || locale()]; }
  function loginMsg(p, lang){
    const T = t9n(lang), where = (T.cmdMap[p.name] || p.name);
    return T.login + ' ' + where + (T.loginTail ? (' ' + T.loginTail) : '');
  }

  /* states: only two — 'login' (needs auth) | 'cached' (stale, dimmed). normal = no message. */
  function statePanel(p, theme, state, lang){
    const t = TONE[theme], tint = theme==='light'? p.tintL : p.tintD, T = t9n(lang);
    if(state==='login'){
      return '<div class="panel col" style="background:'+tint+';color:'+t.sub+'">'
        + '<div class="hdr">'+glyph(p)+'<span class="name" style="color:'+t.ink+'">'+p.name+'</span></div>'
        + '<div class="msg" style="font-size:12px;line-height:1.45">'+loginMsg(p, lang)+'</div></div>';
    }
    /* cached: real data dimmed + caption */
    const inner = barPanel(p, theme);
    return inner
      .replace('<div class="bars">', '<div class="note" style="color:'+t.sub+';font-size:9.5px;margin-top:-4px;margin-bottom:2px">'+T.cached+'</div><div class="bars" style="opacity:.5">');
  }


  function autoMount(root){
    root = root || document;
    root.querySelectorAll('.widget[data-form]').forEach(fillWidget);
    root.querySelectorAll('.touchbar[data-auto]').forEach(el=>{ el.innerHTML = P.map(touchCell).join(''); });
  }
  if(document.readyState !== 'loading') autoMount();
  else document.addEventListener('DOMContentLoaded', ()=> autoMount());

  return { TONE, meter, style, emph, rgba, P, CREDIT, fmt, soonest, urgentWin, sl, glyph,
           ringSVG, barRow, barPanel, ringPanel, compactRow, touchCell,
           I18N, locale, t9n, loginMsg, statePanel, fillWidget, autoMount };
})();
