// shared/chief-alert.js — alerta GLOBAL de conflito de veredicto p/ o juiz-chefe (.cjudge) e o admin,
// visível em QUALQUER página do contest (os dois shells o iniciam). Banner flutuante no topo + bip +
// vibração quando o nº de conflitos sobe; clicar leva ao painel de Conflitos do juiz-chefe.
// Build-free, idempotente, auto-contido (injeta o próprio CSS e o próprio elemento).
import { apiGet } from '/shared/api.js';
import { T } from '/shared/i18n.js';

let _started = false;   // garante um único poller por página
let _poke = null;       // força uma reavaliação imediata (ex.: logo após resolver um conflito)

function injectCss() {
  if (document.getElementById('mojChiefAlertCss')) return;
  const s = document.createElement('style'); s.id = 'mojChiefAlertCss';
  s.textContent = '#mojChiefAlert{position:fixed;top:0;left:0;right:0;z-index:9999;background:#c0392b;'
    + 'color:#fff;font-weight:700;text-align:center;padding:.55rem 1rem;cursor:pointer;'
    + 'box-shadow:0 2px 10px rgba(0,0,0,.35);transform:translateY(-110%);transition:transform .25s}'
    + '#mojChiefAlert.show{transform:translateY(0);animation:mojChiefPulse 1.1s ease-in-out infinite}'
    + '@keyframes mojChiefPulse{0%,100%{background:#c0392b}50%{background:#e74c3c}}';
  document.head.appendChild(s);
}

function banner() {
  let b = document.getElementById('mojChiefAlert');
  if (!b) {
    injectCss();
    b = document.createElement('div');
    b.id = 'mojChiefAlert'; b.setAttribute('role', 'alert');
    (document.body || document.documentElement).appendChild(b);
  }
  return b;
}

// bip curto (Web Audio) + vibração; tudo embrulhado em try (autoplay/perm podem bloquear).
function beep() {
  try {
    const A = window.AudioContext || window.webkitAudioContext; const a = new A();
    const o = a.createOscillator(); const g = a.createGain();
    o.connect(g); g.connect(a.destination); o.type = 'square'; o.frequency.value = 880; g.gain.value = 0.08; o.start();
    setTimeout(() => { o.frequency.value = 660; }, 200);
    setTimeout(() => { o.stop(); a.close().catch(() => {}); }, 500);
  } catch { /* sem áudio */ }
  try { navigator.vibrate && navigator.vibrate([200, 100, 200]); } catch { /* sem vibração */ }
}

// startChiefAlert(contest, st) — só p/ chief/admin; idempotente. Faz poll do nº de conflitos e
// mostra/atualiza/esconde o banner; bipa só quando o número SOBE (não a cada poll).
export function startChiefAlert(contest, st) {
  if (_started) return;
  if (!st || !(st.is_chief || st.is_admin)) return;   // a trava real é da API; aqui é só não poluir
  _started = true;
  const enc = encodeURIComponent;
  const G = { contest, auth: true };
  const onChiefPage = location.pathname.replace(/\/+$/, '').endsWith('/contest/chief');
  let last = 0, timer = null;

  const goConflicts = () => {
    if (onChiefPage) { location.hash = '#conf'; window.dispatchEvent(new CustomEvent('moj:show-conflicts')); }
    else { location.href = '/contest/chief/?c=' + enc(contest) + '#conf'; }
  };
  const show = (n) => {
    const b = banner();
    b.textContent = '⚠ ' + n + T(' conflito(s) de veredicto aguardando o juiz-chefe — clique para resolver', ' verdict conflict(s) awaiting the chief judge — click to resolve');
    b.classList.add('show'); b.onclick = goConflicts;
  };
  const hide = () => { const b = document.getElementById('mojChiefAlert'); if (b) { b.classList.remove('show'); b.textContent = ''; } };

  const poll = async () => {
    clearTimeout(timer);
    try {
      const r = await apiGet('/contest/review/conflicts?contest=' + enc(contest), G);
      const n = r.n || 0;
      if (n > 0) { show(n); if (n > last) beep(); } else hide();
      last = n;
    } catch { /* silencioso: rede/permissão */ }
    timer = setTimeout(poll, 8000 + Math.random() * 4000);
  };
  _poke = poll;   // reavaliar já (sem rebipar: 'last' é preservado)
  poll();
}

// pokeChiefAlert() — força uma reavaliação imediata (some/atualiza o banner sem esperar o próximo poll).
export function pokeChiefAlert() { if (_poke) _poke(); }
