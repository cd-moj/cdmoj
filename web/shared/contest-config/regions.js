// shared/contest-config/regions.js — editor de filtros de região (regions.json).
// Lista simples {name, regex}; “JSON avançado” permite sub-regiões aninhadas.
import { el } from '/shared/ui.js';

export function makeRegionsEditor(opts = {}) {
  let regions = (opts.initial || []).map((r) => ({ ...r }));
  const list = el('div', {});
  function render() {
    list.innerHTML = '';
    if (!regions.length) list.append(el('p', { class: 'muted small' }, 'Sem filtros de região. Ex.: nome “DF”, regex “^br-df-”.'));
    regions.forEach((r, i) => {
      const name = el('input', { value: r.name || '', placeholder: 'nome (ex.: DF)', style: 'width:150px' });
      name.addEventListener('input', () => { r.name = name.value; });
      const rx = el('input', { value: r.regex || '', placeholder: 'regex (ex.: ^br-df-)', style: 'flex:1' });
      rx.addEventListener('input', () => { r.regex = rx.value; });
      const rm = el('button', { class: 'btn danger', onclick: () => { regions.splice(i, 1); render(); } }, '✕');
      list.append(el('div', { class: 'row', style: 'margin:.25rem 0' }, name, rx, rm));
    });
  }
  render();
  const adv = el('textarea', { rows: '5', style: 'width:100%;display:none;font-family:monospace;font-size:.82rem', placeholder: 'JSON avançado com subregions…' });
  const advToggle = el('a', { href: '#', class: 'small', onclick: (e) => {
    e.preventDefault();
    if (adv.style.display === 'none') { adv.value = JSON.stringify(regions, null, 1); adv.style.display = ''; }
    else adv.style.display = 'none';
  } }, 'JSON avançado (sub-regiões)');
  const panel = el('div', {}, list,
    el('div', { class: 'row' }, el('button', { class: 'btn ghost', onclick: () => { regions.push({ name: '', regex: '' }); render(); } }, '+ região'), advToggle),
    adv);
  return {
    el: panel,
    getValue() {
      if (adv.style.display !== 'none' && adv.value.trim()) {
        try { const j = JSON.parse(adv.value); if (Array.isArray(j)) return j; } catch { /* cai no modo simples */ }
      }
      return regions.filter((r) => r.regex && r.regex.trim()).map((r) => ({ name: r.name || r.regex, regex: r.regex.trim() }));
    },
  };
}
