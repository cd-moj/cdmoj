// shared/contest-config/basic.js — editor de campos "basic" do contest (vão para o conf).
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { toLocalDT, dtToEpoch } from './util.js';

export function makeBasicEditor(opts = {}) {
  const i = opts.initial || {};
  const locale = el('select', {}, el('option', { value: 'pt' }, 'Português'), el('option', { value: 'en' }, 'English'));
  locale.value = i.locale || 'pt';
  const loginStart = el('input', { type: 'datetime-local' }); if (i.login_start) loginStart.value = toLocalDT(i.login_start);
  const loginEnabled = el('input', { type: 'checkbox' }); loginEnabled.checked = i.login_enabled !== false;
  const freeze = el('input', { type: 'datetime-local' }); if (i.freeze) freeze.value = toLocalDT(i.freeze);

  const panel = el('div', {},
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, T('Idioma do contest', 'Contest language')), locale),
      el('div', { class: 'field' }, el('label', {}, T('Abertura do login (tela de espera)', 'Login opening (waiting screen)')), loginStart)),
    el('div', { class: 'grid2' },
      el('div', { class: 'field' }, el('label', {}, T('Freeze do placar (congela no fim)', 'Scoreboard freeze (freezes at the end)')), freeze),
      el('div', { class: 'field' }, el('label', { style: 'font-weight:400' }, loginEnabled, T(' Login habilitado', ' Login enabled')))));
  return {
    el: panel,
    getValue() {
      return {
        locale: locale.value,
        login_start: loginStart.value ? dtToEpoch(loginStart.value) : undefined,
        login_enabled: loginEnabled.checked,
        freeze: freeze.value ? dtToEpoch(freeze.value) : undefined,
      };
    },
  };
}
