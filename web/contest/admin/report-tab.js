// contest/admin/report-tab.js — "Prova › Relatório": o relatório estático da prova num lugar só.
//   1. baixar o tar.gz (site navegável offline — GET admin/report);
//   2. PUBLICAR como histórico em /relatorio/<c>/ (admin/report-publish: publicar, republicar,
//      despublicar; o job roda em segundo plano e a caixa faz poll de 5 s só nela mesma);
//   3. relatórios PÚBLICOS das rodadas arquivadas (publish-round/unpublish-round).
// Até 05/09 (1) e (2) moravam no h2 de Situação e (3) em Rodadas — três lugares p/ o mesmo
// artefato. A caixa de publicação é PERSISTENTE e atualiza em lugar.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { fmtDate, downloadAuthed, swap, swapIf, sigOf } from '/shared/admin-ui.js';
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
    b.disabled = true; b.textContent = T('⏳ gerando…', '⏳ generating…', '⏳ generando…');
    try { await downloadAuthed(CONTEST, '/contest/admin/report?contest=' + enc(CONTEST), 'relatorio-' + CONTEST + '.tar.gz'); }
    finally { b.disabled = false; b.textContent = old; }
  } }, T('📦 Baixar tar.gz', '📦 Download tar.gz', '📦 Descargar tar.gz'));

  // --- 2. publicação (caixa persistente) ---------------------------------------------------
  const pubBox = el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' });
  const pubMsg = el('div', { class: 'small' });
  // PORTÃO DA PUBLICAÇÃO (auditoria 03/10/2026): o relatório é público e traz o placar completo, os enunciados e as
  // coortes — o servidor recusa antes do início, com o placar congelado (até o fim + 1 min; depois pede confirmação)
  // e com coorte não liberada. Aqui só se traduz e se confirma.
  const pubError = (e) => {
    const d = (e && e.data) || {};
    if (d.code === 'not_started') return T('A prova ainda não começou: o relatório traz os enunciados e ficaria público antes do início.', 'The contest has not started yet: the report has the statements and would be public before the start.', 'La competencia todavía no empezó: el informe trae los enunciados y quedaría público antes del inicio.');
    if (d.code === 'freeze_locked') {
      const at = d.release_at ? fmtDate(d.release_at) : '';
      return T(`Com o placar congelado, o relatório só pode ser publicado a partir de ${at} (fim da prova para todas as sedes + 1 min): ele mostra o placar completo.`, `With the scoreboard frozen, the report can only be published from ${at} (end of the contest for all sites + 1 min): it shows the full scoreboard.`, `Con el marcador congelado, el informe solo se puede publicar a partir de ${at} (fin de la competencia para todas las sedes + 1 min): muestra el marcador completo.`);
    }
    if (d.code === 'cohorts_not_released') return T('O contest tem coorte PRIVADA e os resultados não foram liberados: o relatório público mostra todos os times. Libere os resultados em Evento › Coortes.', 'The contest has a PRIVATE cohort and the results were not released: the public report shows every team. Release the results in Event › Cohorts.', 'La competencia tiene una cohorte PRIVADA y los resultados no se liberaron: el informe público muestra todos los equipos. Libera los resultados en Evento › Cohortes.');
    return (e && e.message) || T('falha', 'failed', 'fallido');
  };
  async function act(action, msg, extra) {
    if (msg && !confirm(msg)) return;
    pubMsg.className = 'small muted'; pubMsg.textContent = '…';
    try { P = await apiPost(PUB, Object.assign({ action }, extra || {}), G); pubMsg.textContent = ''; render(); }
    catch (e) {
      if (e && e.data && e.data.code === 'board_frozen' && !(extra && extra.force_frozen)
          && confirm(T('O placar ainda está CONGELADO: o relatório público mostra o placar completo antes da revelação. Publicar mesmo assim?',
            'The scoreboard is still FROZEN: the public report shows the full scoreboard before the reveal. Publish anyway?',
            'El marcador todavía está CONGELADO: el informe público muestra el marcador completo antes de la revelación. ¿Publicar de todos modos?'))) {
        return act(action, null, Object.assign({}, extra || {}, { force_frozen: true }));
      }
      pubMsg.className = 'small error-box'; pubMsg.textContent = pubError(e); pubRefresh();
    }
  }
  function pubRender() {
    const p = P, job = (p && p.job) || null;
    pubBox.innerHTML = '';
    if (job && job.state === 'running') {
      pubBox.append(el('span', { class: 'muted' }, T('⏳ publicando… (gera o site e troca de uma vez; ~1–2 min numa prova grande)', '⏳ publishing… (builds the site and swaps it at once; ~1–2 min for a large contest)', '⏳ publicando… (genera el sitio y lo reemplaza de una vez; ~1–2 min en una competencia grande)')));
      if (!pubTimer) pubTimer = setInterval(() => { if (!panel.hidden && panel.isConnected) pubRefresh(); }, 5000);   // só com o painel visível
      return;
    }
    if (pubTimer) { clearInterval(pubTimer); pubTimer = null; }
    if (job && job.state === 'error') pubBox.append(el('span', { class: 'pill bad', title: job.error || '' }, T('falha ao publicar', 'publish failed', 'falló la publicación')));
    if (p && p.published) {
      pubBox.append(el('a', { class: 'btn', href: p.url, target: '_blank' }, T('📑 Abrir o relatório publicado', '📑 Open the published report', '📑 Abrir el informe publicado')),
        el('span', { class: 'muted small' }, T('publicado em ', 'published on ', 'publicado el ') + fmtDate(p.at) + (p.by ? ' · ' + p.by : '') + (p.pages ? ' · ' + p.pages + T(' páginas', ' pages', ' páginas') : '')),
        el('button', { class: 'btn ghost', title: T('gera de novo e troca o site publicado', 'regenerate and replace the published site', 'regenerar y reemplazar el sitio publicado'),
          onclick: () => act('publish') }, T('🔄 Republicar', '🔄 Republish', '🔄 Republicar')),
        el('button', { class: 'btn ghost danger',
          onclick: () => act('unpublish', T('Despublicar o relatório? O endereço /relatorio/' + CONTEST + '/ deixa de existir e o botão sai da página inicial.',
                                            'Unpublish the report? /relatorio/' + CONTEST + '/ stops existing and the button leaves the home page.',
                                            '¿Despublicar el informe? La dirección /relatorio/' + CONTEST + '/ deja de existir y el botón sale de la página de inicio.')) }, T('Despublicar', 'Unpublish', 'Despublicar')));
    } else {
      pubBox.append(el('button', { class: 'btn',
        onclick: () => act('publish', T('Publicar o relatório estático em /relatorio/' + CONTEST + '/? Fica PÚBLICO (placar, runs, estatísticas, clarifications anônimas) e listado na página inicial e no /contests/.',
                                       'Publish the static report at /relatorio/' + CONTEST + '/? It becomes PUBLIC (scoreboard, runs, statistics, anonymous clarifications) and is listed on the home page and /contests/.',
                                       '¿Publicar el informe estático en /relatorio/' + CONTEST + '/? Queda PÚBLICO (marcador, envíos, estadísticas, aclaraciones anónimas) y aparece en la página de inicio y en /contests/.')) },
        T('📢 Publicar como histórico', '📢 Publish as history', '📢 Publicar como histórico')),
        el('span', { class: 'muted small' }, T('ainda não publicado', 'not published yet', 'todavía no publicado')));
    }
  }
  async function pubRefresh() { try { P = await apiGet(PUB, G); } catch { P = null; } render(); }

  // --- 3. rodadas arquivadas --------------------------------------------------------------
  const roundsBox = el('div', {});
  // EM LUGAR: o poll de 5 s durante a publicação só refaz a tabela de rodadas se ela MUDOU
  function roundsRender() {
    const rounds = (P && P.rounds) || [];
    swapIf(roundsBox, sigOf(rounds.map((r) => [r.slug, r.name, r.kind, r.public, r.url, r.at, r.pages])), () => roundsBuild(rounds));
  }
  function roundsBuild(rounds) {
    const wrap = el('div', {});
    if (!rounds.length) {
      if (has('rodadas')) wrap.append(el('p', { class: 'muted small' }, T('Nenhuma rodada arquivada com relatório ainda (o relatório da rodada nasce na promoção, em Evento › Rodadas).', 'No archived round with a report yet (a round report is created at promotion, in Event › Rounds).', 'Ninguna ronda archivada con informe todavía (el informe de la ronda se crea en la promoción, en Evento › Rondas).')));
      return wrap;
    }
    const tb = el('tbody');
    rounds.forEach((r) => tb.append(el('tr', {},
      el('td', {}, el('b', {}, r.name || r.slug), el('span', { class: 'small muted' }, ' · ' + r.slug + (r.kind ? ' · ' + r.kind : ''))),
      el('td', {}, r.public ? el('a', { class: 'pill ok', href: r.url, target: '_blank' }, T('público · abrir', 'public · open', 'público · abrir')) : el('span', { class: 'pill' }, T('não publicado', 'not published', 'no publicado'))),
      el('td', {}, el('button', { class: 'btn ghost' + (r.public ? ' danger' : ''), onclick: () => act(r.public ? 'unpublish-round' : 'publish-round',
        r.public ? null : T(`Publicar o relatório da rodada “${r.name || r.slug}” em ${r.url}? Fica PÚBLICO (placar, runs, estatísticas).`,
                             `Publish the “${r.name || r.slug}” round report at ${r.url}? It becomes PUBLIC (scoreboard, runs, statistics).`,
                             `¿Publicar el informe de la ronda “${r.name || r.slug}” en ${r.url}? Se vuelve PÚBLICO (marcador, runs, estadísticas).`), { round: r.slug }) },
        r.public ? T('despublicar', 'unpublish', 'despublicar') : T('🌐 publicar', '🌐 publish', '🌐 publicar'))))));
    wrap.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, T('Rodada', 'Round', 'Ronda')), el('th', {}, T('Estado', 'State', 'Estado')), el('th', {}, ''))), tb)),
      el('p', { class: 'muted small' }, T('O relatório de uma rodada é o gerado na promoção (auditoria; não se regenera). Publicado, ele aparece em /relatorio/<contest>/rodada/<slug>/ e a página inicial do relatório principal o linka ao ser (re)publicada.',
        'A round report is the one generated at promotion (audit; it is not regenerated). Once published it lives at /relatorio/<contest>/rodada/<slug>/ and the main report links to it when it is (re)published.',
        'El informe de una ronda es el que se genera en la promoción (auditoría; no se regenera). Una vez publicado, vive en /relatorio/<contest>/rodada/<slug>/ y el informe principal lo enlaza al ser (re)publicado.')));
    return wrap;
  }

  function render() { pubRender(); roundsRender(); }

  let built = false;
  function skeleton() {
    panel.innerHTML = '';
    panel.append(
      el('div', { class: 'section' },
        el('h2', {}, T('📑 Relatório da prova', '📑 Contest report', '📑 Informe de la competencia')),
        el('p', { class: 'muted small' }, T('Um site estático navegável (placar aberto, placar congelado, runs com veredicto canônico, clarifications anônimas, estatísticas, enunciados, tarefas do staff). Sem código-fonte, sem log de juiz, sem senha.',
          'A browsable static site (open scoreboard, frozen scoreboard, runs with canonical verdict, anonymous clarifications, statistics, statements, staff tasks). No source code, no judge log, no password.',
          'Un sitio estático navegable (marcador abierto, marcador congelado, runs con veredicto canónico, aclaraciones anónimas, estadísticas, enunciados, tareas del staff). Sin código fuente, sin log del juez, sin contraseña.')),
        el('div', { class: 'row', style: 'gap:.6rem;align-items:center;flex-wrap:wrap' }, dlBtn,
          el('span', { class: 'muted small' }, T('para guardar ou mandar aos participantes (abre em file:// ou em qualquer servidor web)', 'to keep or send to participants (opens from file:// or any web server)', 'para guardar o enviar a los participantes (se abre desde file:// o cualquier servidor web)')))),
      el('div', { class: 'section' },
        el('h2', {}, T('📢 Publicação (histórico do evento)', '📢 Publication (event history)', '📢 Publicación (histórico del evento)')),
        el('p', { class: 'muted small' }, T('Publicar deixa o mesmo site em /relatorio/<contest>/ e põe o botão 📑 Relatório no card do contest na página inicial e no /contests/. É público: publique quando tudo já foi divulgado. Republicar troca o site inteiro de uma vez; despublicar apaga o endereço.',
          'Publishing puts the same site at /relatorio/<contest>/ and adds the 📑 Report button to the contest card on the home page and /contests/. It is public: publish when everything is already out. Republishing swaps the whole site at once; unpublishing removes the address.',
          'Publicar pone el mismo sitio en /relatorio/<contest>/ y agrega el botón 📑 Informe a la tarjeta de la competencia en la página principal y en /contests/. Es público: publica cuando todo ya fue divulgado. Republicar reemplaza el sitio entero de una vez; despublicar elimina la dirección.')),
        pubBox, pubMsg),
      el('div', { class: 'section', hidden: !has('rodadas') },
        el('h2', {}, T('🔁 Relatórios das rodadas arquivadas', '🔁 Archived round reports', '🔁 Informes de las rondas archivadas')),
        roundsBox));
    built = true;
  }

  async function load() {
    if (!built) skeleton();
    await pubRefresh();
  }
  return { panel, load };
}
