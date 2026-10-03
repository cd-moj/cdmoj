// shared/staff-alert.js — alerta GLOBAL da organização do contest, em QUALQUER página: juiz (.judge),
// juiz-chefe (.cjudge), admin (.admin) e .mon. Banner fixo no topo + som + contador no título da aba +
// (opcional) notificação do sistema, para:
//   💬 clarification sem resposta (todos esses papéis)
//   ⚖ veredicto esperando o SEU voto (MANUAL_VERDICT; juiz, chefe, admin)
//   ⚠ conflito de veredicto (chefe e admin)
// Pedido do juiz-chefe do TCP 2026 (03/10/2026): clarification nova só aparecia p/ quem estava na aba de
// clarifications. Substitui o chief-alert.js (que vira um apelido deste módulo).
//
// NÃO ONERAR O SERVIDOR: UMA aba por navegador faz o poll (a LÍDER, eleita por Web Locks) e conta às
// outras pelo BroadcastChannel — dez abas abertas = um poll. Ritmo: 8–12 s com alguma aba do contest
// VISÍVEL, 30–40 s com todas ocultas (o som existe p/ chamar quem não está olhando, então não para).
// A rota (/contest/staff-alerts) só devolve contagens e sai pelo porteiro (~1 ms, sem fork). Sem Web Locks
// ou BroadcastChannel, cada aba pola sozinha (o comportamento de antes). 401/403 PARAM o poll.
//
// SOM: o navegador só toca áudio depois de um gesto na PÁGINA. O contexto de áudio é criado/retomado no
// 1º clique/tecla; enquanto não houver gesto, o banner mostra "🔇 ativar som". Mudo por contest no
// localStorage. Lembrete a cada 2 min enquanto houver pendência (decisão do Ribas, 03/10/2026).
// Toca UMA vez por navegador: a aba visível, ou a líder quando nenhuma está visível.
import { apiGet } from '/shared/api.js';
import { T } from '/shared/i18n.js';

let _started = false;
let _poke = null;

const REMIND_MS = 120000;

export function startStaffAlert(contest, st, opts = {}) {
  if (_started || (opts && opts.alerts === false)) return;
  if (!contest || contest === 'treino') return;          // treino não tem fila de revisão nem clarification
  if (!st || !st.logged_in) return;
  const mon = st.is_mon === true || /\.mon$/.test(st.login || '');
  const voter = !!(st.is_judge || st.is_admin || st.is_chief);
  if (!voter && !mon) return;                            // a trava real é da API; aqui é só não poluir
  _started = true;

  const enc = encodeURIComponent;
  const G = { contest, auth: true };
  const KEY = 'moj-staff-alert-' + contest;
  const LS_MUTE = 'moj_alert_mute_' + contest;
  const here = location.pathname.replace(/\/+$/, '');
  const ls = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch { /* sem storage */ } },
  };
  const canNotify = () => typeof Notification !== 'undefined';

  // ---- estado ------------------------------------------------------------------------------------
  let snap = null;            // a última resposta da rota (desta aba ou da líder)
  let leader = false;         // esta aba faz o poll?
  let stopped = false;        // 401/403: para tudo
  let lastPoll = 0;
  let remindAt = 0;
  let visAt = 0;              // último "tem aba visível" que a líder ouviu
  const coord = typeof BroadcastChannel !== 'undefined' && navigator.locks && typeof navigator.locks.request === 'function';
  const ch = coord ? new BroadcastChannel(KEY) : null;

  // ---- som ---------------------------------------------------------------------------------------
  let actx = null;
  const audioReady = () => !!(actx && actx.state === 'running');
  // o banner só se refaz DEPOIS do clique (setTimeout): refazer no pointerdown trocaria o botão debaixo do
  // dedo e o clique que desbloqueou o som se perderia
  const unlock = () => {
    if (audioReady()) return;
    try {
      const A = window.AudioContext || window.webkitAudioContext;
      if (!A) return;
      if (!actx) actx = new A();
      if (actx.state !== 'running' && actx.resume) actx.resume().then(() => setTimeout(render, 350), () => {});
    } catch { /* sem áudio */ }
  };
  ['pointerdown', 'keydown'].forEach((ev) => document.addEventListener(ev, unlock, { capture: true, passive: true }));
  const muted = () => ls.get(LS_MUTE) === '1';
  // tons por tipo: clarification = dois toques subindo; voto = arpejo; conflito = alarme (o de sempre)
  const TONES = {
    clar:     { type: 'sine',   notes: [[660, 0, 0.16], [990, 0.18, 0.22]] },
    review:   { type: 'sine',   notes: [[523, 0, 0.12], [659, 0.13, 0.12], [784, 0.26, 0.2]] },
    conflict: { type: 'square', notes: [[880, 0, 0.2], [660, 0.22, 0.25], [880, 0.5, 0.2], [660, 0.72, 0.25]] },
  };
  const play = (kind) => {
    if (muted()) return;
    try {
      if (audioReady()) {
        const tone = TONES[kind] || TONES.clar;
        const t0 = actx.currentTime + 0.02;
        tone.notes.forEach(([f, at, dur]) => {
          const o = actx.createOscillator(); const g = actx.createGain();
          o.type = tone.type; o.frequency.value = f;
          g.gain.setValueAtTime(0.0001, t0 + at);
          g.gain.exponentialRampToValueAtTime(tone.type === 'square' ? 0.08 : 0.16, t0 + at + 0.02);
          g.gain.exponentialRampToValueAtTime(0.0001, t0 + at + dur);
          o.connect(g); g.connect(actx.destination); o.start(t0 + at); o.stop(t0 + at + dur + 0.02);
        });
      }
    } catch { /* sem áudio */ }
    try { navigator.vibrate && navigator.vibrate(kind === 'conflict' ? [200, 100, 200] : [120]); } catch { /* sem vibração */ }
  };

  // ---- o que mostrar -----------------------------------------------------------------------------
  const nums = (s) => {
    const c = (s && s.clar) || {}; const r = (s && s.review) || {};
    return { open: c.open | 0, unc: c.unclaimed | 0, clast: c.last | 0,
             mine: r.mine_todo | 0, mlast: r.mine_last | 0, conf: r.conflicts | 0 };
  };
  const pending = (n) => n.unc + n.mine + n.conf;
  // eventos = o que CHEGOU desde a fotografia anterior (a chegada, não a contagem: uma resolvida e uma nova
  // entre dois polls deixam o número igual)
  const eventsOf = (prev, cur) => {
    const ev = [];
    if (!prev) return ev;
    const a = nums(prev), b = nums(cur);
    if (b.conf > a.conf) ev.push('conflict');
    if (b.unc > 0 && (b.clast > a.clast || b.unc > a.unc)) ev.push('clar');
    if (b.mine > 0 && (b.mlast > a.mlast || b.mine > a.mine)) ev.push('review');
    return ev;
  };
  const worst = (n) => (n.conf ? 'conflict' : n.unc ? 'clar' : n.mine ? 'review' : null);

  const goConflicts = () => {
    if (here.endsWith('/contest/chief')) { location.hash = '#conf'; window.dispatchEvent(new CustomEvent('moj:show-conflicts')); }
    else location.href = '/contest/chief/?c=' + enc(contest) + '#conf';
  };
  const go = (path) => () => { location.href = path + '?c=' + enc(contest); };

  function injectCss() {
    if (document.getElementById('mojStaffAlertCss')) return;
    const s = document.createElement('style'); s.id = 'mojStaffAlertCss';
    // sticky no TOPO do body (não fixed): a faixa empurra a página em vez de cobrir o cabeçalho/nav
    s.textContent = '#mojStaffAlert{position:sticky;top:0;left:0;right:0;z-index:9999;display:none;flex-wrap:wrap;'
      + 'gap:.4rem;align-items:center;justify-content:center;padding:.4rem .8rem;background:#1f2430;color:#fff;'
      + 'font-weight:700;box-shadow:0 2px 10px rgba(0,0,0,.35)}'
      + '#mojStaffAlert.show{display:flex}'
      + '#mojStaffAlert .sa-item{border:0;border-radius:999px;padding:.35rem .9rem;color:#fff;font:inherit;cursor:pointer}'
      + '#mojStaffAlert .sa-conflict{background:#c0392b}#mojStaffAlert .sa-clar{background:#b35c00}'
      + '#mojStaffAlert .sa-review{background:#4a3fb5}#mojStaffAlert .sa-info{background:#4b5563;font-weight:600}'
      + '#mojStaffAlert .sa-new{animation:mojSaPulse 1s ease-in-out 6}'
      + '#mojStaffAlert .sa-ctl{background:transparent;border:1px solid rgba(255,255,255,.5);border-radius:999px;'
      + 'color:#fff;font:inherit;font-weight:600;padding:.25rem .7rem;cursor:pointer}'
      + '@keyframes mojSaPulse{0%,100%{filter:none}50%{filter:brightness(1.35)}}'
      + '@media (prefers-reduced-motion:reduce){#mojStaffAlert .sa-new{animation:none}}'
      + '@media print{#mojStaffAlert{display:none!important}}';
    document.head.appendChild(s);
  }
  function bar() {
    let b = document.getElementById('mojStaffAlert');
    if (!b) {
      injectCss();
      b = document.createElement('div'); b.id = 'mojStaffAlert';
      b.setAttribute('role', 'alert'); b.setAttribute('aria-live', 'assertive');
      const host = document.body || document.documentElement;
      if (host.firstChild && host.insertBefore) host.insertBefore(b, host.firstChild); else host.appendChild(b);
    }
    return b;
  }
  const btn = (cls, text, onclick) => {
    const e = document.createElement('button'); e.type = 'button'; e.className = cls; e.textContent = text; e.onclick = onclick; return e;
  };

  let fresh = new Set();       // tipos que acabaram de chegar (pulsam)
  let sig = '';                // o que está desenhado: nada mudou ⇒ não toca no DOM (o clique não se perde)
  const baseTitle = () => document.title.replace(/^\(\d+\) /, '');
  function render() {
    const n = nums(snap);
    const p = pending(n);
    try { const t = (p > 0 ? '(' + p + ') ' : '') + baseTitle(); if (document.title !== t) document.title = t; } catch { /* sem título */ }
    const showAny = p > 0 || n.open > 0;
    const perm = canNotify() ? Notification.permission : '-';
    const s = [showAny, n.conf, n.unc, n.open, n.mine, [...fresh].join(), muted(), audioReady(), perm, T('pt', 'en', 'es')].join('|');
    if (s === sig) return;
    sig = s;
    const b = document.getElementById('mojStaffAlert');
    if (!showAny) { if (b) { b.classList.remove('show'); b.textContent = ''; } return; }
    const box = bar();
    box.textContent = '';
    if (n.conf) box.appendChild(btn('sa-item sa-conflict' + (fresh.has('conflict') ? ' sa-new' : ''),
      '⚠ ' + n.conf + T(' conflito(s) de veredicto para o juiz-chefe', ' verdict conflict(s) for the chief judge', ' conflicto(s) de veredicto para el juez principal'), goConflicts));
    if (n.unc) box.appendChild(btn('sa-item sa-clar' + (fresh.has('clar') ? ' sa-new' : ''),
      '💬 ' + n.unc + T(' clarification(s) sem resposta', ' unanswered clarification(s)', ' clarification(s) sin respuesta'), go('/contest/clarification/')));
    else if (n.open) box.appendChild(btn('sa-item sa-info',
      '💬 ' + n.open + T(' clarification(s) sendo respondida(s)', ' clarification(s) being answered', ' clarification(s) en respuesta'), go('/contest/clarification/')));
    if (n.mine) box.appendChild(btn('sa-item sa-review' + (fresh.has('review') ? ' sa-new' : ''),
      '⚖ ' + n.mine + T(' veredicto(s) esperando o seu voto', ' verdict(s) awaiting your vote', ' veredicto(s) esperando tu voto'), go('/contest/judge/')));
    // controles: ativar som (sem gesto ainda) · mudo · notificação do sistema (opt-in)
    if (!muted() && !audioReady()) box.appendChild(btn('sa-ctl', T('🔇 ativar som', '🔇 enable sound', '🔇 activar sonido'), (e) => { e.stopPropagation(); unlock(); }));
    box.appendChild(btn('sa-ctl', muted() ? T('🔈 som desligado', '🔈 sound off', '🔈 sonido apagado') : T('🔊 som ligado', '🔊 sound on', '🔊 sonido activado'),
      (e) => { e.stopPropagation(); ls.set(LS_MUTE, muted() ? null : '1'); if (!muted()) unlock(); render(); }));
    if (canNotify() && Notification.permission === 'default') {
      box.appendChild(btn('sa-ctl', T('🔔 avisar fora do navegador', '🔔 notify outside the browser', '🔔 avisar fuera del navegador'),
        (e) => { e.stopPropagation(); try { const r = Notification.requestPermission(); if (r && r.then) r.then(render, render); } catch { /* sem permissão */ } }));
    }
    box.classList.add('show');
  }
  document.addEventListener('moj:lang', render);

  // ---- notificação do sistema (só quando nenhuma aba do contest está visível) ---------------------
  const notify = (ev) => {
    if (!canNotify() || Notification.permission !== 'granted') return;
    const n = nums(snap);
    const lines = [];
    if (ev.includes('conflict')) lines.push('⚠ ' + n.conf + T(' conflito(s) de veredicto', ' verdict conflict(s)', ' conflicto(s) de veredicto'));
    if (ev.includes('clar')) lines.push('💬 ' + n.unc + T(' clarification(s) sem resposta', ' unanswered clarification(s)', ' clarification(s) sin respuesta'));
    if (ev.includes('review')) lines.push('⚖ ' + n.mine + T(' veredicto(s) esperando o seu voto', ' verdict(s) awaiting your vote', ' veredicto(s) esperando tu voto'));
    if (!lines.length) return;
    try {
      const no = new Notification('MOJ — ' + contest, { body: lines.join('\n'), tag: KEY, renotify: true });
      no.onclick = () => { try { window.focus(); } catch { /* */ } no.close(); };
    } catch { /* sem notificação */ }
  };

  // ---- aplica uma fotografia (da própria aba ou da líder) ----------------------------------------
  const visibleNow = () => document.visibilityState === 'visible' || document.hidden === false;
  function apply(next, ev, anyVisible) {
    snap = next;
    fresh = new Set(ev);
    render();
    if (!ev.length) return;
    remindAt = Date.now() + REMIND_MS;
    // UM som por navegador: a aba visível toca; se nenhuma está, a líder (e só ela notifica o sistema)
    if (visibleNow() || (!anyVisible && leader)) play(ev.includes('conflict') ? 'conflict' : ev[0]);
    if (!anyVisible && leader) notify(ev);
  }

  // ---- poll (só a líder) ------------------------------------------------------------------------
  let timer = null, gen = 0;
  const anyVisible = () => visibleNow() || (Date.now() - visAt < 25000);
  const delay = () => (anyVisible() ? 8000 + Math.random() * 4000 : 30000 + Math.random() * 10000);
  async function poll() {
    if (stopped || !leader) return;
    clearTimeout(timer);
    const my = ++gen;
    lastPoll = Date.now();      // na SAÍDA: o "hello" de uma aba nova com um poll em voo não dispara outro
    try {
      const r = await apiGet('/contest/staff-alerts?contest=' + enc(contest), G);
      if (my !== gen) return;
      const ev = eventsOf(snap, r);
      const vis = anyVisible();
      apply(r, ev, vis);
      if (ch) ch.postMessage({ type: 'snap', snap: r, ev, vis });
      // lembrete: enquanto houver pendência, a cada 2 min (desde a última novidade)
      const w = worst(nums(r));
      if (w && remindAt && Date.now() >= remindAt) {
        remindAt = Date.now() + REMIND_MS;
        if (ch) ch.postMessage({ type: 'remind', kind: w, vis });
        if (visibleNow() || !vis) play(w);
      }
      if (!w) remindAt = 0;
      else if (!remindAt) remindAt = Date.now() + REMIND_MS;
    } catch (e) {
      if (e && (e.status === 401 || e.status === 403)) { stopped = true; if (ch) ch.postMessage({ type: 'stop' }); return; }
      /* rede: tenta no próximo ciclo */
    }
    if (my === gen && !stopped) timer = setTimeout(poll, delay());
  }
  const pollSoon = () => { if (leader && Date.now() - lastPoll > 3000) poll(); };

  _poke = () => { if (leader) poll(); else if (ch) ch.postMessage({ type: 'poke' }); };

  document.addEventListener('visibilitychange', () => {
    if (!visibleNow()) return;
    if (leader) pollSoon(); else if (ch) ch.postMessage({ type: 'vis' });
  });

  if (!coord) {                       // sem coordenação: esta aba pola sozinha (como antes)
    leader = true;
    poll();
    return;
  }
  ch.onmessage = (m) => {
    const d = (m && m.data) || {};
    if (d.type === 'snap' && !leader) apply(d.snap, d.ev || [], !!d.vis);
    else if (d.type === 'remind' && !leader) { if (visibleNow()) play(d.kind); }
    else if (d.type === 'stop') { stopped = true; }
    else if (leader && d.type === 'vis') { visAt = Date.now(); pollSoon(); }
    else if (leader && d.type === 'poke') poll();
    else if (leader && d.type === 'hello') { visAt = d.visible ? Date.now() : visAt; if (snap) ch.postMessage({ type: 'snap', snap, ev: [], vis: anyVisible() }); else pollSoon(); }
  };
  // aba seguidora visível avisa a líder a cada 10 s (local, sem rede): é o que mantém o ritmo rápido
  setInterval(() => { if (!leader && !stopped && visibleNow()) ch.postMessage({ type: 'vis' }); }, 10000);
  ch.postMessage({ type: 'hello', visible: visibleNow() });
  // a trava é segurada enquanto a aba viver; fechou a líder, a próxima da fila assume
  navigator.locks.request(KEY, () => new Promise(() => { leader = true; poll(); })).catch(() => {});
}

// pokeStaffAlert() — reavaliar já (depois de responder/reservar/votar/resolver), sem rebipar.
export function pokeStaffAlert() { if (_poke) _poke(); }
