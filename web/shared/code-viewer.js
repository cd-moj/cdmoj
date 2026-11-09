// shared/code-viewer.js — o CÓDIGO de uma submissão na tela, com cor de sintaxe e só leitura (o CodeMirror do editor;
// pedido do Paulo, 09/11/2026: "na maioria das vezes dá pra julgar sem baixar o código"). Duas formas:
//   mountSource(host, contest, s) — dentro de uma página (a página da submissão, /contest/run/);
//   openCodeDialog(contest, s)    — um pop-up sobre a tela atual (fila do juiz, todas as submissões).
// `s` = {id, sub_epoch, lang}. O acesso é o da rota /submission/source (dono ou juiz); o erro dela aparece na tela.
import { el } from '/shared/ui.js';
import { getToken } from '/shared/api.js';
import { T } from '/shared/i18n.js';
import { createEditor } from '/shared/editor.js';
import { langById, langLabel, LANG_ALIAS } from '/shared/languages.js';

const enc = encodeURIComponent;
export const cmForLang = (lang) => { const e = String(lang || '').toLowerCase(); return langById(LANG_ALIAS[e] || e).cm; };
const extOf = (lang) => String(lang || 'txt').toLowerCase();

export async function fetchSource(contest, s) {
  const r = await fetch(`/api/v1/submission/source?contest=${enc(contest)}&id=${enc(s.id)}&time=${enc(s.sub_epoch || '')}`,
    { headers: { Authorization: 'Bearer ' + getToken(contest) } });
  const body = await r.text();
  if (!r.ok) { let m = ''; try { m = JSON.parse(body).error.message || ''; } catch { /* não é JSON */ } throw new Error(m || 'HTTP ' + r.status); }
  return body;
}

// o código num elemento da página; devolve {code} (ou null com o erro já na tela)
export async function mountSource(host, contest, s) {
  host.replaceChildren(el('div', { class: 'muted small' }, T('carregando o código…', 'loading the code…', 'cargando el código…')));
  let code;
  try { code = await fetchSource(contest, s); }
  catch (e) {
    host.replaceChildren(el('div', { class: 'error-box' }, T('Não foi possível abrir o código: ', 'Could not open the code: ', 'No se pudo abrir el código: ') + (e.message || '')));
    return null;
  }
  host.replaceChildren();
  await createEditor(host, { doc: code, cm: cmForLang(s.lang), readOnly: true });
  return { code };
}

export function downloadText(name, text) {
  const a = el('a', { href: URL.createObjectURL(new Blob([text], { type: 'text/plain' })), download: name });
  document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 30000);
}

// o pop-up: cabeçalho com o id, a linguagem e as ações (página da submissão, copiar, baixar, fechar)
export function openCodeDialog(contest, s, { runHref } = {}) {
  let code = '';
  const body = el('div', { class: 'code-dlg-body', style: 'height:min(72vh,820px);overflow:auto' });
  const msg = el('span', { class: 'small muted' });
  const copyB = el('button', { class: 'btn ghost', onclick: async () => {
    try { await navigator.clipboard.writeText(code); msg.textContent = T('copiado', 'copied', 'copiado'); }
    catch { msg.textContent = T('não foi possível copiar', 'could not copy', 'no se pudo copiar'); }
  } }, T('📋 Copiar', '📋 Copy', '📋 Copiar'));
  const dlB = el('button', { class: 'btn ghost', onclick: () => { if (code) downloadText(s.id + '.' + extOf(s.lang), code); } }, T('⬇ Baixar', '⬇ Download', '⬇ Descargar'));
  const dlg = el('dialog', { class: 'code-dlg', style: 'width:min(1100px,96vw);max-height:94vh;padding:0;border:1px solid var(--line,#cbd5e1);border-radius:10px' });
  const closeB = el('button', { class: 'btn ghost', title: T('fechar (Esc)', 'close (Esc)', 'cerrar (Esc)'), onclick: () => dlg.close() }, '✕');
  dlg.append(
    el('div', { class: 'row', style: 'gap:.5rem;align-items:center;padding:.5rem .8rem;border-bottom:1px solid var(--line,#e2e8f0);flex-wrap:wrap' },
      el('b', {}, '💻 ' + String(s.id || '').slice(0, 8)), el('span', { class: 'small muted' }, langLabel(s.lang) || s.lang || ''),
      el('div', { class: 'spacer' }), msg,
      runHref ? el('a', { class: 'btn ghost', href: runHref, target: '_blank', rel: 'noopener' }, T('↗ Página da submissão', '↗ Submission page', '↗ Página del envío')) : null,
      copyB, dlB, closeB),
    body);
  document.body.append(dlg);
  dlg.addEventListener('close', () => dlg.remove());
  dlg.addEventListener('click', (e) => { if (e.target === dlg) dlg.close(); });   // clique fora fecha
  if (typeof dlg.showModal === 'function') dlg.showModal(); else dlg.setAttribute('open', '');
  mountSource(body, contest, s).then((r) => { if (r) code = r.code; });
  return dlg;
}
