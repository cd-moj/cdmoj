// contest/admin/rounds-tab.js — aba "🔁 Rodadas": aquecimento (dress rehearsal) e prova oficial
// NO MESMO contest. A rodada ativa é o `conf` (mesma coisa que ⚙️ Configurações e 📚 Problemas
// editam); as planejadas vivem no rounds.json até serem promovidas.
//
// PROMOVER arquiva a rodada corrente (submissões, veredictos, placar, logs — auditoria posterior),
// zera o placar e coloca a janela + os problemas da próxima no ar. O checklist vem do servidor:
// se houver job em voo, veredicto pendente ou review aberto, ele RECUSA (e explica por quê).
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { makeBankPanel, toLocalDT, dtToEpoch } from '/shared/contest-config/index.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const fmt = (e) => (+e ? new Date(+e * 1000).toLocaleString() : '—');
const KIND = { warmup: T('aquecimento', 'warm-up'), official: T('prova oficial', 'official contest'), extra: T('extra', 'extra') };
const STATE = {
  active:   { t: T('no ar', 'live'),        c: 'ok' },
  pending:  { t: T('planejada', 'planned'), c: '' },
  archived: { t: T('arquivada', 'archived'), c: '' },
};

export function makeRoundsTab(CONTEST, opts = {}) {
  const readOnly = !!opts.readOnly;           // juiz-chefe: acompanha, não promove
  const panel = el('div', { class: 'section' });
  const G = { contest: CONTEST, auth: true };
  let DATA = null, editing = '';

  const msg = el('div', { class: 'small', style: 'margin:.4rem 0' });
  const setMsg = (t, cls) => { msg.className = 'small ' + (cls || ''); msg.textContent = t; };
  const api = (body) => (body
    ? apiPost('/contest/admin/rounds?contest=' + enc(CONTEST), body, G)
    : apiGet('/contest/admin/rounds?contest=' + enc(CONTEST), G));

  async function act(body, okText) {
    try { const j = await api(body); setMsg(okText || T('✓ salvo', '✓ saved')); await load(); return j; }
    catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); throw e; }
  }

  // ---- promoção: checklist do servidor + confirmação digitando o id ----
  function promoteBox() {
    const pr = DATA.promote_ready || { ok: false, blockers: [] };
    const next = DATA.next || '';
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' },
      el('h3', { style: 'margin:.1rem 0 .4rem' }, T('🚀 Promover para a próxima rodada', '🚀 Promote to the next round')));
    if (!next) {
      box.append(el('p', { class: 'small muted' },
        T('Crie a próxima rodada (abaixo) para poder promover.', 'Create the next round (below) to be able to promote.')));
      return box;
    }
    box.append(el('p', { class: 'small muted', style: 'margin:.1rem 0 .5rem' },
      T(`A rodada no ar será ARQUIVADA (submissões, veredictos, placar e logs ficam guardados para auditoria) e “${next}” entra no ar com a janela e os problemas dela. Contas, senhas, sedes, cores de balão e time limits não mudam.`,
        `The live round will be ARCHIVED (submissions, verdicts, scoreboard and logs are kept for audit) and “${next}” goes live with its own window and problems. Accounts, passwords, sites, balloon colours and time limits are untouched.`)));
    const ul = el('ul', { style: 'margin:.2rem 0 .5rem 1.1rem' });
    if (pr.ok) {
      ul.append(el('li', { class: 'small', style: 'color:#0a7' },
        T('✓ tudo pronto: rodada encerrada, fila do juiz vazia, nenhum veredicto pendente.',
          '✓ all clear: round ended, judge queue empty, no pending verdict.')));
    } else {
      (pr.blockers || []).forEach(b => ul.append(el('li', { class: 'small' },
        el('b', {}, '⛔ ' + b.code), ' — ' + (b.detail || ''))));
    }
    box.append(ul);
    if (readOnly) return box;
    const force = el('input', { type: 'checkbox' });
    const go = el('button', { class: 'btn', onclick: async () => {
      const typed = prompt(T('Isto ARQUIVA a rodada no ar e ZERA o placar. Para confirmar, digite o id do contest (',
                            'This ARCHIVES the live round and RESETS the scoreboard. To confirm, type the contest id (') + CONTEST + '):');
      if (typed !== CONTEST) { setMsg(T('cancelado (id não confere) — nada foi alterado.', 'cancelled (id does not match) — nothing changed.'), 'error-box'); return; }
      setMsg(T('promovendo… (gerando o relatório da rodada e arquivando)', 'promoting… (generating the round report and archiving)'));
      try {
        const j = await api({ action: 'promote', to: next, force: force.checked });
        setMsg(T(`✓ “${j.from}” arquivada (${j.archived.submissions} submissões de ${j.archived.users} contas) — “${j.to}” no ar`,
                 `✓ “${j.from}” archived (${j.archived.submissions} submissions from ${j.archived.users} accounts) — “${j.to}” is live`));
        await load();
      } catch (e) {
        const bl = (e && e.body && e.body.blockers) || [];
        setMsg((e.message || T('falha', 'failed')) + (bl.length ? ': ' + bl.map(b => b.code).join(', ') : ''), 'error-box');
        await load();
      }
    } }, T('🚀 Promover agora', '🚀 Promote now'));
    box.append(el('div', { class: 'row', style: 'gap:.6rem;align-items:center' }, go,
      el('label', { class: 'small row', style: 'gap:.25rem' }, force,
        T('ignorar os bloqueadores (só em emergência)', 'ignore blockers (emergency only)'))));
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
      el('option', { value: k, selected: (r.kind || 'official') === k }, KIND[k])));
    const fld = (l, i) => el('div', { class: 'field' }, el('label', {}, l), i);
    box.append(el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap' },
      fld(T('nome', 'name'), nm), fld(T('tipo', 'kind'), kd),
      fld(T('início', 'start'), st), fld(T('fim', 'end'), en), fld(T('freeze (opcional)', 'freeze (optional)'), fz)));
    box.append(el('button', { class: 'btn', onclick: () => act({
      action: 'set', slug: r.slug, name: nm.value.trim(), kind: kd.value,
      start: dtToEpoch(st.value), end: dtToEpoch(en.value), freeze: dtToEpoch(fz.value),
    }) }, T('salvar janela', 'save window')));

    // problemas da rodada: lista editável + busca/sorteio no banco (o MESMO painel da aba Problemas)
    const probs = (r.problems || []).slice();
    const plist = el('div', { style: 'margin:.5rem 0' });
    const renderP = () => {
      plist.innerHTML = '';
      if (!probs.length) plist.append(el('div', { class: 'small muted' },
        T('nenhum problema nesta rodada ainda', 'no problems in this round yet')));
      probs.forEach((p, i) => plist.append(el('div', { class: 'row', style: 'gap:.5rem;align-items:center;padding:.15rem 0' },
        el('b', { style: 'min-width:2rem' }, p.letter || String.fromCharCode(65 + i)),
        el('span', { style: 'min-width:16rem' }, p.name || p.problem_id || p.bank_id),
        el('code', { class: 'small muted' }, p.bank_id || p.problem_id || ''),
        el('button', { class: 'btn ghost', onclick: () => { probs.splice(i, 1); renderP(); } }, '✕'))));
    };
    renderP();
    const saveP = el('button', { class: 'btn', onclick: () => act({
      action: 'problems', slug: r.slug,
      problems: probs.map((p, i) => ({ bank_id: p.bank_id || p.problem_id, name: p.name,
        letter: p.letter || String.fromCharCode(65 + i) })),
    }, T('✓ problemas da rodada salvos', '✓ round problems saved')) }, T('salvar problemas', 'save problems'));
    const bank = makeBankPanel({
      api: {
        meta: () => apiGet('/contest/admin/bank?contest=' + enc(CONTEST) + '&meta=1', G),
        draw: (p) => apiGet('/contest/admin/draw?contest=' + enc(CONTEST) + '&' + new URLSearchParams(p).toString(), G),
        search: (q) => apiGet('/contest/admin/bank?contest=' + enc(CONTEST) + '&limit=30&q=' + enc(q), G),
      },
      onAdd: (it) => { probs.push({ bank_id: it.id, name: it.title || it.id }); renderP(); },
      searchLabel: T('Problemas desta rodada (buscar no banco)', 'Problems for this round (search the bank)'),
      searchPlaceholder: T('🔎 título ou id…', '🔎 title or id…'),
      noQueryFilter: (items) => items.filter((x) => x.private),
      emptyHint: T('digite para buscar no banco', 'type to search the bank'),
    });
    box.append(el('h4', { style: 'margin:.6rem 0 .2rem' }, T('Problemas da rodada', 'Round problems')),
      el('p', { class: 'small muted', style: 'margin:.1rem 0 .3rem' },
        T('A lista entra no ar quando esta rodada for promovida (na rodada no ar, salvar aplica na hora).',
          'The list goes live when this round is promoted (on the live round, saving applies right away).')),
      plist, saveP, bank.el);
    return box;
  }

  function roundRow(r) {
    const s = STATE[r.state] || { t: r.state, c: '' };
    const row = el('div', { class: 'subcard', style: 'margin:.4rem 0' });
    const head = el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
      el('b', {}, r.name || r.slug),
      el('span', { class: 'pill ' + s.c }, s.t),
      el('span', { class: 'small muted' }, KIND[r.kind] || r.kind || ''),
      el('span', { class: 'small muted' }, fmt(r.start) + ' → ' + fmt(r.end)),
      (r.problems || []).length ? el('span', { class: 'small muted' },
        T(`${r.problems.length} problema(s)`, `${r.problems.length} problem(s)`)) : null);
    if (r.stats) head.append(el('span', { class: 'small muted' },
      T(`· ${r.stats.submissions} submissões de ${r.stats.users} contas`, `· ${r.stats.submissions} submissions from ${r.stats.users} accounts`)));
    row.append(head);

    const acts = el('div', { class: 'row', style: 'gap:.5rem;margin-top:.35rem;flex-wrap:wrap' });
    if (r.state === 'archived') {
      // o relatório é um SITE (páginas que se linkam), e a rota é autenticada por Bearer: quem
      // navega nele é o visualizador em /contest/rounds/, que busca cada página com o token e
      // reescreve os links internos. Link cru daria 401 e os links de dentro quebrariam.
      const view = (f) => '/contest/rounds/?c=' + enc(CONTEST) + '#' + enc(r.slug) + '/' + f;
      acts.append(
        el('a', { class: 'btn ghost', target: '_blank', href: view('index.html') },
          T('📊 placar arquivado', '📊 archived scoreboard')),
        el('a', { class: 'btn ghost', target: '_blank', href: view('runs.html') },
          T('submissões', 'submissions')));
      if (!readOnly) {
        acts.append(el('button', { class: 'btn ghost', onclick: () => act(
          { action: 'publish', slug: r.slug, on: !r.published },
          r.published ? T('✓ despublicada', '✓ unpublished') : T('✓ publicada para os times', '✓ published to the teams')) },
          r.published ? T('despublicar', 'unpublish') : T('publicar p/ os times', 'publish to teams')));
        acts.append(el('button', { class: 'btn ghost', onclick: async () => {
          const r2 = await fetch('/api/v1/contest/admin/round-archive?contest=' + enc(CONTEST) + '&round=' + enc(r.slug),
            { headers: { Authorization: 'Bearer ' + (getToken(CONTEST) || '') } });
          if (!r2.ok) { setMsg(T('falha ao baixar o arquivo', 'failed to download the archive'), 'error-box'); return; }
          const url = URL.createObjectURL(await r2.blob());
          const a = el('a', { href: url, download: CONTEST + '-' + r.slug + '.tar.gz' });
          document.body.append(a); a.click(); setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
        } }, T('⇣ arquivo bruto (tar.gz)', '⇣ raw archive (tar.gz)')));
      }
      if (r.published) acts.append(el('span', { class: 'pill ok' }, T('visível p/ os times', 'visible to teams')));
    } else if (!readOnly) {
      acts.append(el('button', { class: 'btn ghost', onclick: () => { editing = (editing === r.slug ? '' : r.slug); render(); } },
        editing === r.slug ? T('fechar', 'close') : T('✎ editar', '✎ edit')));
      if (r.state === 'pending') acts.append(el('button', { class: 'btn ghost', onclick: () => {
        if (confirm(T('Remover a rodada planejada?', 'Remove the planned round?'))) act({ action: 'remove', slug: r.slug });
      } }, T('remover', 'remove')));
    }
    if (acts.childNodes.length) row.append(acts);
    if (editing === r.slug && r.state !== 'archived') row.append(editor(r));
    return row;
  }

  function addBox() {
    const slug = el('input', { placeholder: 'oficial', style: 'width:9rem' });
    const nm = el('input', { placeholder: T('Prova oficial', 'Official contest'), style: 'min-width:12rem' });
    const kd = el('select', {}, ...['official', 'warmup', 'extra'].map(k => el('option', { value: k }, KIND[k])));
    const st = el('input', { type: 'datetime-local' });
    const en = el('input', { type: 'datetime-local' });
    const fld = (l, i) => el('div', { class: 'field' }, el('label', {}, l), i);
    return el('div', { class: 'subcard', style: 'margin:.6rem 0' },
      el('h3', { style: 'margin:.1rem 0 .4rem' }, T('➕ Nova rodada', '➕ New round')),
      el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap' },
        fld(T('id (a-z, 0-9, -)', 'id (a-z, 0-9, -)'), slug), fld(T('nome', 'name'), nm),
        fld(T('tipo', 'kind'), kd), fld(T('início', 'start'), st), fld(T('fim', 'end'), en)),
      el('button', { class: 'btn', style: 'margin-top:.3rem', onclick: () => act({
        action: 'add', slug: slug.value.trim().toLowerCase(), name: nm.value.trim(), kind: kd.value,
        start: dtToEpoch(st.value), end: dtToEpoch(en.value),
      }, T('✓ rodada criada', '✓ round created')) }, T('criar rodada', 'create round')));
  }

  function render() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('🔁 Rodadas da prova', '🔁 Contest rounds')),
      el('p', { class: 'small muted' },
        T('Aquecimento e prova oficial no MESMO contest: mesma URL, mesmo login, mesma configuração. A rodada no ar é a que está nas Configurações e nos Problemas; ao promover, o MOJ arquiva tudo o que aconteceu e coloca a próxima no ar.',
          'Warm-up and official contest in the SAME contest: same URL, same login, same configuration. The live round is the one in Settings and Problems; on promotion, the MOJ archives everything that happened and puts the next one live.')),
      msg);
    // "Registrei a prova primeiro e criei o aquecimento depois": a rodada PENDENTE começa antes
    // da ATIVA ⇒ promover seria o caminho ERRADO (arquivaria a prova vazia, e arquivo é
    // imutável). O certo é INVERTER editando as duas — este aviso ensina exatamente isso.
    const act = (DATA.rounds || []).find((r) => r.state === 'active');
    const early = (DATA.rounds || []).find((r) => r.state === 'pending' && act && r.start && act.start && r.start < act.start);
    if (early) {
      panel.append(el('div', { class: 'notice', style: 'margin:.4rem 0' },
        el('b', {}, T('⚠ A rodada planejada "', '⚠ The planned round "') + (early.name || early.slug)
          + T('" começa ANTES da rodada no ar.', '" starts BEFORE the live round.')),
        el('div', { class: 'small', style: 'margin-top:.25rem' },
          T('A rodada no ar é a que vive nas Configurações — NÃO promova (promover arquiva a rodada no ar, e arquivo não volta). Para a planejada rodar primeiro, INVERTA editando as duas aqui mesmo: troque janela, tipo e problemas entre elas (a edição da rodada no ar aplica na hora).',
            'The live round is the one in Settings — do NOT promote (promotion archives the live round, and archives are final). For the planned one to run first, SWAP by editing both rounds right here: exchange window, kind and problems (edits to the live round apply immediately).'))));
    }
    (DATA.rounds || []).forEach(r => panel.append(roundRow(r)));
    if (!(DATA.rounds || []).length) panel.append(el('div', { class: 'small muted' },
      T('nenhuma rodada ainda', 'no rounds yet')));
    if (!readOnly) panel.append(promoteBox(), addBox());
  }

  async function load() {
    try { DATA = await api(); render(); }
    catch (e) {
      panel.innerHTML = '';
      panel.append(el('h2', {}, T('🔁 Rodadas da prova', '🔁 Contest rounds')),
        el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load')));
    }
  }
  return { panel, load };
}
