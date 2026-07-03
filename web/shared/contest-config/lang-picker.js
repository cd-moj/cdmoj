// shared/contest-config/lang-picker.js — seletor de linguagens (checkboxes a partir da lista
// canônica do MOJ). Compartilhado: aba Configurações/Problemas do admin e o wizard de criação.
import { el } from '/shared/ui.js';
import { LANGUAGES } from '/shared/languages.js';

// makeLangPicker(selectedIds) -> { el, get() -> [ids marcados] }
export function makeLangPicker(selectedIds) {
  const sel = new Set((selectedIds || []).map((x) => String(x).toLowerCase()));
  const boxes = LANGUAGES.map((l) => {
    const c = el('input', { type: 'checkbox' }); c.checked = sel.has(l.id);
    return { id: l.id, c };
  });
  const box = el('div', { class: 'lang-grid' },
    ...boxes.map((b) => el('label', { class: 'lang-chip' }, b.c, ' ' + LANGUAGES.find((l) => l.id === b.id).label)));
  return { el: box, get: () => boxes.filter((b) => b.c.checked).map((b) => b.id) };
}
