// contest/admin/sites-tab.js — "Pessoas › Sedes & escolas": as SEDES (regiões) do contest e as
// regras de país/escola por regex no login. Antes viviam na aba "Aparência", junto das cores de
// balão — nada a ver: sede é a espinha do gate de UA, do escopo do staff, das etiquetas e do
// filtro do placar. Salva só as chaves `regions` e `teams_meta` do POST /contest/admin/config.
//
// A materialização (regra → campo por time) fica na aba 👥 Times, que é quem edita conta a conta.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { makeRegionsEditor, makeTeamsEditor } from '/shared/contest-config/index.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const PRIV = /\.(admin|judge|cjudge|staff|cstaff|mon)$/;

export function makeSitesTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  async function load() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('🏫 Sedes & escolas', '🏫 Sites & schools')));
    let cfg, ur;
    try {
      [cfg, ur] = await Promise.all([
        apiGet('/contest/admin/config?contest=' + enc(CONTEST), G),
        apiGet('/contest/admin/users?contest=' + enc(CONTEST), G).catch(() => null),
      ]);
    } catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }
    // logins p/ o preview de matches (só quem entra no placar — sem contas privilegiadas)
    const logins = ((ur && ur.users) || []).map((u) => u.login).filter((l) => !PRIV.test(l || ''));

    const regionsEd = makeRegionsEditor({ initial: cfg.regions || [] });
    const teamsEd = await makeTeamsEditor({ initial: cfg.teams_meta || [], logins });
    const msg = el('div', { class: 'small', style: 'margin:.5rem 0' });
    const save = el('button', { class: 'btn' }, T('Salvar sedes e escolas', 'Save sites and schools'));
    save.addEventListener('click', async () => {
      save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
      try {
        await apiPost('/contest/admin/config?contest=' + enc(CONTEST),
          { regions: regionsEd.getValue(), teams_meta: teamsEd.getValue() }, G);
        msg.textContent = T('✓ salvo', '✓ saved');
      } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
      save.disabled = false;
    });
    const hh = (t, sub) => el('div', {}, el('h3', { style: 'margin:1rem 0 .2rem' }, t),
      el('p', { class: 'small muted', style: 'margin:0 0 .3rem' }, sub));
    panel.append(
      hh(T('🏫 Sedes (regiões)', '🏫 Sites (regions)'),
        T('Cada sede é um nome + uma regex no login. A sede alimenta o filtro do placar, o escopo do staff (staff-filters), as etiquetas e o gate de navegador por sede.',
          'Each site is a name + a regex on the login. The site feeds the scoreboard filter, the staff scope (staff-filters), the badges and the per-site browser gate.')),
      regionsEd.el,
      hh(T('🏳️ Países e escolas (por regex no login)', '🏳️ Countries and schools (by login regex)'),
        T('Preenche bandeira/universidade dos times que casarem — conveniência de carga; o valor por time pode ser editado em 👥 Times.',
          'Fills flag/university for matching teams — a bulk convenience; the per-team value can be edited in 👥 Teams.')),
      teamsEd.el,
      el('div', { class: 'row', style: 'margin-top:.7rem' }, save, msg));
  }
  return { panel, load };
}
