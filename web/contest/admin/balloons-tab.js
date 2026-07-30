// contest/admin/balloons-tab.js — "Prova › Balões": cor de cada letra.
// O staff imprime a folha do balão com a cor desenhada (lib/print.sh); sem balloons.json todos
// saem cinza. Salva só a chave `colors` do POST /contest/admin/config (o handler é por-chave).
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { makeColorsEditor } from '/shared/contest-config/index.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

export function makeBalloonsTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('🎈 Balões', '🎈 Balloons')),
      el('p', { class: 'small muted' },
        T('Uma cor por letra: é o que sai desenhado na folha do balão que o staff entrega. Sem cores definidas, todos os balões saem cinza.',
          'One colour per letter: it is what gets drawn on the balloon sheet the staff delivers. With no colours defined, every balloon comes out grey.')));
    let cfg;
    try { cfg = await apiGet('/contest/admin/config?contest=' + enc(CONTEST), G); }
    catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }
    if (!(cfg.letters || []).length) {
      panel.append(el('div', { class: 'muted' }, T('O contest ainda não tem problemas — adicione em Prova › Problemas.', 'The contest has no problems yet — add them in Contest › Problems.')));
      return;
    }
    const ed = makeColorsEditor({ letters: cfg.letters || [], initial: cfg.colors || {} });
    const msg = el('div', { class: 'small' });
    const save = el('button', { class: 'btn' }, T('Salvar cores', 'Save colours'));
    save.addEventListener('click', async () => {
      save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
      try { await apiPost('/contest/admin/config?contest=' + enc(CONTEST), { colors: ed.getValue() }, G); msg.textContent = T('✓ salvo', '✓ saved'); }
      catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
      save.disabled = false;
    });
    panel.append(ed.el, el('div', { class: 'row', style: 'margin-top:.7rem' }, save, msg));
  }
  return { panel, load };
}
