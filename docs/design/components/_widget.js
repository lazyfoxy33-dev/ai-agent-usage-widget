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
    { k:'codex', name:'Codex', icon:'../assets/codex-app.png?v=logo-fix', accent:'#7B83F5',
      tintL:'#F6F6FB', tintD:'#1B1B23',
      windows:[ {label:'5H', used:4, reset:221}, {label:'Weekly', used:1, reset:9960} ] },
    { k:'kimi', name:'Kimi Code', icon:'../assets/kimi-code.png', accent:'#1478FF',
      tintL:'#F4F7FC', tintD:'#181C24',
      windows:[ {label:'5H', used:1, reset:277}, {label:'Weekly', used:1, reset:9000} ] }
  ];
  const BALANCE = [
    { k:'deepseek', name:'DeepSeek', icon:'../assets/deepseek.png', glyph:'D', accent:'#4F6D7A',
      tintL:'#F3F6F7', tintD:'#1A2024',
      kind:'balance', amount:'¥45.83', trend:'近 2 日约可用 139 天',
      amountEn:'¥45.83', trendEn:'≈ 139 days left (2d)' },
    { k:'siliconflow', name:'SiliconFlow', icon:'../assets/siliconflow.png', glyph:'S', accent:'#F56C6C',
      tintL:'#FDF5F5', tintD:'#241A1A',
      kind:'balance', state:'no_api_key' },
    { k:'openrouter', name:'OpenRouter', icon:'../assets/openrouter.png', glyph:'O', accent:'#8B5CF6',
      tintL:'#F5F3FD', tintD:'#1E1A2E',
      kind:'balance', amount:'$75.42', trend:'暂无消耗趋势',
      amountEn:'$75.42', trendEn:'No spending trend yet' }
  ];
  const CREDIT = { k:'credit', name:'Credits', glyph:'$', accent:'#1FA37A',
      tintL:'#F2F8F5', tintD:'#171F1B',
      kind:'balance', amount:'$12.40', trend:'~9d est.',
      amountEn:'$12.40', trendEn:'~9d est.' };
  const ALL = P.concat(BALANCE);

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
    if(p.icon) return '<img class="'+cls+'" src="'+p.icon+'" alt="'+p.name+'">';
    return '<span class="'+cls+' gl" style="background:'+p.accent+'">'+(p.glyph||'?')+'</span>';
  }
  function isBalance(p){ return p && p.kind === 'balance'; }

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
    if(isBalance(p)) return balancePanel(p, theme);
    const sc = soonest(p.windows);
    const bars = p.windows.map(w=> barRow(w, p.accent, theme)).join('');
    return '<div class="panel col" style="background:'+tint+';color:'+t.ink+'">'
      + '<div class="hdr">'+glyph(p)+'<span class="name">'+p.name+'</span><span class="cd" style="color:'+t.sub+'"><span class="rr">↻</span>'+sl(sc.label)+' '+fmt(sc.reset)+'</span></div>'
      + '<div class="bars">'+bars+'</div></div>';
  }

  function balanceText(p, lang){
    const T = t9n(lang);
    if(p.state === 'no_api_key') return { amount:T.noApiKey, trend:T.apiKeyHint, missing:true };
    return {
      amount:(lang === 'en' && p.amountEn) ? p.amountEn : p.amount,
      trend:(lang === 'en' && p.trendEn) ? p.trendEn : p.trend,
      missing:false
    };
  }

  function balancePanel(p, theme, lang){
    const t = TONE[theme], tint = theme==='light'? p.tintL : p.tintD;
    const copy = balanceText(p, lang || locale());
    return '<div class="panel col balance-panel" style="background:'+tint+';color:'+t.ink+'">'
      + '<div class="hdr">'+glyph(p)+'<span class="name">'+p.name+'</span><span class="cd" style="color:'+t.sub+'">Cr</span></div>'
      + '<div class="balance-main'+(copy.missing?' missing':'')+'" style="color:'+(copy.missing?t.sub:t.ink)+'">'+copy.amount+'</div>'
      + '<div class="balance-sub" style="color:'+t.sub+'">'+copy.trend+'</div></div>';
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
    if(isBalance(p)){
      const copy = balanceText(p, locale());
      return '<div class="striprow balance-row" style="background:'+tint+';color:'+t.ink+'">'
        + glyph(p) + '<span class="sname">'+p.name+'</span>'
        + '<div class="balance-mini"><span class="mval balance-amt" style="color:'+(copy.missing?t.sub:t.ink)+'">'+copy.amount+'</span>'
        + '<span class="mtrend" style="color:'+t.sub+'">'+copy.trend+'</span></div></div>';
    }
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
    if(isBalance(p)){
      const copy = balanceText(p, 'zh');
      return '<div class="tcell balance-touch" title="'+p.name+'">'
        + glyph(p,'tico')
        + '<div class="tmid"><span class="tname">'+p.name+'</span><span class="tval" style="color:'+(copy.missing?'rgba(255,255,255,.55)':p.accent)+'">'+copy.amount+'</span></div></div>';
    }
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
    const list = (el.dataset.providers === 'balance')
      ? BALANCE
      : (el.dataset.providers === 'credit')
      ? [P[0], CREDIT]
      : (el.dataset.providers === 'all+credit') ? P.concat([CREDIT])
      : (el.dataset.providers === 'all') ? ALL
      : P;
    el.innerHTML = widgetPanels(form, theme, list);
  }

  function widgetPanels(form, theme, providers){
    const list = providers === 'all' ? ALL
      : providers === 'balance' ? BALANCE
      : Array.isArray(providers) ? providers
      : P;
    if(form==='ring')    return list.map(p=> isBalance(p) ? balancePanel(p, theme) : ringPanel(p, theme)).join('');
    else if(form==='compact') return list.map(p=> compactRow(p, theme)).join('');
    else                 return list.map(p=> barPanel(p, theme)).join('');
  }
  /* ---------- i18n: 默认中文 · 英文系统自动切 ---------- */
  const I18N = {
    zh:{ login:'未登录 · 请先在', loginTail:'登录', cached:'缓存数据 · 等待刷新', cachedBalance:'缓存余额 · 等待刷新', noApiKey:'未配置 API 密钥', apiKeyHint:'在账户设置中添加后显示余额', resetsPre:'', cmdMap:{ 'Claude':'Claude Code', 'Codex':'Codex CLI', 'Kimi Code':'Kimi CLI', 'Credits':'控制台', 'DeepSeek':'账户设置', 'SiliconFlow':'账户设置', 'OpenRouter':'账户设置' } },
    en:{ login:'Not signed in · Log in via', loginTail:'', cached:'Cached · awaiting refresh', cachedBalance:'Cached balance · awaiting refresh', noApiKey:'No API key configured', apiKeyHint:'Add a key in Account Settings', resetsPre:'', cmdMap:{ 'Claude':'Claude Code', 'Codex':'Codex CLI', 'Kimi Code':'Kimi CLI', 'Credits':'the console', 'DeepSeek':'Account Settings', 'SiliconFlow':'Account Settings', 'OpenRouter':'Account Settings' } }
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

  /* states: quota = login/cached; balance = no_api_key/cached. normal = no message. */
  function statePanel(p, theme, state, lang){
    const t = TONE[theme], tint = theme==='light'? p.tintL : p.tintD, T = t9n(lang);
    if(isBalance(p) && state==='no_api_key'){
      return '<div class="panel col" style="background:'+tint+';color:'+t.sub+'">'
        + '<div class="hdr">'+glyph(p)+'<span class="name" style="color:'+t.ink+'">'+p.name+'</span></div>'
        + '<div class="msg" style="font-size:12px;line-height:1.45">'+T.noApiKey+' · '+T.apiKeyHint+'</div></div>';
    }
    if(state==='login'){
      return '<div class="panel col" style="background:'+tint+';color:'+t.sub+'">'
        + '<div class="hdr">'+glyph(p)+'<span class="name" style="color:'+t.ink+'">'+p.name+'</span></div>'
        + '<div class="msg" style="font-size:12px;line-height:1.45">'+loginMsg(p, lang)+'</div></div>';
    }
    /* cached: real data dimmed + caption */
    const inner = barPanel(p, theme);
    if(isBalance(p)){
      return inner
        .replace('<div class="balance-main', '<div class="note" style="color:'+t.sub+';font-size:9.5px;margin-top:-4px;margin-bottom:2px">'+T.cachedBalance+'</div><div class="balance-main')
        .replace('class="balance-main', 'class="balance-main stale')
        .replace('class="balance-sub"', 'class="balance-sub stale"');
    }
    return inner
      .replace('<div class="bars">', '<div class="note" style="color:'+t.sub+';font-size:9.5px;margin-top:-4px;margin-bottom:2px">'+T.cached+'</div><div class="bars" style="opacity:.5">');
  }


  function autoMount(root){
    root = root || document;
    root.querySelectorAll('.widget[data-form]').forEach(fillWidget);
    root.querySelectorAll('.touchbar[data-auto]').forEach(el=>{
      const list = el.dataset.providers === 'all' ? ALL : P;
      el.innerHTML = list.map(touchCell).join('');
    });
  }
  if(document.readyState !== 'loading') autoMount();
  else document.addEventListener('DOMContentLoaded', ()=> autoMount());

  return { TONE, meter, style, emph, rgba, P, BALANCE, CREDIT, ALL, fmt, soonest, urgentWin, sl, glyph,
           ringSVG, barRow, barPanel, balancePanel, ringPanel, compactRow, touchCell, widgetPanels,
           I18N, locale, t9n, loginMsg, statePanel, fillWidget, autoMount };
})();
