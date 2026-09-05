// contest/admin/report-tab.js — "Prova › Relatório": o relatório estático da prova num lugar só.
//   1. baixar o tar.gz (site navegável offline — GET admin/report);
//   2. PUBLICAR como histórico em /relatorio/<c>/ (admin/report-publish: publicar, republicar,
//      despublicar; o job roda em segundo plano e a caixa faz poll de 5 s só nela mesma);
//   3. relatórios PÚBLICOS das rodadas arquivadas (publish-round/unpublish-round).
// Até 05/09 (1) e (2) moravam no h2 de Situação e (3) em Rodadas — três lugares p/ o mesmo
// artefato. A caixa de publicação é PERSISTENTE e atualiza em lugar.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { fmtDate, downloadAuthed, swap } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

export function makeReportTab(CONTEST, opts = {}) {
  const G = { contest: CONTEST, auth: true };
  const has = typeof opts.has === 'function' ? opts.has : () => true;
  const panel = el('div', {});
  const PUB = '/contest/admin/report-publish?contest=' + enc(CONTEST);
  let pubTimer = null;
  let P = null;                       // último GET admin/report-publish

  // --- 1. download ------------------------------------------------------------------------
  const dlBtn = el('button', { class: 'btn', onclick: async (ev) => {
    const b = ev.currentTarget, old = b.textContent;
    b.disabled = true; b.textContent = T('⏳ gerando…', '⏳ generating…');
    try { await downloadAuthed(CONTEST, '/contest/admin/report?contest=' + enc(CONTEST), 'relatorio-' + CONTEST + '.tar.gz'); }
    finally { b.disabled = false; b.textContent = old; }
  } }, T('📦 Baixar tar.gz', '📦 Download tar.gz'));

  // --- 2. publicação (caixa persistente) ---------------------------------------------------
  const pubBox = el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' });
  const pubMsg = el('div', { class: 'small' });
  async function act(action, msg, extra) {
    if (msg && !confirm(msg)) return;
    pubMsg.className = 'small muted'; pubMsg.textContent = '…';
    try { P = await apiPost(PUB, Object.assign({ action }, extra || {}), G); pubMsg.textContent = ''; render(); }
    catch (e) { pubMsg.className = 'small error-box'; pubMsg.textContent = e.message || T('falha', 'failed'); pubRefresh(); }
  }
  function pubRender() {
    const p = P, job = (p && p.job) || null;
    pubBox.innerHTML = '';
    if (job && job.state === 'running') {
      pubBox.append(el('span', { class: 'muted' }, T('⏳ publicando… (gera o site e troca de uma vez; ~1–2 min numa prova grande)', '⏳ publishing… (builds the site and swaps it at once; ~1–2 min for a large contest)')));
      if (!pubTimer) pubTimer = setInterval(pubRefresh, 5000);
      return;
    }
    if (pubTimer) { clearInterval(pubTimer); pubTimer = null; }
    if (job && job.state === 'error') pubBox.append(el('span', { class: 'pill bad', title: job.error || '' }, T('falha ao publicar', 'publish failed')));
    if (p && p.published) {
      pubBox.append(el('a', { class: 'btn', href: p.url, target: '_blank' }, T('📑 Abrir o relatório publicado', '📑 Open the published report')),
        el('span', { class: 'muted small' }, T('publicado em ', 'published on ') + fmtDate(p.at) + (p.by ? ' · ' + p.by : '') + (p.pages ? ' · ' + p.pages + T(' páginas', ' pages') : '')),
        el('button', { class: 'btn ghost', title: T('gera de novo e troca o site publicado', 'regenerate and replace the published site'),
          onclick: () => act('publish') }, T('🔄 Republicar', '🔄 Republish')),
        el('button', { class: 'btn ghost danger',
          onclick: () => act('unpublish', T('Despublicar o relatório? O endereço /relatorio/' + CONTEST + '/ deixa de existir e o botão sai da página inicial.',
                                            'Unpublish the report? /relatorio/' + CONTEST + '/ stops existing and the button leaves the home page.')) }, T('Despublicar', 'Unpublish')));
    } else {
      pubBox.append(el('button', { class: 'btn',
        onclick: () => act('publish', T('Publicar o relatório estático em /relatorio/' + CONTEST + '/? Fica PÚBLICO (placar, runs, estatísticas, clarifications anônimas) e listado na página inicial e no /contests/.',
                                       'Publish the static report at /relatorio/' + CONTEST + '/? It becomes PUBLIC (scoreboard, runs, statistics, anonymous clarifications) and is listed on the home page and /contests/.')) },
        T('📢 Publicar como histórico', '📢 Publish as history')),
        el('span', { class: 'muted small' }, T('ainda não publicado', 'not published yet')));
    }
  }
  async function pubRefresh() { try { P = await apiGet(PUB, G); } catch { P = null; } render(); }

  // --- 3. rodadas arquivadas --------------------------------------------------------------
  const roundsBox = el('div', {});
  function roundsRender() {
    const rounds = (P && P.rounds) || [];
    roundsBox.innerHTML = '';
    if (!rounds.length) {
      if (has('rodadas')) roundsBox.append(el('p', { class: 'muted small' }, T('Nenhuma rodada arquivada com relatório ainda (o relatório da rodada nasce na promoção, em Evento › Rodadas).', 'No archived round with a report yet (a round report is created at promotion, in Event › Rounds).')));
      return;
    }
    const tb = el('tbody');
    rounds.forEach((r) => tb.append(el('tr', {},
      el('td', {}, el('b', {}, r.name || r.slug), el('span', { class: 'small muted' }, ' · ' + r.slug + (r.kind ? ' · ' + r.kind : ''))),
      el('td', {}, r.public ? el('a', { class: 'pill ok', href: r.url, target: '_blank' }, T('público · abrir', 'public · open')) : el('span', { class: 'pill' }, T('não publicado', 'not published'))),
      el('td', {}, el('button', { class: 'btn ghost' + (r.public ? ' danger' : ''), onclick: () => act(r.public ? 'unpublish-round' : 'publish-round',
        r.public ? null : T(`Publicar o relatório da rodada “${r.name || r.slug}” em ${r.url}? Fica PÚBLICO (placar, runs, estatísticas).`,
                             `Publish the “${r.name || r.slug}” round report at ${r.url}? It becomes PUBLIC (scoreboard, runs, statistics).`), { round: r.slug }) },
        r.public ? T('despublicar', 'unpublish') : T('🌐 publicar', '🌐 publish'))))));
    roundsBox.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, T('Rodada', 'Round')), el('th', {}, T('Estado', 'State')), el('th', {}, ''))), tb)),
      el('p', { class: 'muted small' }, T('O relatório de uma rodada é o gerado na promoção (auditoria; não se regenera). Publicado, ele aparece em /relatorio/<contest>/rodada/<slug>/ e a página inicial do relatório principal o linka ao ser (re)publicada.',
        'A round report is the one generated at promotion (audit; it is not regenerated). Once published it lives at /relatorio/<contest>/rodada/<slug>/ and the main report links to it when it is (re)published.')));
  }

  function render() { pubRender(); roundsRender(); }

  let built = false;
  function skeleton() {
    panel.innerHTML = '';
    panel.append(
      el('div', { class: 'section' },
        el('h2', {}, T('📑 Relatório da prova', '📑 Contest report')),
        el('p', { class: 'muted small' }, T('Um site estático navegável (placar aberto, placar congelado, runs com veredicto canônico, clarifications anônimas, estatísticas, enunciados, tarefas do staff). Sem código-fonte, sem log de juiz, sem senha.',
          'A browsable static site (open scoreboard, frozen scoreboard, runs with canonical verdict, anonymous clarifications, statistics, statements, staff tasks). No source code, no judge log, no password.')),
        el('div', { class: 'row', style: 'gap:.6rem;align-items:center;flex-wrap:wrap' }, dlBtn,
          el('span', { class: 'muted small' }, T('para guardar ou mandar aos participantes (abre em file:// ou em qualquer servidor web)', 'to keep or send to participants (opens from file:// or any web server)')))),
      el('div', { class: 'section' },
        el('h2', {}, T('📢 Publicação (histórico do evento)', '📢 Publication (event history)')),
        el('p', { class: 'muted small' }, T('Publicar deixa o mesmo site em /relatorio/<contest>/ e põe o botão 📑 Relatório no card do contest na página inicial e no /contests/. É público: publique quando tudo já foi divulgado. Republicar troca o site inteiro de uma vez; despublicar apaga o endereço.',
          'Publishing puts the same site at /relatorio/<contest>/ and adds the 📑 Report button to the contest card on the home page and /contests/. It is public: publish when everything is already out. Republishing swaps the whole site at once; unpublishing removes the address.')),
        pubBox, pubMsg),
      el('div', { class: 'section', hidden: !has('rodadas') },
        el('h2', {}, T('🔁 Relatórios das rodadas arquivadas', '🔁 Archived round reports')),
        roundsBox));
    built = true;
  }

  async function load() {
    if (!built) skeleton();
    await pubRefresh();
  }
  return { panel, load };
}
