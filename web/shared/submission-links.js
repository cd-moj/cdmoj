// shared/submission-links.js — links AUTENTICADOS p/ o log (report HTML) e o código-fonte de uma
// submissão, reusáveis em qualquer tela de juiz/chefe/admin. `s` = {id, sub_epoch, lang}.
// Centraliza o fetch com Bearer (o nginx não recebe o token por querystring) + o nome de arquivo
// com a EXTENSÃO correta da linguagem (igual ao que o aluno baixa).
import { el } from '/shared/ui.js';
import { getToken } from '/shared/api.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

// baixa um recurso autenticado como arquivo (blob), preservando o nome/extensão.
export async function downloadAuthed(contest, path, filename) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken(contest) } });
    if (!r.ok) throw 0;
    const a = el('a', { href: URL.createObjectURL(await r.blob()), download: filename });
    document.body.append(a); a.click(); a.remove();
  } catch { alert(T('Falha ao baixar.', 'Download failed.', 'Error al descargar.')); }
}

// openHtmlReport(html) — abre um relatório HTML AUTO-CONTIDO (o report.html do mojtools, o de
// calibração, o de test-run) numa aba nova, por **blob URL**.
//
// ⚠ NUNCA use `<iframe srcdoc>` para isto. Um srcdoc tem URL `about:srcdoc` e herda o BASE URL do
// PAI: um `href="#test-3-in"` resolve para "<a-página-de-onde-você-veio>#test-3-in" e vira
// NAVEGAÇÃO, não rolagem. Era o que fazia os quadradinhos do log "voltarem para a página de
// submissão" (relato de juiz, 2026-08-24) — em quatro telas, porque a rotina foi copiada. Com
// blob o documento ganha URL própria e a âncora volta a ser âncora.
// Isolar não é problema: o report é gerado sem JS e traz `default-src 'none'` no próprio <head>.
//
// `w` (opcional) = a janela já aberta NO CLIQUE (openReportAuthed/openTextAuthed): depois de um `await` o navegador
// pode barrar o pop-up. O blob vive enquanto a aba aberta viver (antes era revogado em 60 s: recarregar ou voltar ao
// report depois de um minuto dava página morta — relato do Roberto, 09/11/2026).
export function openHtmlReport(html, w) {
  const url = URL.createObjectURL(new Blob([html], { type: 'text/html' }));
  if (w && !w.closed) w.location.replace(url);
  else w = window.open(url, '_blank');
  if (!w) { alert(T('Permita pop-ups para ver o relatório.', 'Allow pop-ups to view the report.', 'Permite las ventanas emergentes para ver el informe.')); URL.revokeObjectURL(url); return null; }
  revokeWhenClosed(w, url);
  return w;
}
function revokeWhenClosed(w, url) {
  const iv = setInterval(() => {
    let gone = true; try { gone = w.closed; } catch { /* sem acesso = fechada */ }
    if (gone) { clearInterval(iv); URL.revokeObjectURL(url); }
  }, 5000);
}

// a janela é aberta NO CLIQUE, com "carregando…"; o conteúdo chega depois do fetch
function pendingWindow() {
  const w = window.open('', '_blank');
  if (!w) { alert(T('Permita pop-ups para ver o relatório.', 'Allow pop-ups to view the report.', 'Permite las ventanas emergentes para ver el informe.')); return null; }
  try { w.document.title = T('Carregando…', 'Loading…', 'Cargando…'); w.document.body.textContent = T('Carregando…', 'Loading…', 'Cargando…'); } catch { /* segue */ }
  return w;
}
// erro da API na PRÓPRIA janela (antes o corpo do erro — JSON, ou a página do nginx — abria como se fosse o report)
function windowError(w, status, body) {
  let m = ''; try { m = JSON.parse(body).error.message || ''; } catch { /* não é JSON */ }
  try {
    w.document.title = T('Não foi possível abrir', 'Could not open', 'No se pudo abrir');
    w.document.body.textContent = T('Não foi possível abrir: ', 'Could not open: ', 'No se pudo abrir: ')
      + (m || (status ? 'HTTP ' + status : T('falha de rede', 'network failure', 'falla de red')));
  } catch { /* janela fechada */ }
}

// abre o report HTML AUTENTICADO (busca com Bearer — o nginx não recebe o token por querystring).
export async function openReportAuthed(contest, path) {
  const w = pendingWindow(); if (!w) return;
  try {
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken(contest) } });
    const body = await r.text();
    if (!r.ok) { windowError(w, r.status, body); return; }
    openHtmlReport(body, w);
  } catch { windowError(w, 0, ''); }
}

// abre um TEXTO autenticado (código-fonte, log cru) numa aba, em <pre> — mesma regra do openReportAuthed
export async function openTextAuthed(contest, path) {
  const w = pendingWindow(); if (!w) return;
  try {
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken(contest) } });
    const body = await r.text();
    if (!r.ok) { windowError(w, r.status, body); return; }
    const pre = w.document.createElement('pre');
    pre.style.cssText = 'font-family:monospace;white-space:pre-wrap;padding:1rem';
    pre.textContent = body;
    w.document.body.replaceChildren(pre); w.document.title = path.replace(/^.*[?&]id=([0-9a-f]{8}).*$/, '$1');
  } catch { windowError(w, 0, ''); }
}

const srcExt = (s) => ((s && s.lang) ? String(s.lang) : 'txt').toLowerCase();

// logLink(contest, s) / srcLink(contest, s) -> <a> prontos. `s` = {id, sub_epoch, lang}.
export function logLink(contest, s, label) {
  return el('a', { href: '#', onclick: (e) => { e.preventDefault();
    openReportAuthed(contest, `/submission/log?contest=${enc(contest)}&id=${enc(s.id)}&time=${enc(s.sub_epoch || '')}`); } },
    label || '📄 log');
}
export function srcLink(contest, s, label) {
  return el('a', { href: '#', onclick: (e) => { e.preventDefault();
    downloadAuthed(contest, `/submission/source?contest=${enc(contest)}&id=${enc(s.id)}&time=${enc(s.sub_epoch || '')}`, s.id + '.' + srcExt(s)); } },
    label || T('💻 código', '💻 code', '💻 código'));
}
