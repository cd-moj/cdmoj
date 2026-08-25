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
  } catch { alert(T('Falha ao baixar.', 'Download failed.')); }
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
export function openHtmlReport(html) {
  const url = URL.createObjectURL(new Blob([html], { type: 'text/html' }));
  const w = window.open(url, '_blank');
  if (!w) { alert(T('Permita pop-ups para ver o relatório.', 'Allow pop-ups to view the report.')); URL.revokeObjectURL(url); return null; }
  setTimeout(() => URL.revokeObjectURL(url), 60000);
  return w;
}

// abre o report HTML AUTENTICADO (busca com Bearer — o nginx não recebe o token por querystring).
export async function openReportAuthed(contest, path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken(contest) } });
    openHtmlReport(await r.text());
  } catch { alert(T('Falha ao abrir o log.', 'Failed to open the log.')); }
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
    label || T('💻 código', '💻 code'));
}
