// shared/contest-config/colors.js — editor de cores dos balões + modo Sonic.
// Reaproveitável (criação e admin do contest). Grava no formato do balloons.json.
import { el } from '/shared/ui.js';

const PALETTE = { A: 'FFFFFF', B: '000000', C: 'FF0000', D: '800000', E: 'FFFF00', F: '008000',
  G: '0000FF', H: '000080', I: 'FF00FF', J: '800080', K: '00FF00', L: '00FFFF', M: 'C0C0C0', N: 'FF8000', O: 'A3794D' };
const norm = (v) => (typeof v === 'string' ? v : (v && v.hex) || '').replace(/[^0-9a-fA-F]/g, '').slice(0, 6).toUpperCase();

export function makeColorsEditor(opts = {}) {
  let letters = (opts.letters || []).slice();
  const initial = opts.initial || {};
  const state = {};   // letter -> "RRGGBB"
  const sonic = el('input', { type: 'checkbox' });
  sonic.checked = initial.enableSonic === true || initial.enableSonic === 'true';

  const rows = el('div', {});
  function rebuild() {
    rows.innerHTML = '';
    if (!letters.length) { rows.append(el('p', { class: 'muted small' }, 'Sem problemas ainda — adicione problemas e clique “sincronizar”.')); return; }
    letters.forEach((L) => {
      const hex = state[L] || norm(initial[L]) || PALETTE[L] || 'CCCCCC';
      state[L] = hex;
      const picker = el('input', { type: 'color', value: '#' + hex });
      const txt = el('input', { value: hex, maxlength: '6', style: 'width:90px;font-family:monospace;text-transform:uppercase' });
      picker.addEventListener('input', () => { const v = picker.value.replace('#', '').toUpperCase(); txt.value = v; state[L] = v; });
      txt.addEventListener('input', () => { const v = norm(txt.value); state[L] = v; if (v.length === 6) picker.value = '#' + v; });
      rows.append(el('div', { style: 'display:flex;align-items:center;gap:.5rem;margin:.22rem 0' },
        el('span', { style: 'font-weight:800;width:1.6em;text-align:center' }, L), picker, txt));
    });
  }
  rebuild();

  const panel = el('div', {},
    el('label', { style: 'font-weight:400;display:block;margin-bottom:.4rem' }, sonic, ' 🦔 Modo secreto do Sonic (balões viram GIFs)'),
    rows);
  return {
    el: panel,
    setLetters(ls) { letters = (ls || []).slice(); rebuild(); },
    getValue() {
      const out = {}; let touched = false;
      letters.forEach((L) => {
        if (state[L] && state[L].length === 6) {
          out[L] = state[L];
          if (state[L] !== (norm(initial[L]) || PALETTE[L] || 'CCCCCC')) touched = true;
        }
      });
      if (sonic.checked) { out.enableSonic = true; touched = true; }
      return touched ? out : {};   // {} = não mexeu -> wizard/admin não grava balloons.json
    },
  };
}
