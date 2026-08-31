// Painel Prova › Classificação — aplica as regras da 1ª fase → FINAL BRASILEIRA sobre o
// placar (motor server-side /contest/admin/classify), com prévia, rascunho→publicar e
// promoções manuais do comitê. Etapas futuras (PDA → Mundial) já têm o engate no shape
// (stages[]/next_stage) — sem regras implementadas ainda.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

// Tabela OFICIAL de vagas da 1ª fase (regulamento SBC, verificada 15/08) — DEFAULT
// editável quando a região é Brasil. Σ regra2 = 40; 15+40+4+6 = 65 vagas.
const DEFAULT_BR_SEDES = `BA, Salvador = 1
CE, Tianguá = 1
DF, Brasília = 1
ES, Serra = 1
GO, Goiânia = 2
MG, Belo Horizonte = 1
MG, Itajubá = 1
MG, São João del Rei = 1
MG, Uberaba = 1
MG, Viçosa = 1
PA, Belém = 1
PA, Marabá = 1
PA, Santarém = 1
PR, Curitiba = 1
PR, Foz do Iguaçu = 1
RJ, Rio de Janeiro = 2
RS, Passo Fundo = 1
RS, Pelotas = 1
SC, Pinhalzinho = 1
SP, Marília = 1
SP, Ribeirão Preto = 1
SP, São José dos Campos = 1
SP, São Paulo = 3
SP, Sorocaba = 2`;
const DEFAULT_BR_SUPER = `Supersede estadual do Ceará = 2
Supersede estadual de Minas Gerais = 1
Supersede estadual do Rio Grande do Norte = 1
Supersede da região Norte = 1
Supersede da região Nordeste = 4
Supersede da região Sul = 1
Supersede Brasil = 1`;

function parseSlots(text) {
  const out = {};
  String(text || '').split('\n').forEach((ln) => {
    const m = ln.match(/^\s*(.+?)\s*=\s*(\d+)\s*$/);
    if (m && Number(m[2]) > 0) out[m[1]] = Number(m[2]);
  });
  return out;
}

const VIA_T = () => ({
  regra1: T('regra 1 — melhores gerais', 'rule 1 — best overall'),
  regra2: T('regra 2 — vagas por sede', 'rule 2 — site slots'),
  regra4: T('regra 4 — participação feminina', 'rule 4 — female participation'),
  comite: T('comitê (regra 3 / promoções)', 'committee (rule 3 / promotions)'),
});

export function makeClassifyTab(CONTEST) {
  const panel = el('div', { class: 'section' });
  const G = () => ({ contest: CONTEST });
  const call = (body) => apiPost('/contest/admin/classify?contest=' + enc(CONTEST), body, G());

  const head = el('h2', {}, T('🎓 Classificação — próxima fase', '🎓 Qualification — next stage'));
  const stageBox = el('div', {});
  const cfgBox = el('div', {});
  const prevBox = el('div', {});
  panel.append(head, stageBox, cfgBox, prevBox,
    el('p', { class: 'muted small', style: 'margin-top:1rem' },
      T('Engate pronto p/ as próximas etapas: Final BR → PDA → Mundial (regras futuras).',
        'Hooks ready for the next stages: BR Finals → PDA → World Finals (future rules).')));

  const fName = el('input', { value: 'Final Brasileira', style: 'min-width:180px' });
  const fVenue = el('input', { value: 'Uberlândia', style: 'min-width:120px' });
  const fWhen = el('input', { value: 'novembro/2026', style: 'min-width:120px' });
  const fRegion = el('select', {}, el('option', { value: 'Brasil' }, 'Brasil'));
  const fR1 = el('input', { type: 'number', value: '15', style: 'width:5rem' });
  const f3 = el('input', { type: 'number', value: '3', style: 'width:4rem' });
  const f2 = el('input', { type: 'number', value: '2', style: 'width:4rem' });
  const f1 = el('input', { type: 'number', value: '1', style: 'width:4rem' });
  const taSedes = el('textarea', { rows: 10, style: 'width:100%;font-family:var(--mono);font-size:.85rem' });
  const taSuper = el('textarea', { rows: 7, style: 'width:100%;font-family:var(--mono);font-size:.85rem' });
  taSedes.value = DEFAULT_BR_SEDES; taSuper.value = DEFAULT_BR_SUPER;

  const cfg = () => ({
    region: fRegion.value, r1: Number(fR1.value) || 0,
    r4: { f3: Number(f3.value) || 0, f2: Number(f2.value) || 0, f1: Number(f1.value) || 0 },
    sedes: parseSlots(taSedes.value), supersedes: parseSlots(taSuper.value),
  });

  function relationTable(list, withRemove) {
    const via = VIA_T();
    const wrap = el('div', {});
    ['regra1', 'regra2', 'regra4', 'comite'].forEach((v) => {
      const rows = list.filter((t) => t.via === v);
      if (!rows.length) return;
      const tb = el('tbody');
      rows.forEach((t) => {
        const tr = el('tr', {},
          el('td', { class: 'n' }, t.place != null ? String(t.place) : '—'),
          el('td', {}, t.team || t.login, el('span', { class: 'small muted' }, ' · ' + t.login)),
          el('td', { class: 'small' }, t.univ || ''),
          el('td', { class: 'small' }, t.sede || ''),
          el('td', { class: 'small muted' }, t.detail || t.note || ''));
        if (withRemove) tr.append(el('td', {}, el('button', { class: 'btn danger', style: 'font-size:.75rem', onclick: async () => {
          if (!confirm(T('Remover ', 'Remove ') + t.login + T(' da classificação?', ' from the qualification?'))) return;
          try { await call({ action: 'remove', login: t.login }); load(); } catch (e) { alert(e.message); }
        } }, '✖')));
        tb.append(tr);
      });
      wrap.append(el('h4', { style: 'margin:.7rem 0 .2rem' }, via[v] + ' — ' + rows.length),
        el('div', { class: 'chart-wrap' }, el('table', { class: 'moj narrow' },
          el('thead', {}, el('tr', {},
            el('th', { class: 'n' }, T('Posição', 'Place')), el('th', {}, T('Time', 'Team')),
            el('th', {}, T('Escola', 'School')), el('th', {}, T('Sede', 'Site')),
            el('th', {}, T('Detalhe', 'Detail')), withRemove ? el('th', {}, '') : null)), tb)));
    });
    return wrap;
  }

  async function load() {
    stageBox.innerHTML = ''; cfgBox.innerHTML = ''; prevBox.innerHTML = '';
    let st = null;
    try { st = await apiGet('/contest/admin/classify?contest=' + enc(CONTEST), G()); }
    catch (e) { stageBox.append(el('div', { class: 'error-box' }, e.message || 'erro')); return; }
    const stage = (st.stages || []).find((s) => s.id === 'final-br') || null;

    // --- estado atual do stage (rascunho/publicado + relação + promover/remover) ---
    if (stage) {
      const pub = stage.status === 'published';
      const teams = Object.entries(stage.teams || {}).map(([login, v]) => Object.assign({ login }, v))
        .sort((a, b) => (a.place || 9e9) - (b.place || 9e9));
      const addLogin = el('input', { placeholder: 'login', style: 'min-width:150px' });
      const addNote = el('input', { placeholder: T('nota (ex.: regra 3, sede nova)', 'note (e.g., rule 3, new site)'), style: 'min-width:220px' });
      stageBox.append(el('div', { class: 'section', style: 'background:var(--card-bg,#f5f7fb)' },
        el('h3', {}, (stage.name || 'Final Brasileira') + (stage.venue ? ' — ' + stage.venue : '') +
          (stage.when ? ' · ' + stage.when : '')),
        el('p', {}, pub
          ? el('b', { style: 'color:var(--ok,#1a7f37)' }, T('📢 PUBLICADO no placar (chip ↑BR)', '📢 PUBLISHED on the scoreboard (↑BR chip)'))
          : el('b', { style: 'color:var(--warn,#a66a00)' }, T('📝 RASCUNHO (só o admin vê)', '📝 DRAFT (admin only)')),
          el('span', { class: 'small muted' }, ' · ' + teams.length + T(' time(s)', ' team(s)'))),
        el('div', { class: 'toolbar' },
          el('button', { class: 'btn', onclick: async () => {
            const a = pub ? 'unpublish' : 'publish';
            if (!confirm(pub ? T('DESPUBLICAR do placar?', 'UNPUBLISH from the scoreboard?')
                             : T('PUBLICAR no placar (chip ↑BR p/ todos)?', 'PUBLISH on the scoreboard (↑BR chip for everyone)?'))) return;
            try { await call({ action: a }); load(); } catch (e) { alert(e.message); }
          } }, pub ? T('🔕 Despublicar', '🔕 Unpublish') : T('📢 Publicar', '📢 Publish'))),
        relationTable(teams, true),
        el('div', { class: 'toolbar', style: 'margin-top:.5rem' }, addLogin, addNote,
          el('button', { class: 'btn', onclick: async () => {
            const l = addLogin.value.trim(); if (!l) return;
            try { await call({ action: 'add', login: l, note: addNote.value.trim() }); addLogin.value = ''; addNote.value = ''; load(); }
            catch (e) { alert(e.message); }
          } }, T('➕ Promover time (comitê)', '➕ Promote team (committee)')))));
    } else {
      stageBox.append(el('p', { class: 'muted' },
        T('Nenhuma classificação aplicada ainda — configure abaixo, faça a prévia e aplique.',
          'No qualification applied yet — configure below, preview and apply.')));
    }

    // --- config + prévia + aplicar ---
    cfgBox.append(el('details', { open: stage ? null : true },
      el('summary', {}, el('b', {}, T('⚙ Regras e vagas (região: Brasil)', '⚙ Rules and slots (region: Brazil)'))),
      el('div', { class: 'toolbar', style: 'margin:.4rem 0' },
        el('label', {}, T('Etapa: ', 'Stage: '), fName), el('label', {}, T('Local: ', 'Venue: '), fVenue),
        el('label', {}, T('Quando: ', 'When: '), fWhen), el('label', {}, T('Região: ', 'Region: '), fRegion)),
      el('div', { class: 'toolbar', style: 'margin:.4rem 0' },
        el('label', {}, T('Vagas regra 1: ', 'Rule 1 slots: '), fR1),
        el('label', {}, T('Regra 4 — 3♀: ', 'Rule 4 — 3♀: '), f3),
        el('label', {}, ' ≥2♀: ', f2), el('label', {}, ' ≥1♀: ', f1)),
      el('div', { class: 'two-col' },
        el('div', {}, el('div', { class: 'chart-title' }, T('Vagas por SEDE (regra 2) — "Sede = vagas"', 'Slots per SITE (rule 2) — "Site = slots"')), taSedes),
        el('div', {}, el('div', { class: 'chart-title' }, T('Vagas por SUPERSEDE (≤1 por sede membra)', 'Slots per SUPERSITE (≤1 per member site)')), taSuper)),
      el('div', { class: 'toolbar', style: 'margin-top:.5rem' },
        el('button', { class: 'btn', onclick: async () => {
          prevBox.innerHTML = ''; prevBox.append(el('p', { class: 'muted' }, T('calculando…', 'computing…')));
          try {
            const r = await call({ action: 'preview', config: cfg() });
            const p = r.preview || {};
            prevBox.innerHTML = '';
            prevBox.append(el('h3', {}, T('👁 Prévia — ', '👁 Preview — ') + (p.total || 0) + T(' classificados', ' qualified')),
              el('p', { class: 'small muted' }, T('vagas não usadas: ', 'unused slots: ') +
                Object.entries(p.unused || {}).map(([k, v]) => k + ': ' + v).join(' · ')),
              relationTable(p.classified || [], false),
              el('div', { class: 'toolbar', style: 'margin-top:.6rem' },
                el('button', { class: 'btn primary', onclick: async () => {
                  if (!confirm(T('Aplicar como RASCUNHO? (promoções manuais do comitê são preservadas; nada aparece no placar até Publicar)',
                                 'Apply as DRAFT? (manual committee promotions are kept; nothing shows on the scoreboard until you Publish)'))) return;
                  try {
                    await call({ action: 'apply', config: cfg(), name: fName.value, venue: fVenue.value, when: fWhen.value });
                    prevBox.innerHTML = ''; load();
                  } catch (e) { alert(e.message); }
                } }, T('✔ Aplicar rascunho', '✔ Apply draft'))));
          } catch (e) { prevBox.innerHTML = ''; prevBox.append(el('div', { class: 'error-box' }, e.message || 'erro')); }
        } }, T('👁 Prever classificados', '👁 Preview qualified')))));
  }

  return { panel, load };
}
