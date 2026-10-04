// Detalhes da saída de um motor de classificação (painel Evento › Classificação): avisos por código, blocos e
// vagas, a tabela geográfica com as frações, a participação por país, a lista de espera. Usado na prévia e no
// estágio gravado (stage.result). Só renderiza o que a saída traz: o motor BR não tem geo/lista e nada aparece.
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { pickLabel } from '/contest/score/score-classified.js';

// avisos dos motores, pelo código (o motor manda {code, data}); código desconhecido aparece cru, com o data
export const WARN_T = () => ({
  female_node_missing: T('Sem o recorte "Times femininos" no regions.json: nenhum time conta como feminino.',
    'No "Times femininos" slice in regions.json: no team counts as female.',
    'Sin el recorte "Times femininos" en regions.json: ningún equipo cuenta como femenino.'),
  female_multi_bucket: T('Time em mais de uma faixa feminina (vale a maior):', 'Team in more than one female bracket (the highest counts):',
    'Equipo en más de una franja femenina (vale la mayor):'),
  female_prefix_match: T('A lista feminina casa estes logins só por PREFIXO — confira a regex:', 'The female list matches these logins only by PREFIX — check the regex:',
    'La lista femenina coincide con estos logins solo por PREFIJO — revisa la regex:'),
  tie_boundary: T('Empate na fronteira de um bloco: o último que entrou e o primeiro que ficou de fora têm a mesma posição.',
    'Tie at a block boundary: the last team in and the first team out have the same place.',
    'Empate en el límite de un bloque: el último que entró y el primero que quedó fuera tienen la misma posición.'),
  geo_unfilled: T('Região sem time elegível para a vaga geográfica (a vaga fica sem uso):', 'Region with no eligible team for the geographic slot (the slot stays unused):',
    'Región sin equipo elegible para el cupo geográfico (el cupo queda sin uso):'),
  geo_tie_overflow: T('Empate de frações na última vaga geográfica: todas as regiões empatadas levaram — o total passou de N.',
    'Fraction tie at the last geographic slot: all tied regions got one — the total went over N.',
    'Empate de fracciones en el último cupo geográfico: todas las regiones empatadas recibieron uno — el total superó N.'),
  geo_no_room: T('Os passos 1 a 3 já ocuparam as N vagas: não sobrou vaga geográfica.', 'Steps 1 to 3 already used the N slots: no geographic slot left.',
    'Los pasos 1 a 3 ya ocuparon los N cupos: no quedó cupo geográfico.'),
  geo_stuck: T('As frações acabaram antes de completar N (confira as frações herdadas).', 'The fractions ran out before reaching N (check the carried fractions).',
    'Las fracciones se agotaron antes de completar N (revisa las fracciones heredadas).'),
  female_unfilled: T('Vaga feminina sem time elegível:', 'Female slot with no eligible team:', 'Cupo femenino sin equipo elegible:'),
  country_quota_unfilled: T('Cota de país sem instituição livre:', 'Country quota with no free institution:', 'Cuota de país sin institución libre:'),
  cycle_tie: T('Países empatados em times E instituições do ciclo — decida a ordem:', 'Countries tied on cycle teams AND institutions — decide the order:',
    'Países empatados en equipos E instituciones del ciclo — decide el orden:'),
  cycle_table_empty: T('Sem a tabela do ciclo do RCD: a prévia usa as contagens DESTE contest. Preencha cycle_teams/cycle_institutions antes da rodada real.',
    'No RCD cycle table: the preview uses the counts of THIS contest. Fill in cycle_teams/cycle_institutions before the real run.',
    'Sin la tabla del ciclo del RCD: la vista previa usa los conteos de ESTA competencia. Completa cycle_teams/cycle_institutions antes de la corrida real.'),
  host_schools_empty: T('Sem host_schools na config: o passo da instituição-sede (e os blocos da sede) ficam sem efeito.',
    'No host_schools in the config: the host institution step (and the host blocks) have no effect.',
    'Sin host_schools en la config: el paso de la institución sede (y los bloques de la sede) quedan sin efecto.'),
  host_condition_false: T('Uma escola-sede já tem time: o passo 3 não dá vaga.', 'A host school already has a team: step 3 gives no slot.',
    'Una escuela sede ya tiene equipo: el paso 3 no otorga cupo.'),
  school_missing: T('Times sem sigla nem nome de escola (cada um vira a própria escola):', 'Teams without school acronym or name (each one becomes its own school):',
    'Equipos sin sigla ni nombre de escuela (cada uno se vuelve su propia escuela):'),
  wf_region_unfilled: T('Região sem campeão elegível (≥1 resolvido): a vaga foi para o geral.', 'Region with no eligible champion (≥1 solved): the slot went to the overall ranking.',
    'Región sin campeón elegible (≥1 resuelto): el cupo pasó al general.'),
  n_wf_missing: T('Sem N_WF na config: informe as vagas da América Latina no Mundial.', 'No N_WF in the config: enter the Latin America World Finals slots.',
    'Sin N_WF en la config: indica los cupos de América Latina en el Mundial.'),
  n_wf_below_regions: T('N_WF menor que o número de regiões: só as primeiras regiões têm campeão classificado.', 'N_WF is smaller than the number of regions: only the first regions get a champion slot.',
    'N_WF menor que el número de regiones: solo las primeras regiones tienen campeón clasificado.'),
  award_tie: T('Empate atravessa a faixa de medalha (a medalha vai a mais times):', 'A tie crosses a medal band (more teams get the medal):',
    'Un empate atraviesa la franja de medalla (la medalla va a más equipos):'),
  sede_missing: T('Sedes com vaga na config que não existem no regions.json (a vaga não vai a ninguém):', 'Sites with slots in the config that do not exist in regions.json (the slot goes to nobody):',
    'Sedes con cupos en la config que no existen en regions.json (el cupo no va a nadie):'),
  supersede_missing: T('Supersedes com vaga na config que não existem sob a região no regions.json (a vaga não vai a ninguém):', 'Super-sites with slots in the config that do not exist under the region in regions.json (the slot goes to nobody):',
    'Supersedes con cupos en la config que no existen bajo la región en regions.json (el cupo no va a nadie):'),
  school_key_collision: T('A mesma chave de escola com nomes completos diferentes — confira se são a mesma instituição:',
    'The same school key with different full names — check that they are the same institution:',
    'La misma clave de escuela con nombres completos distintos — revisa si son la misma institución:'),
});

// o `data` de um aviso em texto legível ("região so · vagas 1 · preenchidas 0"); `L` traduz id de bloco
function fmtData(d, L) {
  const K = () => ({ region: T('região', 'region', 'región'), slots: T('vagas', 'slots', 'cupos'), filled: T('preenchidas', 'filled', 'ocupados'),
    block: T('bloco', 'block', 'bloque'), country: T('país', 'country', 'país'), quota: T('cota', 'quota', 'cuota'),
    place: T('posição', 'place', 'posición'), last: T('entrou', 'in', 'entró'), next: T('ficou de fora', 'left out', 'quedó fuera'),
    overflow: T('a mais', 'over', 'de más'), allocated: T('alocadas', 'allocated', 'asignados'), medal: T('medalha', 'medal', 'medalla'),
    teams: T('times', 'teams', 'equipos'), places: T('posições', 'places', 'posiciones'), countries: T('países', 'countries', 'países'),
    node: T('nó', 'node', 'nodo'), regions: T('regiões', 'regions', 'regiones'), sites: T('sedes', 'sites', 'sedes') });
  const k = K();
  return Object.entries(d || {}).map(([key, v]) => {
    let val = Array.isArray(v) ? v.map((x) => (typeof x === 'object' ? JSON.stringify(x) : String(x))).join(', ') : (typeof v === 'object' ? JSON.stringify(v) : String(v));
    if (key === 'block' && L) val = L(val);
    if ((key === 'region' || key === 'country') && typeof v === 'string') val = v.toUpperCase();
    return (k[key] || key) + ' ' + val;
  }).join(' · ');
}

// avisos agrupados por código (+ bloco): "Vaga feminina sem time elegível: Feminina por região — região BR · …; região CB · …"
export function warningsBox(ws, labels) {
  if (!ws || !ws.length) return null;
  const W = WARN_T();
  const L = (id) => { const x = (labels || {})[id]; return x ? pickLabel(x) : id; };
  const groups = [];
  ws.forEach((w) => {
    const d = Object.assign({}, w.data || {});
    const key = w.code + '|' + (d.block || '');
    let g = groups.find((x) => x.key === key);
    if (!g) { g = { key, code: w.code, block: d.block, parts: [] }; groups.push(g); }
    if (Array.isArray(d.logins)) g.parts.push(d.logins.join(', '));
    else { delete d.block; const t = fmtData(d, L); if (t) g.parts.push(t); }
  });
  return el('div', { class: 'warn-box', style: 'margin:.4rem 0' },
    el('b', {}, T('⚠ Avisos do motor', '⚠ Engine warnings', '⚠ Avisos del motor')),
    el('ul', { style: 'margin:.3rem 0 0 1.1rem' }, ...groups.map((g) => el('li', { class: 'small' },
      (W[g.code] || g.code) + (g.block ? ' ' + L(g.block) + (g.parts.length ? ' —' : '') : '') + (g.parts.length ? ' ' + g.parts.join('; ') : '')))));
}

const n2 = (x) => (x == null ? '—' : String(x));
const fr = (x) => (x == null ? '—' : (Math.round(Number(x) * 10000) / 10000).toString());
function table(head, rows) {
  return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj narrow' },
    el('thead', {}, el('tr', {}, ...head.map(([h, num]) => el('th', num ? { class: 'n' } : {}, h)))),
    el('tbody', {}, ...rows.map((r) => el('tr', {}, ...r.map(([v, num]) => el('td', num ? { class: 'n' } : {}, v)))))));
}

// resultDetails(p, labels) — os quadros da saída do motor (null se não há nada além da relação)
export function resultDetails(p, labels) {
  if (!p) return null;
  const L = (id) => { const x = (labels || {})[id] || (p.labels || {})[id]; return x ? pickLabel(x) : id; };
  const box = el('div', {});
  if (Array.isArray(p.blocks) && p.blocks.length) {
    box.append(el('h4', { style: 'margin:.7rem 0 .2rem' }, T('Blocos e vagas', 'Blocks and slots', 'Bloques y cupos')),
      table([[T('Bloco', 'Block', 'Bloque')], [T('Vagas', 'Slots', 'Cupos'), 1], [T('Usadas', 'Used', 'Usados'), 1]],
        p.blocks.map((b) => [[L(b.id)], [n2(b.slots), 1], [n2(b.used), 1]])));
  }
  if (p.countries) {
    const c = p.countries;
    box.append(el('p', { class: 'small' }, T('Passo 2: ', 'Step 2: ', 'Paso 2: ') + c.participating_without_team +
      T(' países participantes sem time; teto ', ' participating countries without a team; cap ', ' países participantes sin equipo; tope ') + c.cap +
      T(', usadas ', ', used ', ', usados ') + c.used +
      ((c.zero_solved || []).length ? T('. Só com 0 resolvidos: ', '. Only with 0 solved: ', '. Solo con 0 resueltos: ') + c.zero_solved.map((x) => x.toUpperCase()).join(', ') : '') + '.'));
  }
  if (p.host && p.host.condition != null) {
    box.append(el('p', { class: 'small' }, p.host.condition
      ? T('Passo 3: nenhuma escola-sede tinha time — 1 vaga ao melhor de escola sem time.', 'Step 3: no host school had a team — 1 slot to the best team from a school without one.', 'Paso 3: ninguna escuela sede tenía equipo — 1 cupo al mejor de escuela sin equipo.')
      : T('Passo 3: uma escola-sede já tinha time — sem vaga.', 'Step 3: a host school already had a team — no slot.', 'Paso 3: una escuela sede ya tenía equipo — sin cupo.')));
  }
  if (p.geo && Array.isArray(p.geo.regions)) {
    const g = p.geo;
    box.append(el('h4', { style: 'margin:.7rem 0 .2rem' }, T('Representação geográfica (passo 4)', 'Geographic representation (step 4)', 'Representación geográfica (paso 4)')),
      el('p', { class: 'small muted' }, T('Escolas na LATAM: ', 'Schools in LATAM: ', 'Escuelas en LATAM: ') + g.schools_latam +
        T(' · vagas restantes: ', ' · remaining slots: ', ' · cupos restantes: ') + g.remaining +
        (g.overflow ? T(' · passou de N em ', ' · over N by ', ' · superó N en ') + g.overflow : '') +
        T(' · conta em inteiros: q = escolas × restantes; vagas = q ÷ escolas da LATAM; fração = resto ÷ escolas da LATAM.',
          ' · integer math: q = schools × remaining; slots = q ÷ LATAM schools; fraction = remainder ÷ LATAM schools.',
          ' · cuenta en enteros: q = escuelas × restantes; cupos = q ÷ escuelas de LATAM; fracción = resto ÷ escuelas de LATAM.')),
      table([[T('Região', 'Region', 'Región')], [T('Escolas', 'Schools', 'Escuelas'), 1], ['q', 1], [T('Inteiras', 'Whole', 'Enteras'), 1],
        [T('Fração herdada', 'Carried fraction', 'Fracción heredada'), 1], [T('Fração', 'Fraction', 'Fracción'), 1], ['Extra', 1],
        [T('Vagas', 'Slots', 'Cupos'), 1], [T('Preenchidas', 'Filled', 'Ocupados'), 1], [T('Fração p/ o ano seguinte', 'Fraction for next year', 'Fracción para el año siguiente'), 1]],
        g.regions.map((r) => [[r.name || r.code], [n2(r.schools), 1], [n2(r.q), 1], [n2(r.nslots), 1], [fr(r.fraction_prev), 1], [fr(r.fraction), 1],
          [n2(r.extra), 1], [n2(r.slots), 1], [n2(r.filled), 1], [fr(r.fraction_out), 1]])));
    const fo = p.fractions_out || {};
    const snippet = JSON.stringify({ fractions_prev: fo });
    box.append(el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap;margin-top:.3rem' },
      el('code', { class: 'small' }, snippet),
      el('button', { class: 'btn ghost small', title: T('para a config do ano seguinte', 'for next year\'s config', 'para la config del año siguiente'),
        onclick: (ev) => {
          const b = ev && ev.target;
          const done = () => { if (b) b.textContent = T('✓ copiado', '✓ copied', '✓ copiado'); };
          try { navigator.clipboard.writeText(snippet).then(done, () => prompt('', snippet)); } catch (e) { prompt('', snippet); }
        } }, T('📋 Copiar frações p/ o ano seguinte', '📋 Copy fractions for next year', '📋 Copiar fracciones para el año siguiente'))));
  }
  const cp = p.country_participation || {};
  Object.entries(cp).forEach(([bid, x]) => {
    box.append(el('h4', { style: 'margin:.7rem 0 .2rem' }, L(bid) + ' — ' + (x.source === 'config'
      ? T('tabela do ciclo (RCD)', 'cycle table (RCD)', 'tabla del ciclo (RCD)')
      : T('contagens deste contest (prévia)', 'counts of this contest (preview)', 'conteos de esta competencia (vista previa)'))),
    table([['#', 1], [T('País', 'Country', 'País')], [T('Times', 'Teams', 'Equipos'), 1], [T('Instituições', 'Institutions', 'Instituciones'), 1],
      [T('Cota', 'Quota', 'Cuota'), 1], [T('Preenchidas', 'Filled', 'Ocupados'), 1]],
    (x.ranking || []).filter((r) => r.quota > 0 || r.rank <= 8).map((r) => [[n2(r.rank), 1], [String(r.country || '').toUpperCase()], [n2(r.teams), 1],
      [n2(r.institutions), 1], [n2(r.quota), 1], [n2(r.filled), 1]])));
  });
  if (p.reserve && p.reserve.slots) {
    box.append(el('p', { class: 'small' }, T('Reserva: ', 'Reserve: ', 'Reserva: ') + p.reserve.slots +
      T(' vaga(s) — o comitê as usa com "➕ Promover à mão" (via reserva).', ' slot(s) — the committee uses them with "➕ Promote by hand" (reserve route).',
        ' cupo(s) — el comité los usa con "➕ Promover a mano" (vía reserva).')));
  }
  if (p.awards) {
    const a = p.awards, md = a.medals || {};
    const who = (xs) => (xs || []).map((t) => (t.team || t.login) + ' (#' + t.place + ')').join(', ') || '—';
    box.append(el('h4', { style: 'margin:.7rem 0 .2rem' }, T('Prêmios (informativo)', 'Awards (informative)', 'Premios (informativo)')),
      table([[T('Prêmio', 'Award', 'Premio')], [T('Times', 'Teams', 'Equipos')]], [
        [[T('Campeão', 'Champion', 'Campeón')], [who(a.champion)]],
        [[T('🥇 Ouro', '🥇 Gold', '🥇 Oro')], [who(md.gold)]],
        [[T('🥈 Prata', '🥈 Silver', '🥈 Plata')], [who(md.silver)]],
        [[T('🥉 Bronze', '🥉 Bronze', '🥉 Bronce')], [who(md.bronze)]],
        ...(a.regional || []).map((r) => [[r.title || r.name || r.region], [(r.team || r.login) + ' (#' + r.place + ')']])]));
  }
  if (Array.isArray(p.waitlist)) {
    box.append(el('h4', { style: 'margin:.7rem 0 .2rem' }, T('Lista de espera', 'Waiting list', 'Lista de espera') + ' — ' + p.waitlist.length),
      p.waitlist.length
        ? table([['#', 1], [T('Faixa', 'Tier', 'Franja')], [T('Time', 'Team', 'Equipo')], [T('Escola', 'School', 'Escuela')], [T('Posição', 'Place', 'Posición'), 1]],
          p.waitlist.map((w) => [[n2(w.pos), 1], [(p.waitlist_tiers && p.waitlist_tiers[w.tier]) ? pickLabel(p.waitlist_tiers[w.tier]) : w.tier],
            [(w.team || w.login) + ' · ' + w.login], [w.univ || w.school || ''], [n2(w.place), 1]]))
        : el('p', { class: 'small muted' }, T('Vazia.', 'Empty.', 'Vacía.')));
  }
  return box.children.length ? box : null;
}
