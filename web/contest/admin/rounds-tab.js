// contest/admin/rounds-tab.js — aba "🔁 Rodadas": aquecimento (dress rehearsal) e prova oficial
// NO MESMO contest. A rodada ativa é o `conf` (mesma coisa que ⚙️ Configurações e 📚 Problemas
// editam); as planejadas vivem no rounds.json até serem promovidas.
//
// PROMOVER arquiva a rodada corrente (submissões, veredictos, placar, logs — auditoria posterior),
// zera o placar e coloca a janela + os problemas da próxima no ar. O checklist vem do servidor:
// se houver job em voo, veredicto pendente ou review aberto, ele RECUSA (e explica por quê).
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { makeBankPanel, makeColorsEditor, toLocalDT, dtToEpoch } from '/shared/contest-config/index.js';
import { T } from '/shared/i18n.js';
import { fmtEpoch as fmt, downloadAuthed } from '/shared/admin-ui.js';
import { makeTitleChips } from '/shared/problem-titles.js';

const enc = encodeURIComponent;
// funções, não const de módulo: T() no topo congela o idioma ANTES do setLang(LOCALE)
const KIND = (k) => ({ warmup: T('aquecimento', 'warm-up', 'calentamiento'), official: T('prova oficial', 'official contest', 'competencia oficial'), extra: T('extra', 'extra', 'extra') }[k]);
const STATE = (k) => ({
  active:   { t: T('no ar', 'live', 'en vivo'),        c: 'ok' },
  pending:  { t: T('planejada', 'planned', 'planificada'), c: '' },
  archived: { t: T('arquivada', 'archived', 'archivada'), c: '' },
}[k]);

export function makeRoundsTab(CONTEST, opts = {}) {
  const readOnly = !!opts.readOnly;           // juiz-chefe: acompanha, não promove
  const panel = el('div', { class: 'section' });
  const G = { contest: CONTEST, auth: true };
  let DATA = null, PUB = null, editing = '';   // PUB = GET admin/report-publish (relatórios PÚBLICOS das rodadas)
  const PUBURL = '/contest/admin/report-publish?contest=' + enc(CONTEST);

  const msg = el('div', { class: 'small', style: 'margin:.4rem 0' });
  const setMsg = (t, cls) => { msg.className = 'small ' + (cls || ''); msg.textContent = t; };
  const api = (body) => (body
    ? apiPost('/contest/admin/rounds?contest=' + enc(CONTEST), body, G)
    : apiGet('/contest/admin/rounds?contest=' + enc(CONTEST), G));

  async function act(body, okText) {
    try { const j = await api(body); setMsg(okText || T('✓ salvo', '✓ saved', '✓ guardado')); await load(); return j; }
    catch (e) { setMsg(e.message || T('falha', 'failed', 'fallido'), 'error-box'); throw e; }
  }

  // ---- promoção: checklist do servidor + confirmação digitando o id ----
  function promoteBox() {
    const pr = DATA.promote_ready || { ok: false, blockers: [] };
    const next = DATA.next || '';
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' },
      el('h3', { style: 'margin:.1rem 0 .4rem' }, T('🚀 Promover para a próxima rodada', '🚀 Promote to the next round', '🚀 Promover a la siguiente ronda')),
      el('p', { class: 'small muted', style: 'margin:0 0 .4rem' },
        T('Antes: feche o login e derrube competidores e staff em ', 'Before: close login and log out competitors and staff in ', 'Antes: cierra el login y desconecta a competidores y staff en '),
        el('a', { href: '#pessoas/sessoes' }, T('Pessoas › Sessões › 🚪 Sair em massa', 'People › Sessions › 🚪 Mass logout', 'Personas › Sesiones › 🚪 Salir en masa')),
        T('; depois de promover, reabra o login lá.', '; after promoting, reopen login there.', '; después de promover, reabre el login ahí.')));
    if (!next) {
      box.append(el('p', { class: 'small muted' },
        T('Crie a próxima rodada (abaixo) para poder promover.', 'Create the next round (below) to be able to promote.', 'Crea la siguiente ronda (abajo) para poder promover.')));
      return box;
    }
    box.append(el('p', { class: 'small muted', style: 'margin:.1rem 0 .5rem' },
      T(`A rodada no ar será ARQUIVADA (submissões, veredictos, placar e logs ficam guardados para auditoria) e “${next}” entra no ar com a janela e os problemas dela. Contas, senhas, sedes e time limits não mudam. As cores de balão só mudam se “${next}” tiver cores próprias.`,
        `The live round will be ARCHIVED (submissions, verdicts, scoreboard and logs are kept for audit) and “${next}” goes live with its own window and problems. Accounts, passwords, sites and time limits are untouched. Balloon colours only change if “${next}” has its own colours.`,
        `La ronda activa será ARCHIVADA (envíos, veredictos, marcador y logs se conservan para auditoría) y “${next}” entra en vigor con su propia ventana y problemas. Cuentas, contraseñas, sedes y time limits no cambian. Los colores de los globos solo cambian si “${next}” tiene colores propios.`)));
    const ul = el('ul', { style: 'margin:.2rem 0 .5rem 1.1rem' });
    if (pr.ok) {
      ul.append(el('li', { class: 'small', style: 'color:#0a7' },
        T('✓ tudo pronto: rodada encerrada, fila do juiz vazia, nenhum veredicto pendente.',
          '✓ all clear: round ended, judge queue empty, no pending verdict.',
          '✓ todo listo: ronda terminada, cola del juez vacía, ningún veredicto pendiente.')));
    } else {
      (pr.blockers || []).forEach(b => ul.append(el('li', { class: 'small' },
        el('b', {}, '⛔ ' + b.code), ' — ' + T(b.detail || '', b.detail_en || null, b.detail_es || null))));
    }
    box.append(ul);
    if (readOnly) return box;
    const force = el('input', { type: 'checkbox' });
    const go = el('button', { class: 'btn', onclick: async () => {
      const typed = prompt(T('Isto ARQUIVA a rodada no ar e ZERA o placar. Para confirmar, digite o id do contest (',
                            'This ARCHIVES the live round and RESETS the scoreboard. To confirm, type the contest id (',
                            'Esto ARCHIVA la ronda activa y REINICIA el marcador. Para confirmar, escribe el id de la competencia (') + CONTEST + '):');
      if (typed !== CONTEST) { setMsg(T('cancelado (id não confere) — nada foi alterado.', 'cancelled (id does not match) — nothing changed.', 'cancelado (el id no coincide) — nada cambió.'), 'error-box'); return; }
      setMsg(T('promovendo… (gerando o relatório da rodada e arquivando)', 'promoting… (generating the round report and archiving)', 'promoviendo… (generando el informe de la ronda y archivando)'));
      try {
        const j = await api({ action: 'promote', to: next, force: force.checked });
        setMsg(T(`✓ “${j.from}” arquivada (${j.archived.submissions} submissões de ${j.archived.users} contas) — “${j.to}” no ar`,
                 `✓ “${j.from}” archived (${j.archived.submissions} submissions from ${j.archived.users} accounts) — “${j.to}” is live`,
                 `✓ “${j.from}” archivada (${j.archived.submissions} envíos de ${j.archived.users} cuentas) — “${j.to}” está activa`));
        await load();
      } catch (e) {
        const bl = (e && e.body && e.body.blockers) || [];
        setMsg((e.message || T('falha', 'failed', 'fallido')) + (bl.length ? ': ' + bl.map(b => b.code).join(', ') : ''), 'error-box');
        await load();
      }
    } }, T('🚀 Promover agora', '🚀 Promote now', '🚀 Promover ahora'));
    box.append(el('div', { class: 'row', style: 'gap:.6rem;align-items:center' }, go,
      el('label', { class: 'small row', style: 'gap:.25rem' }, force,
        T('ignorar os bloqueadores (só em emergência; não passa por cima do placar congelado)', 'ignore blockers (emergency only; does not override the frozen scoreboard)', 'ignorar los bloqueadores (solo en emergencia; no pasa por encima del marcador congelado)'))));
    return box;
  }

  // ---- DESFAZER a última promoção (TCP 2026, 03/10/2026: promoveram uma rodada extra depois da prova oficial
  // e o placar zerou). Só aparece quando há promoção a desfazer; o servidor decide se dá (rodada no ar sem
  // nenhuma atividade) e diz por quê quando não dá.
  function undoBox() {
    const u = DATA.undo;
    if (!u || !u.from || (u.blockers || []).some((b) => b.code === 'no_promotion')) return null;
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' },
      el('h3', { style: 'margin:.1rem 0 .4rem' }, T('↩ Desfazer a última promoção', '↩ Undo the last promotion', '↩ Deshacer la última promoción')),
      el('p', { class: 'small muted', style: 'margin:0 0 .4rem' },
        T(`Volta “${u.from}” para o ar com tudo o que ela tinha (submissões, veredictos, clarifications, placar) e “${u.to}” volta a ser planejada. Só funciona enquanto “${u.to}” não teve nenhuma atividade.`,
          `Brings “${u.from}” back live with everything it had (submissions, verdicts, clarifications, scoreboard), and “${u.to}” goes back to planned. It only works while “${u.to}” has had no activity.`,
          `Vuelve a poner “${u.from}” en vigor con todo lo que tenía (envíos, veredictos, clarifications, marcador) y “${u.to}” vuelve a planificada. Solo funciona mientras “${u.to}” no haya tenido ninguna actividad.`)));
    if (!u.possible) {
      const ul = el('ul', { style: 'margin:.2rem 0 .3rem 1.1rem' });
      (u.blockers || []).forEach((b) => ul.append(el('li', { class: 'small' }, el('b', {}, '⛔ ' + b.code), ' — ' + T(b.detail || '', b.detail_en || null, b.detail_es || null))));
      box.append(ul);
      return box;
    }
    if (readOnly) return box;
    box.append(el('button', { class: 'btn', onclick: async () => {
      const typed = prompt(T(`Desfazer a promoção: “${u.from}” volta ao ar e “${u.to}” volta a planejada. Para confirmar, digite o id do contest (`,
                            `Undo the promotion: “${u.from}” goes back live and “${u.to}” goes back to planned. To confirm, type the contest id (`,
                            `Deshacer la promoción: “${u.from}” vuelve a estar en vigor y “${u.to}” vuelve a planificada. Para confirmar, escribe el id de la competencia (`) + CONTEST + '):');
      if (typed !== CONTEST) { setMsg(T('cancelado (id não confere) — nada foi alterado.', 'cancelled (id does not match) — nothing changed.', 'cancelado (el id no coincide) — nada cambió.'), 'error-box'); return; }
      setMsg(T('desfazendo…', 'undoing…', 'deshaciendo…'));
      try {
        const j = await api({ action: 'undo', confirm: CONTEST });
        setMsg(T(`✓ “${j.restored}” de volta ao ar (${j.submissions} submissões) — “${j.pending}” voltou a planejada`,
                 `✓ “${j.restored}” is live again (${j.submissions} submissions) — “${j.pending}” is planned again`,
                 `✓ “${j.restored}” vuelve a estar en vigor (${j.submissions} envíos) — “${j.pending}” vuelve a planificada`));
      } catch (e) {
        const bl = (e && e.body && e.body.blockers) || [];
        setMsg((e.message || T('falha', 'failed', 'fallido')) + (bl.length ? ': ' + bl.map((b) => b.code).join(', ') : ''), 'error-box');
      }
      await load();
    } }, T('↩ Desfazer a última promoção', '↩ Undo the last promotion', '↩ Deshacer la última promoción')));
    return box;
  }

  // ---- editor de uma rodada planejada (janela + problemas) ----
  function editor(r) {
    const box = el('div', { class: 'subcard', style: 'margin:.4rem 0' });
    const st = el('input', { type: 'datetime-local', value: toLocalDT(r.start) });
    const en = el('input', { type: 'datetime-local', value: toLocalDT(r.end) });
    const fz = el('input', { type: 'datetime-local', value: toLocalDT(r.freeze) });
    const nm = el('input', { value: r.name || r.slug, style: 'min-width:14rem' });
    const kd = el('select', {}, ...['warmup', 'official', 'extra'].map(k =>
      el('option', { value: k, selected: (r.kind || 'official') === k }, KIND(k))));
    const fld = (l, i) => el('div', { class: 'field' }, el('label', {}, l), i);
    box.append(el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap' },
      fld(T('nome', 'name', 'nombre'), nm), fld(T('tipo', 'kind', 'tipo'), kd),
      fld(T('início', 'start', 'inicio'), st), fld(T('fim', 'end', 'fin'), en), fld(T('freeze (opcional)', 'freeze (optional)', 'congelamiento (opcional)'), fz)));
    box.append(el('button', { class: 'btn', onclick: () => act({
      action: 'set', slug: r.slug, name: nm.value.trim(), kind: kd.value,
      start: dtToEpoch(st.value), end: dtToEpoch(en.value), freeze: dtToEpoch(fz.value),
    }) }, T('salvar janela', 'save window', 'guardar ventana')));

    // problemas da rodada: lista editável + busca/sorteio no banco (o MESMO painel da aba Problemas)
    const probs = (r.problems || []).slice();
    const plist = el('div', { style: 'margin:.5rem 0' });
    const renderP = () => {
      plist.innerHTML = '';
      if (!probs.length) plist.append(el('div', { class: 'small muted' },
        T('nenhum problema nesta rodada ainda', 'no problems in this round yet', 'ningún problema en esta ronda todavía')));
      probs.forEach((p, i) => {
        // identificador editável (W1, Q… — não precisa ser A,B,C); salvo junto com a lista
        const letInp = el('input', { value: p.letter || String.fromCharCode(65 + i), maxlength: '3',
          style: 'width:3.6rem; font-family:var(--mono)' });
        letInp.addEventListener('input', () => { p.letter = letInp.value.trim(); });
        // nome: vazio = automático (o título no idioma da prova, na hora em que a rodada entra no ar); os chips
        // PT·EN·ES preenchem com o título de um idioma. Salvo junto com a lista.
        const pid = (p.bank_id || p.problem_id || '').replace('/', '#');
        const titles = p._titles || ((DATA && DATA.titles) || {})[pid];
        const nmInp = el('input', { value: p.name || '', style: 'min-width:14rem',
          placeholder: T('automático (idioma da prova)', 'automatic (contest language)', 'automático (idioma de la competencia)') });
        const chips = makeTitleChips(titles, () => nmInp.value, (v) => { nmInp.value = v; p.name = v; });
        nmInp.addEventListener('input', () => { p.name = nmInp.value; chips.repaint && chips.repaint(); });
        plist.append(el('div', { class: 'row', style: 'gap:.5rem;align-items:center;padding:.15rem 0;flex-wrap:wrap' },
          letInp, nmInp, chips,
          el('code', { class: 'small muted' }, p.bank_id || p.problem_id || ''),
          el('button', { class: 'btn ghost', onclick: () => { probs.splice(i, 1); renderP(); } }, '✕')));
      });
    };
    renderP();
    const saveP = el('button', { class: 'btn', onclick: () => act({
      action: 'problems', slug: r.slug,
      problems: probs.map((p, i) => ({ bank_id: p.bank_id || p.problem_id,
        ...((p.name || '').trim() ? { name: p.name.trim() } : {}),
        letter: p.letter || String.fromCharCode(65 + i) })),
    }, T('✓ problemas da rodada salvos', '✓ round problems saved', '✓ problemas de la ronda guardados')) }, T('salvar problemas', 'save problems', 'guardar problemas'));
    const bank = makeBankPanel({
      api: {
        meta: (q) => apiGet('/contest/admin/bank?contest=' + enc(CONTEST) + '&meta=1&' + new URLSearchParams(q || {}).toString(), G),
        draw: (p) => apiGet('/contest/admin/draw?contest=' + enc(CONTEST) + '&' + new URLSearchParams(p).toString(), G),
        search: (q) => apiGet('/contest/admin/bank?contest=' + enc(CONTEST) + '&limit=30&q=' + enc(q), G),
      },
      onAdd: (it) => { probs.push({ bank_id: it.id, name: '', ...(it.titles ? { _titles: it.titles } : {}) }); renderP(); },
      searchLabel: T('Problemas desta rodada (buscar no banco)', 'Problems for this round (search the bank)', 'Problemas de esta ronda (buscar en el banco)'),
      searchPlaceholder: T('🔎 título ou id…', '🔎 title or id…', '🔎 título o id…'),
      noQueryFilter: (items) => items.filter((x) => x.private),
      privateLabel: T('incluir no sorteio os privados do dono do contest', 'include the contest owner\'s private problems in the draw', 'incluir en el sorteo los privados del dueño de la competencia'),
      emptyHint: T('digite para buscar no banco', 'type to search the bank', 'escribe para buscar en el banco'),
    });
    box.append(el('h4', { style: 'margin:.6rem 0 .2rem' }, T('Problemas da rodada', 'Round problems', 'Problemas de la ronda')),
      el('p', { class: 'small muted', style: 'margin:.1rem 0 .3rem' },
        T('A lista entra no ar quando esta rodada for promovida (na rodada no ar, salvar aplica na hora). Você pode usar qualquer problema que o dono do contest pode ver: público, seu, de colaborador ou da sua org.',
          'The list goes live when this round is promoted (on the live round, saving applies right away). You can use any problem the contest owner can see: public, own, as collaborator or from the org.',
          'La lista entra en vigor cuando esta ronda es promovida (en la ronda activa, guardar aplica de inmediato). Puedes usar cualquier problema que el dueño de la competencia pueda ver: público, propio, como colaborador o de su org.')),
      plist, saveP, bank.el);

    // cores de balão DESTA rodada (2026-09-14): a rodada no ar mostra o balloons.json (o mesmo de
    // Evento › Balões); a planejada guarda as suas e as aplica quando for promovida. Sem cores
    // próprias, a planejada herda as que estiverem em vigor na hora.
    const letters = () => probs.map((p, i) => (p.letter || String.fromCharCode(65 + i)).toUpperCase());
    const hasOwn = !!(r.colors && Object.keys(r.colors).length);
    const ced = makeColorsEditor({ letters: letters(), initial: r.colors || {} });
    const cmsg = el('span', { class: 'small muted' });
    const saveC = el('button', { class: 'btn', onclick: () => {
      const v = ced.getValue();
      if (!Object.keys(v).length) { cmsg.textContent = T('nada mudou', 'nothing changed', 'nada cambió'); return; }
      act({ action: 'set', slug: r.slug, colors: v }, T('✓ cores da rodada salvas', '✓ round colours saved', '✓ colores de la ronda guardados'));
    } }, T('salvar cores', 'save colours', 'guardar colores'));
    const inherit = (r.state === 'active') ? null : el('button', { class: 'btn ghost', onclick: () => {
      if (!confirm(T('Esta rodada passa a herdar as cores que estiverem em vigor quando for promovida. Continuar?',
                     'This round will inherit the colours in force when it is promoted. Continue?',
                     'Esta ronda pasará a heredar los colores vigentes cuando sea promovida. ¿Continuar?'))) return;
      act({ action: 'set', slug: r.slug, colors: null }, T('✓ a rodada herda as cores em vigor', '✓ the round inherits the colours in force', '✓ la ronda hereda los colores vigentes'));
    } }, T('herdar as cores em vigor', 'inherit the colours in force', 'heredar los colores vigentes'));
    box.append(el('h4', { style: 'margin:.8rem 0 .2rem' }, T('🎈 Cores dos balões desta rodada', '🎈 Balloon colours for this round', '🎈 Colores de los globos de esta ronda')),
      el('p', { class: 'small muted', style: 'margin:.1rem 0 .3rem' },
        r.state === 'active'
          ? T('Estas são as cores em vigor (as mesmas de Evento › Balões). Salvar aplica na hora.',
              'These are the colours in force (the same as Event › Balloons). Saving applies right away.',
              'Estos son los colores vigentes (los mismos de Evento › Globos). Guardar aplica de inmediato.')
          : (hasOwn
            ? T('Esta rodada tem cores próprias. Elas entram no ar quando a rodada for promovida.',
                'This round has its own colours. They go live when the round is promoted.',
                'Esta ronda tiene colores propios. Entran en vigor cuando la ronda sea promovida.')
            : T('Esta rodada não tem cores próprias: ao ser promovida, herda as cores em vigor. Salve para dar cores próprias a ela.',
                'This round has no colours of its own: when promoted, it inherits the colours in force. Save to give it its own colours.',
                'Esta ronda no tiene colores propios: al ser promovida, hereda los colores vigentes. Guarda para darle colores propios.'))),
      ced.el, el('div', { class: 'row', style: 'gap:.6rem;align-items:center;margin-top:.4rem' }, saveC, inherit, cmsg));
    return box;
  }

  function roundRow(r) {
    const s = STATE(r.state) || { t: r.state, c: '' };
    const row = el('div', { class: 'subcard', style: 'margin:.4rem 0' });
    const head = el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
      el('b', {}, r.name || r.slug),
      el('span', { class: 'pill ' + s.c }, s.t),
      el('span', { class: 'small muted' }, KIND(r.kind) || r.kind || ''),
      el('span', { class: 'small muted' }, fmt(r.start) + ' → ' + fmt(r.end)),
      (r.problems || []).length ? el('span', { class: 'small muted' },
        T(`${r.problems.length} problema(s)`, `${r.problems.length} problem(s)`, `${r.problems.length} problema(s)`)) : null,
      (r.colors && Object.keys(r.colors).length && r.state !== 'archived') ? el('span', { class: 'pill', title: T('esta rodada tem cores de balão próprias', 'this round has its own balloon colours', 'esta ronda tiene colores de globo propios') },
        T('🎈 cores próprias', '🎈 own colours', '🎈 colores propios')) : null);
    if (r.stats) head.append(el('span', { class: 'small muted' },
      T(`· ${r.stats.submissions} submissões de ${r.stats.users} contas`, `· ${r.stats.submissions} submissions from ${r.stats.users} accounts`, `· ${r.stats.submissions} envíos de ${r.stats.users} cuentas`)));
    row.append(head);

    const acts = el('div', { class: 'row', style: 'gap:.5rem;margin-top:.35rem;flex-wrap:wrap' });
    if (r.state === 'archived') {
      // o relatório é um SITE (páginas que se linkam), e a rota é autenticada por Bearer: quem
      // navega nele é o visualizador em /contest/rounds/, que busca cada página com o token e
      // reescreve os links internos. Link cru daria 401 e os links de dentro quebrariam.
      const view = (f) => '/contest/rounds/?c=' + enc(CONTEST) + '#' + enc(r.slug) + '/' + f;
      acts.append(
        el('a', { class: 'btn ghost', target: '_blank', href: view('index.html') },
          T('📊 placar arquivado', '📊 archived scoreboard', '📊 marcador archivado')),
        el('a', { class: 'btn ghost', target: '_blank', href: view('runs.html') },
          T('submissões', 'submissions', 'envíos')));
      if (!readOnly) {
        acts.append(el('button', { class: 'btn ghost', onclick: () => act(
          { action: 'publish', slug: r.slug, on: !r.published },
          r.published ? T('✓ despublicada', '✓ unpublished', '✓ despublicada') : T('✓ publicada para os times', '✓ published to the teams', '✓ publicada para los equipos')) },
          r.published ? T('despublicar', 'unpublish', 'despublicar') : T('publicar p/ os times', 'publish to teams', 'publicar para los equipos')));
        acts.append(el('button', { class: 'btn ghost', onclick: () => downloadAuthed(CONTEST,
          '/contest/admin/round-archive?contest=' + enc(CONTEST) + '&round=' + enc(r.slug), CONTEST + '-' + r.slug + '.tar.gz') },
        T('⇣ arquivo bruto (tar.gz)', '⇣ raw archive (tar.gz)', '⇣ archivo bruto (tar.gz)')));
      }
      if (r.published) acts.append(el('span', { class: 'pill ok' }, T('visível p/ os times', 'visible to teams', 'visible para los equipos')));
      // relatório PÚBLICO da rodada (histórico): symlink relatorio-rodadas/<slug> servido pelo nginx em
      // /relatorio/<c>/rodada/<slug>/ e linkado na página inicial do relatório principal publicado
      const pr = ((PUB && PUB.rounds) || []).find((x) => x.slug === r.slug);
      // (ligar/desligar a publicação mora em Prova › Relatório — aqui só o atalho)
      if (pr && pr.public) acts.append(el('a', { class: 'btn ghost', target: '_blank', href: pr.url }, T('📑 relatório público', '📑 public report', '📑 informe público')));
      else if (pr && !readOnly) acts.append(el('a', { class: 'small', href: '#prova/relatorio' }, T('publicar o relatório em Prova › Relatório →', 'publish the report in Contest › Report →', 'publicar el informe en Competencia › Informe →')));
    } else if (!readOnly) {
      acts.append(el('button', { class: 'btn ghost', onclick: () => { editing = (editing === r.slug ? '' : r.slug); render(); } },
        editing === r.slug ? T('fechar', 'close', 'cerrar') : T('✎ editar', '✎ edit', '✎ editar')));
      if (r.state === 'pending') acts.append(el('button', { class: 'btn ghost', onclick: () => {
        if (confirm(T('Remover a rodada planejada?', 'Remove the planned round?', '¿Eliminar la ronda planificada?'))) act({ action: 'remove', slug: r.slug });
      } }, T('remover', 'remove', 'quitar')));
    }
    if (acts.childNodes.length) row.append(acts);
    if (editing === r.slug && r.state !== 'archived') row.append(editor(r));
    return row;
  }

  function addBox() {
    const slug = el('input', { placeholder: 'oficial', style: 'width:9rem' });
    const nm = el('input', { placeholder: T('Prova oficial', 'Official contest', 'Competencia oficial'), style: 'min-width:12rem' });
    const kd = el('select', {}, ...['official', 'warmup', 'extra'].map(k => el('option', { value: k }, KIND(k))));
    const st = el('input', { type: 'datetime-local' });
    const en = el('input', { type: 'datetime-local' });
    const fld = (l, i) => el('div', { class: 'field' }, el('label', {}, l), i);
    return el('div', { class: 'subcard', style: 'margin:.6rem 0' },
      el('h3', { style: 'margin:.1rem 0 .4rem' }, T('➕ Nova rodada', '➕ New round', '➕ Nueva ronda')),
      el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap' },
        fld(T('id (a-z, 0-9, -)', 'id (a-z, 0-9, -)', 'id (a-z, 0-9, -)'), slug), fld(T('nome', 'name', 'nombre'), nm),
        fld(T('tipo', 'kind', 'tipo'), kd), fld(T('início', 'start', 'inicio'), st), fld(T('fim', 'end', 'fin'), en)),
      el('button', { class: 'btn', style: 'margin-top:.3rem', onclick: () => act({
        action: 'add', slug: slug.value.trim().toLowerCase(), name: nm.value.trim(), kind: kd.value,
        start: dtToEpoch(st.value), end: dtToEpoch(en.value),
      }, T('✓ rodada criada', '✓ round created', '✓ ronda creada')) }, T('criar rodada', 'create round', 'crear ronda')));
  }

  function render() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('🔁 Rodadas da prova', '🔁 Contest rounds', '🔁 Rondas de la competencia')),
      el('p', { class: 'small muted' },
        T('Aquecimento e prova oficial no MESMO contest: mesma URL, mesmo login, mesma configuração. A rodada no ar é a que está nas Configurações e nos Problemas; ao promover, o MOJ arquiva tudo o que aconteceu e coloca a próxima no ar.',
          'Warm-up and official contest in the SAME contest: same URL, same login, same configuration. The live round is the one in Settings and Problems; on promotion, the MOJ archives everything that happened and puts the next one live.',
          'Calentamiento y competencia oficial en la MISMA competencia: misma URL, mismo login, misma configuración. La ronda activa es la que está en Configuración y Problemas; al promover, el MOJ archiva todo lo que pasó y pone la siguiente en vigor.')),
      msg);
    // "Registrei a prova primeiro e criei o aquecimento depois": a rodada PENDENTE começa antes
    // da ATIVA ⇒ promover seria o caminho ERRADO (arquivaria a prova vazia, e arquivo é
    // imutável). O certo é INVERTER editando as duas — este aviso ensina exatamente isso.
    const act = (DATA.rounds || []).find((r) => r.state === 'active');
    const early = (DATA.rounds || []).find((r) => r.state === 'pending' && act && r.start && act.start && r.start < act.start);
    if (early) {
      panel.append(el('div', { class: 'notice', style: 'margin:.4rem 0' },
        el('b', {}, T('⚠ A rodada planejada "', '⚠ The planned round "', '⚠ La ronda planificada "') + (early.name || early.slug)
          + T('" começa ANTES da rodada no ar.', '" starts BEFORE the live round.', '" empieza ANTES de la ronda activa.')),
        el('div', { class: 'small', style: 'margin-top:.25rem' },
          T('A rodada no ar é a que vive nas Configurações — NÃO promova (promover arquiva a rodada no ar, e arquivo não volta). Para a planejada rodar primeiro, INVERTA editando as duas aqui mesmo: troque janela, tipo e problemas entre elas (a edição da rodada no ar aplica na hora).',
            'The live round is the one in Settings — do NOT promote (promotion archives the live round, and archives are final). For the planned one to run first, SWAP by editing both rounds right here: exchange window, kind and problems (edits to the live round apply immediately).',
            'La ronda activa es la que vive en Configuración — NO promuevas (promover archiva la ronda activa, y los archivos son definitivos). Para que la planificada corra primero, INVIÉRTELAS editando las dos aquí mismo: intercambia ventana, tipo y problemas entre ellas (la edición de la ronda activa aplica de inmediato).'))));
    }
    (DATA.rounds || []).forEach(r => panel.append(roundRow(r)));
    if (!(DATA.rounds || []).length) panel.append(el('div', { class: 'small muted' },
      T('nenhuma rodada ainda', 'no rounds yet', 'ninguna ronda todavía')));
    if (!readOnly) panel.append(promoteBox(), addBox());
    { const ub = undoBox(); if (ub) panel.append(ub); }
  }

  async function load() {
    try { [DATA, PUB] = await Promise.all([api(), apiGet(PUBURL, G).catch(() => null)]); render(); }
    catch (e) {
      panel.innerHTML = '';
      panel.append(el('h2', {}, T('🔁 Rodadas da prova', '🔁 Contest rounds', '🔁 Rondas de la competencia')),
        el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load', 'falló al cargar')));
    }
  }
  return { panel, load };
}
