// contest/admin/modules-tab.js — "Central › Módulos": o que este contest LIGA. Um cartão por módulo
// do catálogo (modules.js) com nome, descrição, painéis que ele abre, pill "dados presentes"
// (detectado pelo servidor: GET /contest/admin/modules) e a caixa de ligar. Presets só pré-marcam.
// Salvar → POST {on, off} → evento `moj:modules` (o shell re-renderiza a nav na hora).
// Desligar NUNCA apaga dado: o aviso diz isso e a API preserva os arquivos.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';
import { MODULES, PRESETS } from './modules.js';

const enc = encodeURIComponent;

export function makeModulesTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  const noticeBox = el('div', {});
  const grid = el('div', { class: 'tcards' });
  const msg = el('div', { class: 'small' });
  const checks = {};
  let DATA = null;

  // aviso de bookmark p/ painel de módulo desligado (o shell chama depois do load)
  function notice(text) {
    noticeBox.innerHTML = '';
    if (!text) return;
    noticeBox.append(el('div', { class: 'alert row', style: 'gap:.6rem;align-items:center' }, el('span', { style: 'flex:1' }, text),
      el('button', { class: 'btn ghost small', title: T('dispensar', 'dismiss'), onclick: () => { noticeBox.innerHTML = ''; } }, '✕')));
  }

  const rowOf = (id) => ((DATA && DATA.modules) || []).find((m) => m.id === id) || {};
  function card(m) {
    const r = rowOf(m.id);
    const cb = el('input', { type: 'checkbox' }); cb.checked = !!r.on; checks[m.id] = cb;
    const dataPill = r.detected
      ? el('span', { class: 'pill ok', title: r.reason || '' }, T('dados presentes', 'data present'))
      : el('span', { class: 'pill', title: T('nenhum arquivo deste módulo no contest', 'no file of this module in the contest') }, T('sem dados', 'no data'));
    return el('div', { class: 'gen-card' + (r.on ? '' : ' off') },
      el('label', { style: 'display:flex;gap:.5rem;align-items:flex-start;cursor:pointer' }, cb,
        el('div', { style: 'flex:1' },
          el('h4', { style: 'margin:0' }, m.icon + ' ' + m.name, ' ', dataPill),
          el('div', { class: 'small muted', style: 'margin:.2rem 0' }, m.desc),
          el('div', { class: 'small' }, T('Abre: ', 'Opens: '), m.panels.join(' · ')),
          r.detected && !r.on ? el('div', { class: 'small', style: 'color:#7a5c00;margin-top:.2rem' },
            T('Desligado com dados existentes: os painéis não aparecem, mas nada foi apagado.', 'Off with existing data: the panels are hidden, but nothing was deleted.')) : null)));
  }
  function renderCards() { grid.innerHTML = ''; MODULES().forEach((m) => grid.append(card(m))); }

  function presetsRow() {
    return el('div', { class: 'row', style: 'gap:.4rem;flex-wrap:wrap;align-items:center;margin:.4rem 0' },
      el('span', { class: 'small muted' }, T('Pré-marcar:', 'Pre-select:')),
      ...PRESETS().map((p) => el('button', { class: 'btn ghost small', title: p.hint, onclick: () => {
        Object.entries(checks).forEach(([id, cb]) => { cb.checked = p.mods.includes(id); });
        msg.className = 'small muted'; msg.textContent = T(`preset «${p.name}» marcado — confira e salve`, `preset "${p.name}" selected — check and save`);
      } }, p.name)));
  }

  async function save() {
    const on = [], off = [];
    Object.entries(checks).forEach(([id, cb]) => { const was = !!rowOf(id).on; if (cb.checked && !was) on.push(id); if (!cb.checked && was) off.push(id); });
    if (!on.length && !off.length) { msg.className = 'small muted'; msg.textContent = T('nada a mudar', 'nothing to change'); return; }
    const offWithData = off.filter((id) => rowOf(id).detected);
    if (offWithData.length) {
      const names = offWithData.map((id) => (MODULES().find((m) => m.id === id) || {}).name || id).join(', ');
      if (!confirm(T(`Desligar ${names}? Os painéis somem da nav, mas NENHUM dado é apagado — religar restaura tudo.`,
        `Turn off ${names}? The panels leave the nav, but NO data is deleted — turning it back on restores everything.`))) return;
    }
    msg.className = 'small muted'; msg.textContent = T('Salvando…', 'Saving…');
    try {
      await apiPost('/contest/admin/modules?contest=' + enc(CONTEST), { on, off }, G);
      await fetchData(); renderCards();
      msg.className = 'small'; msg.textContent = T('✓ salvo', '✓ saved');
      window.dispatchEvent(new CustomEvent('moj:modules', { detail: { enabled: (DATA && DATA.enabled) || [] } }));
    } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
  }
  async function fetchData() { DATA = await apiGet('/contest/admin/modules?contest=' + enc(CONTEST), G); }

  let built = false;
  async function load() {
    if (!built) {
      panel.innerHTML = '';
      panel.append(el('h2', {}, T('🧩 Módulos do contest', '🧩 Contest modules')),
        el('p', { class: 'muted small' },
          T('Um módulo é um grupo de recursos que este contest usa. Ligar mostra os painéis, as checagens da Central e os cartões correspondentes; desligar esconde, sem apagar nada. Uma prova de disciplina costuma não ligar nenhum; uma prova com Maratona Linux liga Máquinas; a Maratona liga todos.',
            'A module is a group of features this contest uses. Turning it on shows the matching panels, Home checks and cards; turning it off hides them without deleting anything. A course exam usually enables none; an exam on Maratona Linux enables Machines; the Maratona enables all.')),
        noticeBox, presetsRow(), grid,
        el('div', { class: 'row', style: 'gap:.6rem;align-items:center;margin-top:.6rem' },
          el('button', { class: 'btn', onclick: save }, T('💾 Salvar módulos', '💾 Save modules')), msg));
      built = true;
    }
    try { await fetchData(); } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha ao carregar', 'failed to load'); return; }
    renderCards();
  }
  return { panel, load, notice };
}
