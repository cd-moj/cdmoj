// Painel Evento › Classificação — as PRÓXIMAS FASES do contest (docs/CLASSIFICACAO.md). Um contest pode ter
// vários ESTÁGIOS (final-br e pda no da 1ª fase/regional, mundial no do Campeonato), cada um com o seu motor
// (catálogo do servidor: GET /contest/admin/classify → algorithms). Por estágio: prévia, rascunho → publicar,
// e o OVERRIDE MANUAL (salvaguarda): excluir do cálculo, retirar sem recalcular, promover à mão, desfazer —
// sempre com motivo, que fica interno (só este painel o mostra).
// O formulário do motor BR (form:"br") é o de sempre; os outros motores usam o editor JSON, semeado com a
// regra oficial (algorithms[].seed) e validado no servidor.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';
import { fmtEpoch } from '/shared/admin-ui.js';
import { pickLabel } from '/contest/score/score-classified.js';

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
const slotsText = (o) => Object.entries(o || {}).map(([k, v]) => k + ' = ' + v).join('\n');

// avisos dos motores, pelo código (o motor manda {code, data}); código desconhecido aparece cru
const WARN_T = () => ({
  female_node_missing: T('Sem o recorte "Times femininos" no regions.json: nenhum time conta como feminino.',
    'No "Times femininos" slice in regions.json: no team counts as female.',
    'Sin el recorte "Times femininos" en regions.json: ningún equipo cuenta como femenino.'),
  female_multi_bucket: T('Time em mais de uma faixa feminina (vale a maior):', 'Team in more than one female bracket (the highest counts):',
    'Equipo en más de una franja femenina (vale la mayor):'),
  female_prefix_match: T('A lista feminina casa estes logins só por PREFIXO — confira a regex:', 'The female list matches these logins only by PREFIX — check the regex:',
    'La lista femenina coincide con estos logins solo por PREFIJO — revisa la regex:'),
});
const OP_T = () => ({
  exclude: T('⊘ excluído do cálculo', '⊘ excluded from the computation', '⊘ excluido del cálculo'),
  withdraw: T('✂ retirado (vaga vaga)', '✂ withdrawn (slot left open)', '✂ retirado (cupo vacante)'),
  add: T('🛠 promovido à mão', '🛠 promoted by hand', '🛠 promovido a mano'),
});

export function makeClassifyTab(CONTEST) {
  const panel = el('div', { class: 'section' });
  const G = { contest: CONTEST, auth: true };   // auth:true = manda o Bearer (padrão das abas)
  const call = (body) => apiPost('/contest/admin/classify?contest=' + enc(CONTEST), body, G);

  const head = el('h2', {}, T('🎓 Classificação — próximas fases', '🎓 Qualification — next stages', '🎓 Clasificación — próximas etapas'));
  const barBox = el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;align-items:center;margin:.3rem 0 .6rem' });
  const stageBox = el('div', {});
  const cfgBox = el('div', {});
  const prevBox = el('div', {});
  const msg = el('div', { class: 'small' });
  panel.append(head, barBox, msg, stageBox, cfgBox, prevBox);

  let DATA = { stages: [], algorithms: [], vias: {}, manual_vias: [] };
  let SEL = null;          // id do estágio selecionado
  let NEW = null;          // {alg, id} quando criando uma etapa nova
  const PICK = {};         // estágio → motor escolhido no select (antes de aplicar)
  const showErr = (e) => { msg.className = 'small error-box'; msg.textContent = (e && e.message) || T('erro', 'error', 'error'); };
  const clearMsg = () => { msg.className = 'small'; msg.textContent = ''; };
  const algOf = (id) => DATA.algorithms.find((a) => a.id === id) || null;
  const stageOf = (id) => DATA.stages.find((s) => s.id === id) || null;
  // o motor de um estágio: o escolhido no select › o gravado › o do catálogo p/ esse id › o 1º do catálogo
  const algFor = (st, id) => PICK[id] || (st && st.config && st.config.algorithm) ||
    ((DATA.algorithms.find((a) => a.stage === id) || DATA.algorithms[0] || {}).id) || '';
  const viaLabel = (labels, v, short) => {
    const L = (labels && labels[v]) || DATA.vias[v];
    if (!L) return v;
    return pickLabel(short ? (L.short || L) : L);
  };
  const askReason = (txt) => {
    const r = prompt(txt + '\n' + T('Motivo (obrigatório; fica só no painel):', 'Reason (required; shown only in this panel):', 'Motivo (obligatorio; queda solo en este panel):'));
    return r == null ? null : r.trim();
  };
  const act = async (body) => { clearMsg(); try { await call(Object.assign({ stage: NEW ? NEW.id : SEL }, body)); await load(); } catch (e) { showErr(e); } };

  // --- tabela da relação, agrupada por via na ordem do estágio (via fora da ordem aparece no fim, pelo id) ---
  function relationTable(rel, labels, order, withActions) {
    const wrap = el('div', {});
    const vias = (order || []).slice();
    rel.forEach((t) => { if (!vias.includes(t.via)) vias.push(t.via); });
    vias.forEach((v) => {
      const rows = rel.filter((t) => t.via === v).sort((a, b) => (a.seq || a.place || 9e9) - (b.seq || b.place || 9e9));
      if (!rows.length) return;
      const tb = el('tbody');
      rows.forEach((t) => {
        const out = !!t.withdrawn;
        const note = out ? '✂ ' + T('retirado: ', 'withdrawn: ', 'retirado: ') + (t.withdrawn.reason || '')
          : (t.manual ? '🛠 ' + (t.reason || '') : '');
        const tr = el('tr', { style: out ? 'opacity:.55' : '' },
          el('td', { class: 'n' }, t.place != null && t.place !== '' ? String(t.place) : '—'),
          el('td', { style: out ? 'text-decoration:line-through' : '' }, t.team || t.login, el('span', { class: 'small muted' }, ' · ' + t.login)),
          el('td', { class: 'small' }, t.univ || t.school || ''),
          el('td', { class: 'small' }, t.sede || t.country || ''),
          el('td', { class: 'small muted' }, [t.detail || '', note].filter(Boolean).join(' · ')));
        if (withActions) {
          const td = el('td', { style: 'white-space:nowrap' });
          if (out) {
            td.append(el('button', { class: 'btn ghost small', title: T('desfazer a retirada', 'undo the withdrawal', 'deshacer el retiro'),
              onclick: () => act({ action: 'override_undo', id: t.withdrawn.id }) }, '↩'));
          } else if (t.manual) {
            td.append(el('button', { class: 'btn ghost small', title: T('desfazer a promoção manual', 'undo the manual promotion', 'deshacer la promoción manual'),
              onclick: () => { if (confirm(T('Desfazer a promoção manual de ', 'Undo the manual promotion of ', '¿Deshacer la promoción manual de ') + t.login + '?')) act({ action: 'override_undo', id: t.override }); } }, '↩'));
          } else {
            td.append(
              el('button', { class: 'btn ghost danger small', title: T('retirar SEM recalcular (a vaga fica vaga)', 'withdraw WITHOUT recomputing (the slot stays open)', 'retirar SIN recalcular (el cupo queda vacante)'),
                onclick: () => { const r = askReason(T('Retirar ', 'Withdraw ', 'Retirar ') + t.login + T(' sem recalcular? A vaga fica vaga.', ' without recomputing? The slot stays open.', ' sin recalcular? El cupo queda vacante.')); if (r) act({ action: 'withdraw', login: t.login, reason: r }); } }, '✂'),
              ' ',
              el('button', { class: 'btn ghost danger small', title: T('excluir do cálculo e recalcular (o próximo herda a vaga)', 'exclude from the computation and recompute (the next team inherits the slot)', 'excluir del cálculo y recalcular (el siguiente hereda el cupo)'),
                onclick: () => { const r = askReason(T('Excluir ', 'Exclude ', 'Excluir ') + t.login + T(' do cálculo? O próximo herda a vaga.', ' from the computation? The next team inherits the slot.', ' del cálculo? El siguiente hereda el cupo.')); if (r) act({ action: 'exclude', login: t.login, reason: r }); } }, '⊘'));
          }
          tr.append(td);
        }
        tb.append(tr);
      });
      wrap.append(el('h4', { style: 'margin:.7rem 0 .2rem' }, viaLabel(labels, v, false) + ' — ' + rows.filter((t) => !t.withdrawn).length),
        el('div', { class: 'chart-wrap' }, el('table', { class: 'moj narrow' },
          el('thead', {}, el('tr', {},
            el('th', { class: 'n' }, T('Posição', 'Place', 'Posición')), el('th', {}, T('Time', 'Team', 'Equipo')),
            el('th', {}, T('Escola', 'School', 'Escuela')), el('th', {}, T('Sede / país', 'Site / country', 'Sede / país')),
            el('th', {}, T('Detalhe', 'Detail', 'Detalle')), withActions ? el('th', {}, '') : null)), tb)));
    });
    return wrap;
  }

  function warningsBox(ws) {
    if (!ws || !ws.length) return null;
    const W = WARN_T();
    return el('div', { class: 'warn-box', style: 'margin:.4rem 0' },
      el('b', {}, T('⚠ Avisos do motor', '⚠ Engine warnings', '⚠ Avisos del motor')),
      el('ul', { style: 'margin:.3rem 0 0 1.1rem' }, ...ws.map((w) => {
        const d = w.data || {};
        const extra = Array.isArray(d.logins) ? ' ' + d.logins.join(', ') : (Object.keys(d).length ? ' ' + JSON.stringify(d) : '');
        return el('li', { class: 'small' }, (W[w.code] || w.code) + extra);
      })));
  }

  function overridesBox(ovs) {
    if (!ovs || !ovs.length) return null;
    const O = OP_T();
    const tb = el('tbody');
    ovs.forEach((o) => tb.append(el('tr', {},
      el('td', { class: 'small' }, o.id), el('td', { class: 'small' }, O[o.op] || o.op),
      el('td', {}, o.login || ('ext:' + (o.ext || '')), o.team ? el('span', { class: 'small muted' }, ' · ' + o.team) : null,
        o.op === 'add' && o.via && o.via !== 'manual' ? el('span', { class: 'small muted' }, ' · ' + viaLabel(null, o.via, true)) : null),
      el('td', { class: 'small' }, o.reason || ''),
      el('td', { class: 'small muted' }, (o.by || '') + (o.at ? ' · ' + fmtEpoch(o.at) : '')),
      el('td', {}, el('button', { class: 'btn ghost small', title: T('desfazer', 'undo', 'deshacer'),
        onclick: () => act({ action: 'override_undo', id: o.id }) }, '↩')))));
    return el('details', { open: true, style: 'margin-top:.6rem' },
      el('summary', {}, el('b', {}, T('🛠 Overrides manuais — ', '🛠 Manual overrides — ', '🛠 Overrides manuales — ') + ovs.length)),
      el('p', { class: 'small muted' }, T('Sobrevivem a um novo "Aplicar". O motivo é interno.', 'They survive a new "Apply". The reason is internal.', 'Sobreviven a un nuevo "Aplicar". El motivo es interno.')),
      el('div', { class: 'chart-wrap' }, el('table', { class: 'moj narrow' },
        el('thead', {}, el('tr', {}, el('th', {}, 'id'), el('th', {}, T('Ação', 'Action', 'Acción')), el('th', {}, T('Time', 'Team', 'Equipo')),
          el('th', {}, T('Motivo', 'Reason', 'Motivo')), el('th', {}, T('Quem / quando', 'Who / when', 'Quién / cuándo')), el('th', {}, ''))), tb)));
  }

  function addBox() {
    const mode = el('select', {}, el('option', { value: 'login' }, T('time do placar (login)', 'scoreboard team (login)', 'equipo del marcador (login)')),
      el('option', { value: 'ext' }, T('time de fora do placar', 'team outside the scoreboard', 'equipo fuera del marcador')));
    const login = el('input', { placeholder: 'login', style: 'min-width:150px' });
    const ext = el('input', { placeholder: T('id (ex.: lugia-usb)', 'id (e.g., lugia-usb)', 'id (ej.: lugia-usb)'), style: 'min-width:140px;display:none' });
    const team = el('input', { placeholder: T('nome do time', 'team name', 'nombre del equipo'), style: 'min-width:150px;display:none' });
    const univ = el('input', { placeholder: T('escola', 'school', 'escuela'), style: 'min-width:100px;display:none' });
    const via = el('select', {}, ...(DATA.manual_vias || ['manual']).map((v) => el('option', { value: v }, viaLabel(null, v, false))));
    const reason = el('input', { placeholder: T('motivo (obrigatório)', 'reason (required)', 'motivo (obligatorio)'), style: 'min-width:220px' });
    mode.onchange = () => { const e = mode.value === 'ext'; login.style.display = e ? 'none' : ''; [ext, team, univ].forEach((x) => { x.style.display = e ? '' : 'none'; }); };
    return el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;align-items:center;margin-top:.6rem' },
      mode, login, ext, team, univ, via, reason,
      el('button', { class: 'btn', onclick: () => {
        const r = reason.value.trim();
        if (!r) { showErr({ message: T('Informe o motivo.', 'Enter the reason.', 'Indica el motivo.') }); return; }
        const b = { action: 'add', via: via.value, reason: r };
        if (mode.value === 'ext') { b.ext = ext.value.trim(); b.team = team.value.trim(); if (univ.value.trim()) b.univ = univ.value.trim(); }
        else b.login = login.value.trim();
        act(b);
      } }, T('➕ Promover à mão', '➕ Promote by hand', '➕ Promover a mano')));
  }

  // --- o estágio selecionado: estado, publicar, relação com ações, overrides ---
  function renderStage(st) {
    stageBox.innerHTML = '';
    if (!st) {
      stageBox.append(el('p', { class: 'muted' }, T('Nenhuma classificação aplicada ainda — configure abaixo, faça a prévia e aplique.',
        'No qualification applied yet — configure below, preview and apply.', 'Ninguna clasificación aplicada todavía — configura abajo, previsualiza y aplica.')));
      return;
    }
    const pub = st.status === 'published';
    const rel = st.relation || [];
    const n = rel.filter((t) => !t.withdrawn).length;
    const alg = algOf((st.config && st.config.algorithm) || '');
    stageBox.append(el('div', { class: 'section', style: 'background:var(--card-bg,#f5f7fb)' },
      el('h3', {}, (st.name || st.id) + (st.venue ? ' — ' + st.venue : '') + (st.when ? ' · ' + st.when : '')),
      el('p', {}, pub
        ? el('b', { style: 'color:var(--ok,#1a7f37)' }, T('📢 PUBLICADO no placar', '📢 PUBLISHED on the scoreboard', '📢 PUBLICADA en el marcador'))
        : el('b', { style: 'color:var(--warn,#a66a00)' }, T('📝 RASCUNHO (só o admin vê)', '📝 DRAFT (admin only)', '📝 BORRADOR (solo admin)')),
        el('span', { class: 'small muted' }, ' · ' + T('chip ', 'chip ', 'chip ') + '“🎓 ' + (st.chip || st.id) + '” · ' + n + T(' time(s)', ' team(s)', ' equipo(s)') +
          ' · ' + T('motor: ', 'engine: ', 'motor: ') + (alg ? pickLabel(alg.name) : ((st.config && st.config.algorithm) || T('nenhum (só manual)', 'none (manual only)', 'ninguno (solo manual)'))) +
          (st.applied_at ? ' · ' + T('aplicado em ', 'applied on ', 'aplicado el ') + fmtEpoch(st.applied_at) : ''))),
      el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;align-items:center' },
        el('button', { class: pub ? 'btn ghost danger' : 'btn', onclick: async () => {
          if (pub) { if (!confirm(T('DESPUBLICAR do placar?', 'UNPUBLISH from the scoreboard?', '¿DESPUBLICAR del marcador?'))) return; }
          else {
            // publicar empurra o chip p/ TODO mundo que vê o placar: exige o id digitado (molde das rodadas)
            const typed = prompt(T(`PUBLICAR “${st.name || st.id}” no placar (chip para todos)? Digite o id do contest (${CONTEST}) para confirmar:`,
                                   `PUBLISH “${st.name || st.id}” on the scoreboard (chip for everyone)? Type the contest id (${CONTEST}) to confirm:`,
                                   `¿PUBLICAR “${st.name || st.id}” en el marcador (chip para todos)? Escribe el id de la competencia (${CONTEST}) para confirmar:`));
            if (typed === null) return;
            if (typed.trim() !== CONTEST) { showErr({ message: T('id não confere — nada publicado', 'id does not match — nothing published', 'el id no coincide — nada publicado') }); return; }
          }
          act({ action: pub ? 'unpublish' : 'publish' });
        } }, pub ? T('🔕 Despublicar', '🔕 Unpublish', '🔕 Despublicar') : T('📢 Publicar', '📢 Publish', '📢 Publicar')),
        pub ? null : el('button', { class: 'btn ghost danger', onclick: () => {
          if (confirm(T('Apagar o estágio em rascunho ', 'Delete the draft stage ', '¿Borrar la etapa en borrador ') + st.id + T('? (overrides inclusive)', '? (overrides included)', '? (overrides incluidos)'))) act({ action: 'delete' });
        } }, T('🗑 Apagar rascunho', '🗑 Delete draft', '🗑 Borrar borrador'))),
      warningsBox(st.result && st.result.warnings),
      relationTable(rel, st.labels, st.via_order, true),
      addBox(),
      overridesBox((st.overrides || []).filter((o) => o.op === 'exclude' || o.op === 'withdraw' || o.op === 'add'))));
  }

  // --- configuração + prévia + aplicar ---
  function renderConfig(st, stageId) {
    cfgBox.innerHTML = ''; prevBox.innerHTML = '';
    const algId = NEW ? NEW.alg : algFor(st, stageId);
    const alg = algOf(algId);
    if (!alg) {
      cfgBox.append(el('p', { class: 'muted small' }, T('Nenhum motor disponível (só promoções manuais).', 'No engine available (manual promotions only).', 'Ningún motor disponible (solo promociones manuales).')));
      return;
    }
    // motor: trocar no select só muda a tela; gravar num estágio de OUTRO motor pede confirmação (409)
    const fAlg = el('select', {}, ...DATA.algorithms.map((a) => el('option', { value: a.id, title: pickLabel(a.desc || '') }, pickLabel(a.name))));
    fAlg.value = algId;
    fAlg.onchange = () => {
      if (NEW) { const was = (algOf(NEW.alg) || {}).stage; NEW.alg = fAlg.value; if (!NEW.typed || NEW.id === was) NEW.id = (algOf(fAlg.value) || {}).stage || NEW.id; }
      else PICK[stageId] = fAlg.value;
      clearMsg(); render();
    };
    const cur = (st && st.config && st.config.algorithm === algId) ? st.config : null;
    const d = alg.defaults || {};
    const fName = el('input', { value: (st && st.name) || d.name || '', style: 'min-width:180px' });
    const fVenue = el('input', { value: (st && st.venue) || d.venue || '', style: 'min-width:120px' });
    const fWhen = el('input', { value: (st && st.when) || d.when || '', style: 'min-width:120px' });
    const fChip = el('input', { value: (st && st.chip) || d.chip || '', style: 'width:8rem' });
    let getCfg;
    const formBox = el('div', {});
    if (alg.form === 'br') {
      const c = cur || {};
      const fRegion = el('select', {}, el('option', { value: 'Brasil' }, T('Brasil', 'Brazil', 'Brasil')));
      const fR1 = el('input', { type: 'number', value: String(c.r1 != null ? c.r1 : 15), style: 'width:5rem' });
      const r4 = c.r4 || {};
      const f3 = el('input', { type: 'number', value: String(r4.f3 != null ? r4.f3 : 3), style: 'width:4rem' });
      const f2 = el('input', { type: 'number', value: String(r4.f2 != null ? r4.f2 : 2), style: 'width:4rem' });
      const f1 = el('input', { type: 'number', value: String(r4.f1 != null ? r4.f1 : 1), style: 'width:4rem' });
      const taSedes = el('textarea', { rows: 10, style: 'width:100%;font-family:var(--mono);font-size:.85rem' });
      const taSuper = el('textarea', { rows: 7, style: 'width:100%;font-family:var(--mono);font-size:.85rem' });
      taSedes.value = c.sedes ? slotsText(c.sedes) : DEFAULT_BR_SEDES;
      taSuper.value = c.supersedes ? slotsText(c.supersedes) : DEFAULT_BR_SUPER;
      getCfg = () => ({ algorithm: algId, region: fRegion.value, r1: Number(fR1.value) || 0,
        r4: { f3: Number(f3.value) || 0, f2: Number(f2.value) || 0, f1: Number(f1.value) || 0 },
        sedes: parseSlots(taSedes.value), supersedes: parseSlots(taSuper.value) });
      formBox.append(
        el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap;align-items:center;margin:.4rem 0' },
          el('label', {}, T('Região: ', 'Region: ', 'Región: '), fRegion),
          el('label', {}, T('Vagas regra 1: ', 'Rule 1 slots: ', 'Cupos regla 1: '), fR1),
          el('label', {}, T('Regra 4 — 3♀: ', 'Rule 4 — 3♀: ', 'Regla 4 — 3♀: '), f3),
          el('label', {}, ' ≥2♀: ', f2), el('label', {}, ' ≥1♀: ', f1)),
        el('div', { class: 'two-col' },
          el('div', {}, el('h4', { style: 'margin:.4rem 0 .2rem' }, T('Vagas por SEDE (regra 2) — "Sede = vagas"', 'Slots per SITE (rule 2) — "Site = slots"', 'Cupos por SEDE (regla 2) — "Sede = cupos"')), taSedes),
          el('div', {}, el('h4', { style: 'margin:.4rem 0 .2rem' }, T('Vagas por SUPERSEDE (≤1 por sede membra)', 'Slots per SUPERSITE (≤1 per member site)', 'Cupos por SUPERSEDE (≤1 por sede miembro)')), taSuper)));
    } else {
      // editor JSON semeado: a config do estágio › a semente oficial do motor › {}
      const ta = el('textarea', { rows: 22, spellcheck: 'false', style: 'width:100%;font-family:var(--mono);font-size:.8rem' });
      const seed = cur || alg.seed || {};
      ta.value = JSON.stringify(Object.assign({}, seed, { algorithm: algId }), null, 2);
      const jmsg = el('span', { class: 'small' });
      getCfg = () => {
        let o;
        try { o = JSON.parse(ta.value); } catch (e) { throw new Error(T('JSON inválido: ', 'Invalid JSON: ', 'JSON inválido: ') + e.message); }
        if (!o || typeof o !== 'object' || Array.isArray(o)) throw new Error(T('A config tem de ser um objeto JSON.', 'The config must be a JSON object.', 'La config debe ser un objeto JSON.'));
        o.algorithm = algId; return o;
      };
      formBox.append(
        el('p', { class: 'small muted' }, T('Config do motor em JSON (semeada com a regra oficial). O servidor valida ao prever/aplicar.',
          'Engine config in JSON (seeded with the official rule). The server validates it on preview/apply.',
          'Config del motor en JSON (sembrada con la regla oficial). El servidor la valida al previsualizar/aplicar.')),
        ta,
        el('div', { class: 'row', style: 'gap:.5rem;align-items:center;margin-top:.3rem' },
          el('button', { class: 'btn ghost small', onclick: () => {
            try { ta.value = JSON.stringify(getCfg(), null, 2); jmsg.className = 'small'; jmsg.textContent = '✓'; }
            catch (e) { jmsg.className = 'small error-box'; jmsg.textContent = e.message; }
          } }, T('Formatar / conferir', 'Format / check', 'Formatear / revisar')),
          alg.seed ? el('button', { class: 'btn ghost small', onclick: () => {
            if (confirm(T('Trocar o texto pela semente oficial?', 'Replace the text with the official seed?', '¿Reemplazar el texto por la semilla oficial?'))) ta.value = JSON.stringify(Object.assign({}, alg.seed, { algorithm: algId }), null, 2);
          } }, T('Restaurar a semente oficial', 'Restore the official seed', 'Restaurar la semilla oficial')) : null,
          jmsg));
    }

    const apply = async (cfg, force) => {
      if (!/^[a-z0-9-]{1,32}$/.test(stageId || '')) { showErr({ message: T('Informe o id da etapa (minúsculas, dígitos e -).', 'Enter the stage id (lowercase, digits and -).', 'Indica el id de la etapa (minúsculas, dígitos y -).') }); return; }
      const body = { action: 'apply', stage: stageId, config: cfg, name: fName.value, venue: fVenue.value, when: fWhen.value, chip: fChip.value };
      if (force) body.force = true;
      try { await call(body); SEL = stageId; NEW = null; delete PICK[stageId]; prevBox.innerHTML = ''; await load(); }
      catch (e) {
        if (e && e.data && e.data.code === 'stage_algorithm_mismatch' && !force) {
          if (confirm(T('Este estágio é de outro motor (', 'This stage belongs to another engine (', 'Esta etapa es de otro motor (') + (e.data.stage_algorithm || '') +
            T('). Trocar para ', '). Switch to ', '). ¿Cambiar a ') + algId + '?')) return apply(cfg, true);
          return;
        }
        showErr(e);
      }
    };

    cfgBox.append(el('details', { open: (st && st.config) ? null : true },
      el('summary', {}, el('b', {}, T('⚙️ Regras e vagas — ', '⚙️ Rules and slots — ', '⚙️ Reglas y cupos — ') + pickLabel(alg.name))),
      el('p', { class: 'small muted' }, pickLabel(alg.desc || '')),
      el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap;align-items:center;margin:.4rem 0' },
        el('label', {}, T('Motor: ', 'Engine: ', 'Motor: '), fAlg),
        el('label', {}, T('Etapa: ', 'Stage: ', 'Etapa: '), fName), el('label', {}, T('Local: ', 'Venue: ', 'Lugar: '), fVenue),
        el('label', {}, T('Quando: ', 'When: ', 'Cuándo: '), fWhen), el('label', {}, T('Chip: ', 'Chip: ', 'Chip: '), fChip)),
      formBox,
      el('div', { class: 'row', style: 'gap:.5rem;margin-top:.5rem' },
        el('button', { class: 'btn', onclick: async () => {
          clearMsg();
          let cfg; try { cfg = getCfg(); } catch (e) { showErr(e); return; }
          prevBox.innerHTML = ''; prevBox.append(el('p', { class: 'muted' }, T('calculando…', 'computing…', 'calculando…')));
          try {
            const r = await call({ action: 'preview', stage: stageId, config: cfg });
            const p = r.preview || {};
            const rel = r.relation || [];
            const n = rel.filter((t) => !t.withdrawn).length;
            const order = (p.via_order || alg.vias || []).concat(DATA.manual_vias || []);
            prevBox.innerHTML = '';
            prevBox.append(el('h3', {}, T('👁 Prévia — ', '👁 Preview — ', '👁 Vista previa — ') + n + T(' classificados', ' qualified', ' clasificados')),
              warningsBox(p.warnings),
              p.unused ? el('p', { class: 'small muted' }, T('vagas não usadas: ', 'unused slots: ', 'cupos no usados: ') +
                Object.entries(p.unused).map(([k, v]) => viaLabel(p.labels, k, true) + ': ' + v).join(' · ')) : null,
              (r.overrides || []).length ? el('p', { class: 'small' }, T('Com os overrides manuais do estágio (', 'With the stage manual overrides (', 'Con los overrides manuales de la etapa (') + r.overrides.length + ').') : null,
              relationTable(rel, p.labels || (st && st.labels), order, false),
              el('div', { class: 'row', style: 'gap:.5rem;margin-top:.6rem' },
                el('button', { class: 'btn', onclick: async () => {
                  const pubNow = st && st.status === 'published';
                  if (!confirm(pubNow
                    ? T('Este estágio está PUBLICADO: aplicar muda o placar NA HORA. Continuar? (os overrides manuais ficam)',
                        'This stage is PUBLISHED: applying changes the scoreboard IMMEDIATELY. Continue? (manual overrides are kept)',
                        'Esta etapa está PUBLICADA: aplicar cambia el marcador AL INSTANTE. ¿Continuar? (los overrides manuales se conservan)')
                    : T('Aplicar como RASCUNHO? (os overrides manuais ficam; nada aparece no placar até Publicar)',
                        'Apply as DRAFT? (manual overrides are kept; nothing shows on the scoreboard until you Publish)',
                        '¿Aplicar como BORRADOR? (los overrides manuales se conservan; nada aparece en el marcador hasta que Publiques)'))) return;
                  apply(cfg, false);
                } }, T('✔ Aplicar', '✔ Apply', '✔ Aplicar'))));
          } catch (e) { prevBox.innerHTML = ''; prevBox.append(el('div', { class: 'error-box' }, (e && e.message) || T('erro', 'error', 'error'))); }
        } }, T('👁 Prever classificados', '👁 Preview qualified', '👁 Prever clasificados')))));
  }

  // --- barra de estágios + "nova etapa" ---
  function renderBar() {
    barBox.innerHTML = '';
    const sel = el('select', {});
    DATA.stages.forEach((s) => sel.append(el('option', { value: s.id },
      (s.name || s.id) + ' · ' + s.id + (s.status === 'published' ? ' 📢' : ' 📝'))));
    sel.append(el('option', { value: '__new' }, T('＋ nova etapa…', '＋ new stage…', '＋ nueva etapa…')));
    sel.value = NEW ? '__new' : (SEL || '__new');
    sel.onchange = () => { clearMsg(); if (sel.value === '__new') newStage(); else { SEL = sel.value; NEW = null; } render(); };
    barBox.append(el('label', {}, T('Etapa: ', 'Stage: ', 'Etapa: '), sel));
    if (NEW) {
      const fid = el('input', { value: NEW.id, placeholder: 'id', style: 'width:9rem' });
      fid.oninput = () => { NEW.id = fid.value.trim(); NEW.typed = true; };
      fid.onchange = () => render();
      barBox.append(el('label', {}, T('id da etapa: ', 'stage id: ', 'id de la etapa: '), fid));
    }
  }
  // "nova etapa": o 1º motor do catálogo cujo estágio padrão ainda não existe (senão o 1º), com o id padrão dele
  // (todos os padrões já existem: id em branco, a pessoa digita)
  function newStage() {
    const a = DATA.algorithms.find((x) => x.stage && !stageOf(x.stage));
    NEW = a ? { alg: a.id, id: a.stage, typed: false } : { alg: (DATA.algorithms[0] || {}).id || '', id: '', typed: false };
  }

  function render() {
    // "nova etapa" com o id de um estágio que já existe = é ESSE estágio (as ações do painel vão p/ ele);
    // sem estágio nenhum, o painel abre direto no modo "nova etapa"
    if (NEW && stageOf(NEW.id)) {
      if (NEW.alg && !stageOf(NEW.id).config) PICK[NEW.id] = NEW.alg;   // estágio ainda sem motor: leva o escolhido
      SEL = NEW.id; NEW = null;
    }
    if (!NEW && !stageOf(SEL)) newStage();
    renderBar();
    if (NEW) { renderStage(null); renderConfig(null, NEW.id); return; }
    const st = stageOf(SEL);
    renderStage(st);
    renderConfig(st, st.id);
  }

  async function load() {
    try { DATA = await apiGet('/contest/admin/classify?contest=' + enc(CONTEST), G); }
    catch (e) { stageBox.innerHTML = ''; stageBox.append(el('div', { class: 'error-box' }, (e && e.message) || T('erro', 'error', 'error'))); return; }
    DATA.stages = DATA.stages || []; DATA.algorithms = DATA.algorithms || []; DATA.vias = DATA.vias || {};
    if (SEL && !stageOf(SEL)) SEL = null;
    if (!SEL && DATA.stages.length) SEL = DATA.stages[0].id;
    render();
  }

  return { panel, load };
}
