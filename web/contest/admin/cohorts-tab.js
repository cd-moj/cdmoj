// contest/admin/cohorts-tab.js — aba "🎭 Coortes": times oficiais × CONVIDADOS
// ("CCL"). Espelha POST /contest/admin/cohorts inteiro (add|set|rm|assign|materialize|release).
// Coorte PRIVADA não aparece no placar público nem em /contest/teams; `sees` diz quais coortes
// aquela visão enxerga (o convidado vê todos, o oficial não vê o convidado); EXTRA-OFICIAL entra
// intercalado sem consumir posição. "Liberar resultados" é o pós-prova: todos passam a ver todos.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { T } from '/shared/i18n.js';
import { PRIV_RE } from '/shared/admin-ui.js';

const enc = encodeURIComponent;

export function makeCohortsTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  let DATA = null, LOGINS = [];

  const post = (b) => apiPost('/contest/admin/cohorts?contest=' + enc(CONTEST), b, G);
  const say = (m, bad) => { const d = panel.querySelector('#chMsg'); if (!d) return; d.className = bad ? 'small error-box' : 'small'; d.textContent = m; };

  async function act(body, okMsg) {
    try { await post(body); say(okMsg); await load(); }
    catch (e) { say((e.message || T('falha', 'failed', 'fallido')), true); }
  }

  // ---- uma linha da tabela: campos editáveis + "vê" + ações
  function rowEl(c, all) {
    const name = el('input', { value: c.name || c.id, style: 'width:9rem' });
    const rx = el('input', {
      value: c.regex || '', style: 'width:8rem;font-family:var(--mono)',
      placeholder: c.default ? T('(o resto)', '(the rest)', '(el resto)') : '^ccl',
    });
    const pub = el('input', { type: 'checkbox', checked: c.public !== false });
    const unr = el('input', { type: 'checkbox', checked: c.unranked === true });
    const def = el('input', { type: 'radio', name: 'chDefault', checked: c.default === true });
    const sees = {};
    const seesBox = el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap' },
      ...all.map((o) => {
        const k = el('input', { type: 'checkbox', checked: (c.sees || []).includes(o.id) || o.id === c.id });
        if (o.id === c.id) { k.checked = true; k.disabled = true; k.title = T('a coorte sempre vê a si mesma', 'a cohort always sees itself', 'una cohorte siempre se ve a sí misma'); }
        sees[o.id] = k;
        return el('label', { class: 'small', style: 'white-space:nowrap' }, k, ' ', o.id);
      }));
    const n = (DATA.counts || {})[c.id] || 0;

    // `default` só vai quando MARCADO: mandar `false` na coorte que hoje é a default deixaria o
    // contest sem default nenhum e o servidor a moveria p/ a primeira da lista. Para mudar a
    // default, marca-se o rádio da OUTRA linha e salva-se AQUELA linha.
    const save = () => act({
      action: 'set', id: c.id, name: name.value.trim(), regex: rx.value.trim(),
      public: pub.checked, unranked: unr.checked, ...(def.checked ? { default: true } : {}),
      sees: all.map((o) => o.id).filter((id) => sees[id].checked),
    }, T(`Coorte "${c.id}" salva.`, `Cohort "${c.id}" saved.`, `Cohorte "${c.id}" guardada.`));
    const rm = () => {
      if (c.default) { say(T('a coorte default não pode ser removida', 'the default cohort cannot be removed', 'la cohorte por defecto no se puede eliminar'), true); return; }
      if (n > 0) { say(T(`${n} time(s) ainda estão em "${c.id}" — mova-os antes.`, `${n} team(s) are still in "${c.id}" — move them first.`, `${n} equipo(s) todavía están en "${c.id}" — muévelos primero.`), true); return; }
      if (!confirm(T(`Remover a coorte "${c.id}"?`, `Remove cohort "${c.id}"?`, `¿Eliminar la cohorte "${c.id}"?`))) return;
      act({ action: 'rm', id: c.id }, T('Coorte removida.', 'Cohort removed.', 'Cohorte eliminada.'));
    };

    return el('tr', {},
      el('td', { class: 'small', style: 'font-family:var(--mono);white-space:nowrap' }, c.id,
        c.default ? el('span', { class: 'pill', style: 'margin-left:.3rem' }, T('padrão', 'default', 'predeterminado')) : null),
      el('td', {}, name),
      el('td', {}, rx),
      el('td', { style: 'text-align:center' }, el('label', { title: T('aparece no placar público', 'shows in the public scoreboard', 'aparece en el marcador público') }, pub)),
      el('td', { style: 'text-align:center' }, el('label', { title: T('entra intercalado sem consumir posição', 'interleaved without taking a place', 'intercalado sin ocupar posición') }, unr)),
      el('td', { style: 'text-align:center' }, def),
      el('td', {}, seesBox),
      el('td', { style: 'text-align:right' }, String(n)),
      el('td', { style: 'white-space:nowrap' },
        el('button', { class: 'btn small', onclick: save }, T('salvar', 'save', 'guardar')), ' ',
        el('button', { class: 'btn ghost small danger', onclick: rm, title: T('remover', 'remove', 'quitar') }, '✕')));
  }

  function newForm(all) {
    const id = el('input', { placeholder: 'ccl', style: 'width:6rem;font-family:var(--mono)' });
    const name = el('input', { placeholder: T('Convidados (CCL)', 'Guests (CCL)', 'Invitados (CCL)'), style: 'width:11rem' });
    const rx = el('input', { placeholder: '^ccl', style: 'width:8rem;font-family:var(--mono)' });
    const pub = el('input', { type: 'checkbox' });
    const unr = el('input', { type: 'checkbox', checked: true });
    const add = () => {
      if (!id.value.trim()) { say(T('informe o id', 'enter the id', 'ingresa el id'), true); return; }
      act({
        action: 'add', id: id.value.trim(), name: name.value.trim(), regex: rx.value.trim(),
        public: pub.checked, unranked: unr.checked,
        // uma coorte nova de convidados nasce vendo TODAS (é o caso real do CCL)
        sees: pub.checked ? [] : all.map((o) => o.id),
      }, T('Coorte criada.', 'Cohort created.', 'Cohorte creada.'));
    };
    return el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;align-items:flex-end;margin-top:.5rem' },
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('id', 'id', 'id')), id),
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('nome', 'name', 'nombre')), name),
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('regex do login', 'login regex', 'regex de login')), rx),
      el('label', { class: 'small' }, pub, ' ', T('pública', 'public', 'pública')),
      el('label', { class: 'small' }, unr, ' ', T('extra-oficial', 'unranked', 'extraoficial')),
      el('button', { class: 'btn', onclick: add }, T('+ criar coorte', '+ create cohort', '+ crear cohorte')));
  }

  function assignBox() {
    const login = el('input', { placeholder: T('login do time', 'team login', 'login del equipo'), list: 'chLoginsDl', style: 'width:11rem;font-family:var(--mono)' });
    const sel = el('select', {}, el('option', { value: '' }, T('— pela regra (regex) —', '— by rule (regex) —', '— por regla (regex) —')),
      ...(DATA.cohorts || []).map((c) => el('option', { value: c.id }, c.id)));
    const go = () => {
      if (!login.value.trim()) { say(T('informe o login', 'enter the login', 'ingresa el login'), true); return; }
      act({ action: 'assign', login: login.value.trim(), cohort: sel.value },
        T('Time atribuído.', 'Team assigned.', 'Equipo asignado.'));
    };
    const nrx = (DATA.by_regex_only || []).length;
    return el('div', {},
      el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;align-items:flex-end' },
        el('div', { class: 'field' }, el('label', { class: 'small' }, T('time', 'team', 'equipo')), login),
        el('div', { class: 'field' }, el('label', { class: 'small' }, T('coorte', 'cohort', 'cohorte')), sel),
        el('button', { class: 'btn', onclick: go }, T('atribuir', 'assign', 'asignar')),
        el('span', { style: 'flex:1' }),
        el('button', {
          class: 'btn ghost', title: T('carimba .team.cohort em quem hoje só casa por regex', 'stamps .team.cohort on teams that today only match by regex', 'graba .team.cohort en los equipos que hoy solo coinciden por regex'),
          onclick: () => act({ action: 'materialize' }, T('Coortes materializadas.', 'Cohorts materialized.', 'Cohortes materializadas.')),
        }, T(`📌 Materializar (${nrx})`, `📌 Materialize (${nrx})`, `📌 Materializar (${nrx})`))),
      el('datalist', { id: 'chLoginsDl' }, ...LOGINS.map((l) => el('option', { value: l }))),
      el('div', { class: 'small muted', style: 'margin-top:.3rem' },
        T(`${nrx} time(s) hoje pertencem à coorte só pela regex — materializar transforma a regra em dado, e mudar o regex depois não remaneja ninguém.`,
          `${nrx} team(s) currently belong to a cohort only by regex — materializing turns the rule into data, so changing the regex later moves nobody.`,
          `${nrx} equipo(s) pertenecen hoy a una cohorte solo por regex — materializar convierte la regla en dato, así que cambiar el regex después no mueve a nadie.`)));
  }

  // GUEST_NUMBERING (issue #25): convidado (unranked) sai com "–" no lugar; com a opção ligada
  // ganha a posição na SEQUÊNCIA PRÓPRIA dos convidados (itálico), sem tocar na oficial.
  function guestNumberingBox() {
    const chk = el('input', { type: 'checkbox' });
    const msg = el('span', { class: 'small muted' });
    apiGet('/contest/admin/settings?contest=' + enc(CONTEST), G)
      .then((s) => { chk.checked = s.guest_numbering === true; }).catch(() => {});
    chk.addEventListener('change', async () => {
      try { await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), { guest_numbering: chk.checked }, G);
        msg.textContent = T('✓ salvo — o placar refaz em segundos', '✓ saved — the scoreboard rebuilds in seconds', '✓ guardado — el marcador se reconstruye en segundos'); }
      catch (e) { msg.textContent = e.message || T('falha', 'failed', 'fallido'); chk.checked = !chk.checked; }
    });
    return el('div', { class: 'subcard', style: 'margin:.6rem 0' },
      el('label', { class: 'row', style: 'gap:.4rem;align-items:center' }, chk,
        T('Numerar os convidados numa sequência própria', 'Number guest teams in their own sequence', 'Numerar los equipos invitados en su propia secuencia')),
      el('div', { class: 'small muted', style: 'margin-top:.2rem' },
        T('Convidado (extra-oficial) não consome posição oficial. Com esta opção ele mostra a posição entre os convidados, em itálico, no placar, na revelação e no relatório.',
          'A guest (unranked) team takes no official place. With this option it shows its position among the guest teams, in italics, on the scoreboard, in the reveal and in the report.',
          'Un equipo invitado (extraoficial) no ocupa posición oficial. Con esta opción muestra su posición entre los equipos invitados, en cursiva, en el marcador, en la revelación y en el informe.')),
      msg);
  }

  function releaseBox() {
    const on = DATA.results_released === true;
    const btn = el('button', { class: on ? 'btn ghost' : 'btn danger' }, on
      ? T('🔒 Voltar a esconder', '🔒 Hide again', '🔒 Ocultar de nuevo')
      : T('🔓 Liberar resultados', '🔓 Release results', '🔓 Liberar resultados'));
    btn.onclick = () => {
      if (!on) {
        const w = prompt(T(`Liberar os resultados torna TODOS os times visíveis a TODOS (inclusive os convidados no placar público). Digite o id do contest (${CONTEST}) para confirmar:`,
          `Releasing results makes ALL teams visible to EVERYONE (guests included in the public scoreboard). Type the contest id (${CONTEST}) to confirm:`,
          `Liberar los resultados hace que TODOS los equipos sean visibles para TODOS (invitados incluidos en el marcador público). Escribe el id de la competencia (${CONTEST}) para confirmar:`));
        if (w !== CONTEST) return;
      }
      act({ action: 'release', on: !on }, on ? T('Resultados escondidos.', 'Results hidden.', 'Resultados ocultos.') : T('Resultados liberados.', 'Results released.', 'Resultados liberados.'));
    };
    return el('div', { class: on ? 'alert' : '' },
      el('div', { class: 'row', style: 'gap:.6rem;align-items:center;flex-wrap:wrap' },
        el('b', {}, on ? T('Resultados LIBERADOS', 'Results RELEASED', 'Resultados LIBERADOS') : T('Resultados sob sigilo', 'Results under wraps', 'Resultados bajo reserva')),
        el('span', { class: 'small muted', style: 'flex:1' }, on
          ? T('todo mundo vê todo mundo — é o estado de pós-cerimônia.', 'everyone sees everyone — the post-ceremony state.', 'todos ven a todos — el estado post-ceremonia.')
          : T('cada visão vê só as coortes configuradas em "vê".', 'each view sees only the cohorts configured under "sees".', 'cada vista ve solo las cohortes configuradas en "ve".')),
        btn));
  }

  async function load() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('🎭 Coortes de placar', '🎭 Scoreboard cohorts', '🎭 Cohortes de marcador')),
      el('p', { class: 'small muted' },
        T('Separa times OFICIAIS de CONVIDADOS ("café com leite"). Uma coorte privada não aparece no placar público nem na lista de times; quem está nela pode ver as coortes marcadas em "vê". Extra-oficial entra intercalado no placar sem consumir posição. Juiz, staff e relatório continuam vendo todos, de propósito.',
          'Separates OFFICIAL from GUEST teams. A private cohort does not appear in the public scoreboard nor in the team list; whoever is in it sees the cohorts ticked under "sees". Unranked teams are interleaved in the scoreboard without taking a place. Judges, staff and the report keep seeing everyone, on purpose.',
          'Separa los equipos OFICIALES de los INVITADOS. Una cohorte privada no aparece en el marcador público ni en la lista de equipos; quien está en ella ve las cohortes marcadas en "ve". Los equipos extraoficiales se intercalan en el marcador sin ocupar posición. Jueces, staff y el informe siguen viendo a todos, a propósito.')));
    let d, u;
    try {
      [d, u] = await Promise.all([
        apiGet('/contest/admin/cohorts?contest=' + enc(CONTEST), G),
        apiGet('/contest/admin/users?contest=' + enc(CONTEST), G).catch(() => ({ users: [] })),
      ]);
    } catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || T('erro', 'error', 'error')))); return; }
    DATA = d; LOGINS = ((u && u.users) || []).map((x) => x.login).filter((l) => !PRIV_RE.test(l));
    const all = DATA.cohorts || [];

    panel.append(releaseBox());
    panel.append(guestNumberingBox());
    if (!all.length) {
      panel.append(el('div', { class: 'small muted', style: 'margin:.5rem 0' },
        T('Nenhuma coorte — o contest se comporta como sempre (um placar só, todos oficiais). Criar a primeira coorte é o que liga o mecanismo.',
          'No cohorts — the contest behaves as always (a single scoreboard, everyone official). Creating the first cohort is what turns the mechanism on.',
          'Sin cohortes — la competencia se comporta como siempre (un solo marcador, todos oficiales). Crear la primera cohorte es lo que activa el mecanismo.')));
    } else {
      const tb = el('table', { class: 'moj' },
        el('thead', {}, el('tr', {},
          el('th', {}, 'id'), el('th', {}, T('nome', 'name', 'nombre')), el('th', {}, T('regex do login', 'login regex', 'regex de login')),
          el('th', { title: T('aparece no placar público', 'shows in the public scoreboard', 'aparece en el marcador público') }, T('pública', 'public', 'pública')),
          el('th', { title: T('não consome posição', 'takes no place', 'no ocupa posición') }, T('extra-of.', 'unranked', 'extraoficial')),
          el('th', {}, T('padrão', 'default', 'predeterminado')), el('th', {}, T('vê', 'sees', 've')),
          el('th', { style: 'text-align:right' }, T('times', 'teams', 'equipos')), el('th', {}, ''))),
        el('tbody', {}, ...all.map((c) => rowEl(c, all))));
      panel.append(el('div', { class: 'chart-wrap' }, tb));
    }
    panel.append(newForm(all));
    panel.append(el('h3', { style: 'margin:.9rem 0 .3rem' }, T('🎯 Atribuir times', '🎯 Assign teams', '🎯 Asignar equipos')), assignBox());
    panel.append(el('div', { class: 'small muted', style: 'margin-top:.7rem' },
      T('Placares gerados: ', 'Generated scoreboards: ', 'Marcadores generados: '),
      ...(DATA.views || []).map((v) => el('span', { class: 'pill', style: 'margin-right:.3rem' }, v))),
      el('div', { class: 'small', id: 'chMsg', style: 'margin-top:.4rem' }));
  }

  return { panel, load };
}
