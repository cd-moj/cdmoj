// shared/contest-config/lang-picker.js — seletor de linguagens (checkboxes a partir da lista
// canônica do MOJ). Compartilhado: aba Configurações/Problemas do admin e o wizard de criação.
import { el } from '/shared/ui.js';
import { LANGUAGES, LANG_ALIAS } from '/shared/languages.js';
import { T } from '/shared/i18n.js';

// makeLangPicker(selectedIds) -> { el, get() -> [ids marcados] }
// O conf pode trazer a grafia ANTIGA (`C CPP PY3`, do MOJ de antes) e ids que esta tela não conhece (`MD`, `MEPA`):
// canoniza pelo LANG_ALIAS (py3→py, cc→cpp, h→c…) e mantém o desconhecido MARCADO, com aviso — senão salvar
// QUALQUER outra opção da Regras apagava o Python e o resto da lista (auditoria do painel, 03/10/2026).
export function makeLangPicker(selectedIds) {
  const canon = (x) => { const e = String(x || '').trim().toLowerCase(); return LANG_ALIAS[e] || e; };
  const sel = new Set((selectedIds || []).map(canon).filter(Boolean));
  const boxes = LANGUAGES.map((l) => {
    const c = el('input', { type: 'checkbox' }); c.checked = sel.has(l.id);
    return { id: l.id, c, label: l.label };
  });
  [...sel].filter((id) => !LANGUAGES.some((l) => l.id === id)).forEach((id) => {
    const c = el('input', { type: 'checkbox' }); c.checked = true;
    boxes.push({ id, c, label: id, note: T('⚠️ fora da lista do MOJ', '⚠️ not in the MOJ list', '⚠️ fuera de la lista del MOJ') });
  });
  const box = el('div', { class: 'lang-grid' },
    ...boxes.map((b) => el('label', { class: 'lang-chip', title: b.note || '' }, b.c, ' ' + b.label + (b.note ? ' ' + b.note : ''))));
  return { el: box, get: () => boxes.filter((b) => b.c.checked).map((b) => b.id) };
}
