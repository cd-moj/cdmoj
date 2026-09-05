// shared/admin-ui.js — helpers dos painéis de administração (contest e treino).
// Existiam em 3 cópias (admin.js, machines-tab.js, tasks.js) com diferenças bobas de nome; aqui
// é UMA definição. Sem estado e sem DOM próprio: só formatação, CSV e download.
import { el } from './ui.js';
import { getToken } from './api.js';
import { T } from './i18n.js';

// --- formatação -------------------------------------------------------------
export const pad2 = (n) => String(n).padStart(2, '0');
export const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString();
export const fmtClock = (e) => new Date((+e || 0) * 1000).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit' });
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
  if (!r.ok) { alert(T('Falha no download (HTTP ', 'Download failed (HTTP ') + r.status + ')'); return; }
  const blob = await r.blob(); const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}
