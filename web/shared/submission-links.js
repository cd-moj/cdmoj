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

// abre o report HTML autenticado numa aba nova, isolado num <iframe sandbox> (sem scripts).
export async function openReportAuthed(contest, path) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken(contest) } });
    const html = await r.text();
    const w = window.open('', '_blank');
    if (!w) { alert(T('Permita pop-ups para ver o log.', 'Allow pop-ups to view the log.')); return; }
    w.document.title = 'Log'; w.document.body.style.margin = '0';
    const ifr = w.document.createElement('iframe'); ifr.setAttribute('sandbox', ''); ifr.srcdoc = html;
    ifr.style.cssText = 'position:fixed;inset:0;border:0;width:100%;height:100%'; w.document.body.append(ifr);
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
