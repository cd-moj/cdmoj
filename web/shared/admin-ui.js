// shared/admin-ui.js — helpers dos painéis de administração (contest e treino).
// Existiam em 3 cópias (admin.js, machines-tab.js, tasks.js) com diferenças bobas de nome; aqui
// é UMA definição. Sem estado e sem DOM próprio: só formatação, CSV e download.
import { el } from './ui.js';
import { getToken } from './api.js';
import { T, uiLocale } from './i18n.js';

// --- formatação -------------------------------------------------------------
export const pad2 = (n) => String(n).padStart(2, '0');
export const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString(uiLocale());
export const fmtClock = (e) => new Date((+e || 0) * 1000).toLocaleTimeString(uiLocale(), { hour: '2-digit', minute: '2-digit', second: '2-digit' });
// fmtS COM HORAS: a versão antiga mostrava "80min" (a do tasks.js era a certa — uma cópia só agora)
export const fmtS = (s) => {
  s = Math.max(0, Math.round(+s || 0));
  if (s < 60) return s + 's';
  const m = Math.floor(s / 60);
  if (m < 60) return m + 'min' + (s % 60 ? ' ' + (s % 60) + 's' : '');
  return Math.floor(m / 60) + 'h' + (m % 60 ? (m % 60) + 'min' : '');
};
export const fmtEpoch = (e) => (+e ? fmtDate(e) : '—');   // epoch 0/vazio = travessão (não 1970)
export const fmtKB = (n) => (!n ? '—' : n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(n / 1024)) + ' KB');
// sufixos de conta de PAPEL (a MESMA regex do servidor, is_reserved_role_login): uma cópia só —
// estava repetida em users/sites/teams/cohorts/machines
export const PRIV_RE = /\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$/;

// --- auto-refresh EM LUGAR (regra da casa, CLAUDE.md › Frontend) --------------------------
// swap troca o conteúdo de UM contêiner; swapIf só quando a ASSINATURA do dado mudou (fica em
// box.dataset.sig) — o esqueleto do painel nunca é refeito num tick, <details>/inputs/scroll ficam.
export const swap = (box, node) => { box.innerHTML = ''; if (node) box.append(node); };
export function swapIf(box, sig, build) {
  if (box.dataset.sig === sig) return false;
  box.dataset.sig = sig; swap(box, build()); return true;
}
export const sigOf = (...parts) => JSON.stringify(parts);
// tick só com o painel visível e no DOM (o padrão repetido em status/tasks/central/judges/sessions)
export function everyVisible(panel, ms, fn) {
  const t = setInterval(() => { if (!panel.hidden && panel.isConnected) fn(); }, ms);
  return () => clearInterval(t);
}
export const todayStr = () => { const d = new Date(); return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()); };
export const stamp = () => new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
// cor pelo veredicto nas tabelas do painel (pendente = neutro, o resto = anomalia visível)
export const vClass = (v) => (/accepted/i.test(v || '') ? 'v-ok' : (/(not answered|queue|running)/i.test(v || '') ? '' : 'flag-anom'));

// --- busca em lista ---------------------------------------------------------
// norm: minúsculas SEM acento — "São Carlos" casa com "sao". Estava copiado em 5 telas
// (treino, problemas, home, contests, stat); telas novas usam esta.
export const norm = (s) => (s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
// debounce: só para busca que custa (re-render de lista grande ou chamada de rede). Filtro de
// array pequeno em memória não precisa — o repo filtra a cada tecla e vai bem.
export const debounce = (fn, ms = 150) => { let h; return (...a) => { clearTimeout(h); h = setTimeout(() => fn(...a), ms); }; };

// --- campos -----------------------------------------------------------------
export const field = (l, inp) => el('div', { class: 'field' }, el('label', {}, l), inp);
export const chk = (l, c) => el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, c, ' ' + l));
export const mkBool = (v) => { const c = el('input', { type: 'checkbox' }); c.checked = !!v; return c; };

// --- CSV / download ---------------------------------------------------------
export const csvCell = (v) => { const s = String(v == null ? '' : v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
export const toCsv = (rows) => rows.map((r) => r.map(csvCell).join(',')).join('\r\n') + '\r\n';

export function downloadText(filename, text, mime) {
  const url = URL.createObjectURL(new Blob([text], { type: (mime || 'text/plain') + ';charset=utf-8' }));
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}

// download AUTENTICADO (Bearer) -> blob -> arquivo: é como se baixa zip/tar.gz da API, que um
// <a href> puro não consegue (não manda o header).
export async function downloadAuthed(contest, path, filename) {
  const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + (getToken(contest) || '') } });
  if (!r.ok) { alert(T('Falha no download (HTTP ', 'Download failed (HTTP ', 'Error de descarga (HTTP ') + r.status + ')'); return; }
  const blob = await r.blob(); const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}

// --- confirmação de AÇÃO DE VÁRIOS ALVOS (16/10/2026) ----------------------------------------------------
// O cartão da PRÉVIA do servidor (lib/admin-bulk.sh): quantas contas, quantas sessões, os primeiros nomes, quem
// ficou de fora e porquê, e o campo "digite N para confirmar" — o botão só habilita quando o número bate. Em linha,
// nunca prompt(): foi um clique sem confirmação nenhuma que deslogou 1.310 contas do treino. `run(plan_id, n)` faz o
// POST de execução e devolve a resposta; se o servidor disser plan_changed/confirm_required, o cartão se refaz com a
// prévia nova (error.preview). onDone(resposta) / onCancel() avisam quem abriu.
const SKIP_WHY = () => ({
  self: T('a sua conta', 'your own account', 'tu propia cuenta'),
  role: T('conta de papel (.admin, .judge…)', 'role account (.admin, .judge…)', 'cuenta de rol (.admin, .judge…)'),
  superadmin: T('super-admin', 'super-admin', 'super-admin'),
  notfound: T('não existe', 'does not exist', 'no existe'),
});
export function confirmDanger({ title, verb, preview, run, onDone, onCancel }) {
  const box = el('div', { class: 'subcard danger-confirm', role: 'alertdialog', style: 'border:2px solid var(--bad, #b42318);padding:.7rem .9rem;margin:.5rem 0' });
  let pv = preview || {};
  const paint = (note) => {
    box.innerHTML = '';
    const n = Number(pv.need) || 0, ns = Number(pv.sessions_count) || 0;
    box.append(el('h3', { style: 'margin:.1rem 0 .4rem' }, '⚠️ ' + title));
    if (note) box.append(el('div', { class: 'notice', style: 'margin:.3rem 0' }, note));
    box.append(el('p', { style: 'margin:.2rem 0' }, el('b', {}, String(n)),
      T(' conta(s) serão afetadas', ' account(s) will be affected', ' cuenta(s) serán afectadas'),
      ns ? T(` (${ns} sessão(ões))`, ` (${ns} session(s))`, ` (${ns} sesión(es))`) : '', '.'));
    const sample = pv.sample || [];
    if (sample.length) {
      box.append(el('div', { class: 'small', style: 'font-family:var(--mono);word-break:break-word' },
        sample.join(' · ') + (n > sample.length ? T(` … e mais ${n - sample.length}`, ` … and ${n - sample.length} more`, ` … y ${n - sample.length} más`) : '')));
    }
    if (Number(pv.skipped_count) > 0) {
      const why = SKIP_WHY(), by = pv.skipped_by_reason || {};
      box.append(el('div', { class: 'small muted', style: 'margin-top:.35rem' },
        T('Ficam de fora: ', 'Left out: ', 'Quedan fuera: ') + Object.entries(by).map(([k, v]) => `${v} × ${why[k] || k}`).join(' · ')));
    }
    if (!n) {   // nada a fazer (ex.: nenhuma das contas tem sessão aberta) — não pede "digite 0"
      box.append(el('div', { class: 'row', style: 'gap:.4rem;align-items:center;margin-top:.5rem' },
        el('span', { class: 'small' }, T('Nada a fazer.', 'Nothing to do.', 'Nada que hacer.')),
        el('button', { class: 'btn ghost', onclick: () => { box.remove(); if (onCancel) onCancel(); } }, T('Fechar', 'Close', 'Cerrar'))));
      return;
    }
    const inp = el('input', { type: 'text', inputmode: 'numeric', autocomplete: 'off', style: 'width:7rem',
      'aria-label': T('número de contas para confirmar', 'number of accounts to confirm', 'número de cuentas para confirmar') });
    const go = el('button', { class: 'btn danger', disabled: true }, verb);
    const cancel = el('button', { class: 'btn ghost' }, T('Cancelar', 'Cancel', 'Cancelar'));
    const msg = el('span', { class: 'small' });
    inp.addEventListener('input', () => { go.disabled = inp.value.trim() !== String(n); });
    cancel.addEventListener('click', () => { box.remove(); if (onCancel) onCancel(); });
    go.addEventListener('click', async () => {
      go.disabled = true; msg.textContent = T('executando…', 'running…', 'ejecutando…');
      try { const r = await run(pv.plan_id, n); box.remove(); if (onDone) onDone(r); }
      catch (e) {
        const d = (e && e.data) || {};
        if (d.preview && (e.code === 'plan_changed' || e.code === 'confirm_required')) {
          pv = d.preview;
          paint(T('A situação mudou desde a prévia. Confira o número de novo.', 'Things changed since the preview. Check the number again.', 'La situación cambió desde la vista previa. Revisa el número de nuevo.'));
          return;
        }
        msg.textContent = (e && e.message) || T('falha', 'failed', 'fallido'); go.disabled = false;
      }
    });
    box.append(el('div', { class: 'row', style: 'gap:.4rem;align-items:center;flex-wrap:wrap;margin-top:.5rem' },
      el('span', { class: 'small' }, T(`Digite ${n} para confirmar:`, `Type ${n} to confirm:`, `Escribe ${n} para confirmar:`)), inp, go, cancel, msg));
    try { inp.focus(); } catch (_) { /* sem foco (teste) */ }
  };
  paint();
  return box;
}
