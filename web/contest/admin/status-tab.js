// contest/admin/status-tab.js — "Operação › Situação": o dashboard AO VIVO da prova
// (auto-refresh 12s, só quando o painel está visível). Junta 3 fontes: /contest/admin/dashboard,
// /contest/admin/sessions e /contest/staff/queue — e transforma o que está fora do lugar em
// AÇÕES SUGERIDAS (juiz offline, pool inteiro fora, pendência esperando, conta compartilhada).
//
// ATUALIZAÇÃO EM LUGAR (regra da casa, CLAUDE.md › Frontend): o esqueleto (h2 + um contêiner por
// seção) nasce UMA vez; cada tick troca só a seção cuja ASSINATURA mudou (swapIf). Até 05/09 o
// refresh refazia o painel inteiro a cada 12 s — seleção de texto, scroll e botão "gerando…" iam
// junto.
import { el } from '/shared/ui.js';
import { apiGet } from '/shared/api.js';
import { fmtS, fmtClock, vClass, swap, swapIf, sigOf, everyVisible } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

export function makeStatusTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  let stopTimer = null;
  const card = (label, val, warn) => el('div', { class: 'dash-card' + (warn ? ' warn' : '') },
    el('div', { class: 'dash-val' }, String(val)), el('div', { class: 'dash-lbl' }, label));

  // --- esqueleto: um contêiner por seção, construído uma vez ---------------------------------
  const SK = {};
  function skeleton() {
    // (revelação, relatório e publicação têm casa própria: Central › Gerar e Prova › Relatório)
    SK.h2 = el('h2', {}, T('📊 Situação da prova', '📊 Contest status'));
    SK.err = el('div', {});
    for (const k of ['cards', 'routing', 'review', 'actions', 'judges', 'pending', 'perProblem', 'recent', 'timeline']) SK[k] = el('div', {});
    SK.foot = el('div', { class: 'small muted', style: 'margin-top:.6rem' });
    panel.innerHTML = '';
    panel.append(SK.h2, SK.err, SK.cards, SK.routing, SK.review, SK.actions, SK.judges, SK.pending, SK.perProblem, SK.recent, SK.timeline, SK.foot);
  }

  // --- construtores de seção (puros: recebem o dado, devolvem o nó) ---------------------------
  function buildCards(d, sess, tq) {
    const sub = d.submissions || {}, resp = sub.response || {}, j = d.judges || {};
    const online = sess ? (sess.sessions || []).length : '—';
    // tarefas do staff (impressão+balões): só quando existem
    const tasks = (tq && tq.requests) || [];
    const tPend = tasks.filter((t) => t.status === 'pending');
    const tOld = tPend.length ? Math.max(...tPend.map((t) => Math.floor(Date.now() / 1000) - (t.time || 0))) : 0;
    // balões que a regra do freeze suprimiu (nunca viram tarefa) — o admin tem de saber que
    // existem, senão o silêncio da fila durante o freeze parece defeito
    const bFrozen = (tq && Number(tq.balloons_frozen)) || 0;
    // primeiros-da-sede já materializados: é a cerimônia da sala acontecendo, e o admin
    // acompanha sem precisar da fila do staff (o campo só vem `true` depois de decidido).
    const bFirst = tasks.filter((t) => t.kind === 'balloon' && t.first_site).length;
    const taskCards = (tasks.length || bFrozen) ? [
      card(T('🖨️ impressões pend.', '🖨️ pending prints'), tPend.filter((t) => t.kind !== 'balloon').length, tOld > 600),
      card(T('🎈 balões pend.', '🎈 pending balloons'), tPend.filter((t) => t.kind === 'balloon').length, tOld > 600),
      ...(bFirst ? [card(T('★ primeiros da sede', '★ first-to-solve (site)'), bFirst, false)] : []),
      ...(bFrozen ? [card(T('🧊 balões retidos (freeze)', '🧊 balloons held (freeze)'), bFrozen, false)] : []),
    ] : [];
    return el('div', { class: 'dash-cards' },
      card(T('Logados', 'Logged in'), online),
      card(T('Juízes online', 'Judges online'), (j.online || 0) + '/' + (j.total || 0), (j.total || 0) > 0 && (j.online || 0) === 0),
      card(T('Juízes ocupados', 'Judges busy'), j.busy || 0),
      card(T('Fila', 'Queue'), (j.queue_depth || 0) + (j.assigned ? ' (+' + j.assigned + T(' em juiz)', ' in judge)') : ''), (j.queue_depth || 0) > 5),
      card(T('Pendentes', 'Pending'), sub.pending || 0, (sub.pending || 0) > 0),
      card(T('Maior espera', 'Longest wait'), fmtS(sub.max_wait_s), (sub.max_wait_s || 0) > 60),
      card(T('Resposta média', 'Avg response'), fmtS(resp.avg_s)),
      card(T('Resposta p95', 'p95 response'), fmtS(resp.p95_s), (resp.p95_s || 0) > 120),
      ...taskCards);
  }

  // ✍ roteamento do ESCRITOR (shards do judged): entrada/volta por shard + vivacidade
  // dos workers — a mesma fonte da aba Fila do treino (dashboard.routing).
  function buildRouting(rt) {
    if (!rt || !Array.isArray(rt.workers) || !rt.workers.length) return null;
    const chip = (w) => {
      const age = Number(w.alive_age_s);
      const dead = age < 0 || age > 120;
      const st = dead
        ? (age < 0 ? T('morto', 'dead') : T('parado ' + age + 's', 'stalled ' + age + 's'))
        : (age + 's');
      return el('span', { class: 'small', style: 'display:inline-block;margin:.15rem .35rem .15rem 0;padding:.2rem .55rem;border-radius:1rem;border:1px solid ' + (dead ? '#c00' : 'var(--line)') },
        's' + w.shard + ' ' + (dead ? '⚠ ' : '🟢 ') + st +
        T(' · entrada ', ' · in ') + (w.in_submit || 0) +
        T(' · volta ', ' · back ') + (w.in_results || 0) +
        ((w.in_other || 0) ? T(' · outros ', ' · other ') + w.in_other : ''));
    };
    return el('div', { style: 'margin-top:.5rem' },
      el('span', { class: 'small muted' },
        T('✍ Escritor: ', '✍ Writer: ') +
        (rt.shards > 1 ? rt.shards + T(' shards por hash(login)', ' shards by hash(login)') : T('único', 'single')) +
        T(' · entregues (5 min): ', ' · delivered (5 min): ') + (rt.delivered_5m || 0) + '  '),
      ...rt.workers.map(chip),
      (rt.orphans || 0) > 0
        ? el('span', { class: 'small', style: 'color:#c00;font-weight:600' },
            ' ⚠ ' + rt.orphans + T(' em shard órfão (conferir JUDGED_SHARDS nos 2 containers)', ' in orphan shard (check JUDGED_SHARDS on both containers)'))
        : '');
  }

  // ⚖️ avaliação manual de veredicto (só aparece quando há fila/conflito)
  function buildReview(rv) {
    if (!((rv.pending_total || 0) > 0 || (rv.being_evaluated || 0) > 0 || (rv.conflicts || 0) > 0)) return null;
    const ev = rv.evaluators || [];
    const rtb = el('tbody');
    ev.forEach((e) => rtb.append(el('tr', {},
      el('td', {}, (e.problem_id || '').split('#').pop()),
      el('td', { class: 'small' }, e.computed_verdict || ''),
      el('td', {}, e.conflict ? el('b', { style: 'color:#c00' }, T('conflito', 'conflict')) : (e.status || '')),
      el('td', { class: 'small' }, (e.claimants || []).map((c) => c.judge + ' (' + fmtS(c.elapsed_s) + ')').join(', ') || '—'))));
    return el('div', { style: 'margin-top:.7rem' }, el('h3', {}, T('⚖️ Avaliação manual', '⚖️ Manual evaluation')),
      el('div', { class: 'dash-cards' },
        card(T('Não avaliadas', 'Not evaluated'), rv.not_evaluated || 0, (rv.not_evaluated || 0) > 0),
        card(T('Sendo avaliadas', 'Being evaluated'), rv.being_evaluated || 0),
        card(T('Conflitos', 'Conflicts'), rv.conflicts || 0, (rv.conflicts || 0) > 0)),
      ev.length ? el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Problema', 'Problem')), el('th', {}, T('Computado', 'Computed')), el('th', {}, 'Status'), el('th', {}, T('Avaliando (tempo)', 'Evaluating (time)')))), rtb)) : '',
      (rv.conflicts || 0) > 0 ? el('p', { class: 'small' }, T('⚠ Resolva conflitos no ', '⚠ Resolve conflicts in the '), el('a', { href: '/contest/chief/?c=' + enc(CONTEST) }, T('painel do juiz-chefe', 'chief judge panel')), '.') : '');
  }

  // ações sugeridas (palpáveis): só aparecem quando há algo a fazer
  function computeActions(d, sess, tq) {
    const sub = d.submissions || {}, j = d.judges || {};
    const judges = j.list || [];
    const offline = judges.filter((x) => !x.online).length;
    // pool de juízes do contest (CONTEST_JUDGES; modelo ESTRITO — pool offline segura a fila)
    const pool = Array.isArray(j.pool) ? j.pool : [];
    const poolOnline = pool.filter((h) => judges.some((x) => x.host === h && x.online)).length;
    const alerts = sess ? (sess.alerts || []) : [];
    const tasks = (tq && tq.requests) || [];
    const tPend = tasks.filter((t) => t.status === 'pending');
    const tOld = tPend.length ? Math.max(...tPend.map((t) => Math.floor(Date.now() / 1000) - (t.time || 0))) : 0;
    const actions = [];
    if ((j.total || 0) === 0) actions.push(T('Nenhum juiz registrado — nada será julgado. Suba um agente de juiz.', 'No judge registered — nothing will be judged. Bring up a judge agent.'));
    else if ((j.online || 0) === 0) actions.push(T('Todos os juízes estão OFFLINE — submissões não serão julgadas. Verifique os agentes.', 'All judges are OFFLINE — submissions will not be judged. Check the agents.'));
    else if (offline > 0) actions.push(offline + T(' juiz(es) offline — capacidade reduzida.', ' judge(s) offline — reduced capacity.'));
    if (pool.length && poolOnline === 0)
      actions.push(T('Pool de juízes definido (', 'Judge pool defined (') + pool.join(', ') + T(') mas NENHUM host do pool está online — as submissões ficarão NA FILA até um voltar.', ') but NO pool host is online — submissions will WAIT IN THE QUEUE until one comes back.'));
    else if (pool.length && poolOnline < pool.length)
      actions.push(T('Pool de juízes com host offline (', 'Judge pool with offline host (') + pool.filter((h) => !judges.some((x) => x.host === h && x.online)).join(', ') + T(') — capacidade reduzida.', ') — reduced capacity.'));
    if ((sub.pending || 0) > 0 && (j.online || 0) > 0 && (j.busy || 0) === 0 && (sub.max_wait_s || 0) > 60)
      actions.push(T('Há pendências esperando >1min mas nenhum juiz ocupado — possível problema de fila/roteamento.', 'There are pending items waiting >1min but no judge busy — possible queue/routing problem.'));
    if ((sub.max_wait_s || 0) > 180) actions.push(T('Submissão esperando ', 'Submission waiting ') + fmtS(sub.max_wait_s) + T(' — investigar o juiz/linguagem.', ' — investigate the judge/language.'));
    if (tOld > 600) actions.push(T('Tarefa de impressão/balão pendente há ', 'Print/balloon task pending for ') + fmtS(tOld) + T(' — veja Operação › Staff (você pode agir por lá).', ' — see Operations › Staff (you can act there).'));
    alerts.forEach((a) => actions.push(a.login + T(' logado de ', ' logged in from ') + [a.multi_ip && 'IPs', a.multi_ua && T('máquinas/navegadores', 'machines/browsers')].filter(Boolean).join(T(' e ', ' and ')) + T(' diferentes — conta compartilhada?', ' — shared account?')));
    return actions;
  }
  const buildActions = (actions) => actions.length ? el('div', { class: 'section', style: 'background:#fff7ec;border:1px solid #f3c08e' },
    el('b', {}, T('⚠ Atenção', '⚠ Attention')), el('ul', { style: 'margin:.3rem 0 0; padding-left:1.2rem' }, ...actions.map((a) => el('li', {}, a)))) : null;

  // saúde dos juízes (por host); ⭐ = host do pool do contest
  function buildJudges(j) {
    const judges = j.list || [], pool = Array.isArray(j.pool) ? j.pool : [];
    const box = el('div', {}, el('h3', { style: 'margin:1rem 0 .3rem' }, T('🖥️ Juízes (', '🖥️ Judges (') + judges.length + ')' +
      (pool.length ? ' — pool: ' + pool.join(', ') : '')));
    if (!judges.length) { box.append(el('div', { class: 'flag-anom' }, T('Nenhum juiz registrado.', 'No judge registered.'))); return box; }
    const tb = el('tbody');
    judges.forEach((x) => tb.append(el('tr', {},
      el('td', {}, el('span', { class: x.online ? '' : 'flag-anom', title: pool.includes(x.host) ? T('no pool do contest', 'in the contest pool') : '' },
        (pool.includes(x.host) ? '⭐ ' : '') + (x.online ? '🟢 ' : '🔴 ') + x.host)),
      el('td', { class: 'small' }, x.state || '—'),
      el('td', { class: 'small' + (x.online ? '' : ' flag-anom') }, x.online ? 'online' : (T('offline há ', 'offline for ') + fmtS(x.age_s))),
      el('td', { class: 'small' }, String(x.problems_count || 0) + ' probs'),
      el('td', { class: 'small ua' }, (x.langs || []).join(' ')))));
    box.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, T('Juiz', 'Judge')), el('th', {}, T('Estado', 'State')), el('th', {}, T('Visto', 'Seen')), el('th', {}, 'Cache'), el('th', {}, T('Linguagens', 'Languages')))), tb)));
    return box;
  }

  // pendentes (ação: quem está esperando, há quanto tempo)
  function buildPending(pend) {
    const box = el('div', {}, el('h3', { style: 'margin:1rem 0 .3rem' }, T('⏳ Pendentes (', '⏳ Pending (') + pend.length + ')'));
    if (!pend.length) { box.append(el('div', { class: 'muted' }, T('Nenhuma submissão aguardando o juiz.', 'No submission waiting for the judge.'))); return box; }
    const tb = el('tbody');
    pend.forEach((p) => tb.append(el('tr', {}, el('td', {}, p.login), el('td', {}, p.problem),
      el('td', { class: 'small' }, fmtClock(p.submitted_at)),
      el('td', { class: p.waiting_s > 120 ? 'flag-anom' : (p.waiting_s > 30 ? 'flag-warn' : '') }, fmtS(p.waiting_s)))));
    box.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'Prob'), el('th', {}, T('Enviado', 'Sent')), el('th', {}, T('Esperando', 'Waiting')))), tb)));
    return box;
  }

  // atividade por problema
  function buildPerProblem(pp) {
    if (!pp.length) return null;
    const tb = el('tbody');
    pp.forEach((x) => tb.append(el('tr', {}, el('td', {}, el('b', {}, x.problem)),
      el('td', { class: 'n' }, String(x.submits)),
      el('td', { class: 'n' + (x.pending ? ' flag-anom' : '') }, String(x.pending)),
      el('td', { class: 'n' }, String(x.accepted)))));
    return el('div', {}, el('h3', { style: 'margin:1rem 0 .3rem' }, T('📚 Por problema', '📚 By problem')),
      el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Prob'), el('th', { class: 'n' }, 'Subs'), el('th', { class: 'n' }, 'Pend'), el('th', { class: 'n' }, 'AC'))), tb)));
  }

  // submissões recentes (feed palpável)
  function buildRecent(recent) {
    if (!recent.length) return null;
    const tb = el('tbody');
    recent.forEach((x) => tb.append(el('tr', {}, el('td', { class: 'small' }, fmtClock(x.at)),
      el('td', {}, x.login), el('td', {}, x.problem),
      el('td', {}, el('span', { class: vClass(x.verdict) }, x.verdict || '—')),
      el('td', { class: 'small' }, x.response_s != null ? fmtS(x.response_s) : (x.pending ? '⏳' : '—')))));
    return el('div', {}, el('h3', { style: 'margin:1rem 0 .3rem' }, T('🧾 Submissões recentes', '🧾 Recent submissions')),
      el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Hora', 'Time')), el('th', {}, 'Login'), el('th', {}, 'Prob'), el('th', {}, T('Veredicto', 'Verdict')), el('th', {}, T('Resposta', 'Response')))), tb)));
  }

  // timeline (submissões/min + espera média), escala correta sobre as barras visíveis
  function buildTimeline(tl) {
    if (!tl.length) return null;
    const maxS = Math.max(1, ...tl.map((b) => b.submits || 0));
    const maxW = Math.max(1, ...tl.map((b) => b.avg_wait_s || 0));
    const rows = tl.map((b) => {
      const peak = (b.avg_wait_s || 0) >= Math.max(30, maxW * 0.7) && (b.submits || 0) >= Math.max(2, maxS * 0.5);
      return el('div', { class: 'spark-row' + (peak ? ' peak' : '') },
        el('span', { class: 'spark-t small' }, fmtClock(b.t).slice(0, 5)),
        el('span', { class: 'spark-bar', style: 'width:' + Math.round(100 * (b.submits || 0) / maxS) + '%' }),
        el('span', { class: 'small muted' }, (b.submits || 0) + T(' sub · espera ~', ' sub · wait ~') + fmtS(b.avg_wait_s) + (peak ? T(' ⬅ pico', ' ⬅ peak') : '')));
    });
    return el('div', {}, el('h3', { style: 'margin:1rem 0 .3rem' }, T('📈 Atividade (submissões/min e espera média)', '📈 Activity (submissions/min and average wait)')),
      el('div', { class: 'spark' }, ...rows),
      el('div', { class: 'small muted', style: 'margin-top:.2rem' }, T('Barra ∝ submissões no minuto (máx visível = ', 'Bar ∝ submissions per minute (max visible = ') + maxS + ')'));
  }

  // --- o tick: busca e troca SÓ o que mudou ---------------------------------------------------
  let ever = false;
  async function refresh() {
    let d, sess, tq;
    try {
      [d, sess, tq] = await Promise.all([
        apiGet('/contest/admin/dashboard?contest=' + enc(CONTEST), G),
        apiGet('/contest/admin/sessions?contest=' + enc(CONTEST), G).catch(() => null),
        apiGet('/contest/staff/queue?contest=' + enc(CONTEST), G).catch(() => null),
      ]);
    } catch (e) {
      // sem dado novo: o último quadro fica; só o aviso de falha entra (e sai no próximo sucesso)
      swap(SK.err, el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error'))));
      return;
    }
    swap(SK.err, null);
    ever = true;
    const sub = d.submissions || {}, j = d.judges || {};
    const tasks = (tq && tq.requests) || [];
    const tSig = tasks.map((t) => [t.status, t.kind, t.time, !!t.first_site]);
    swapIf(SK.cards, sigOf(sub.pending, sub.max_wait_s, sub.response, j.online, j.total, j.busy, j.queue_depth, j.assigned,
      sess ? (sess.sessions || []).length : null, tSig, tq && tq.balloons_frozen), () => buildCards(d, sess, tq));
    swapIf(SK.routing, sigOf(d.routing || null), () => buildRouting(d.routing || null));
    swapIf(SK.review, sigOf(d.review || {}), () => buildReview(d.review || {}));
    const actions = computeActions(d, sess, tq);
    swapIf(SK.actions, sigOf(actions), () => buildActions(actions));
    swapIf(SK.judges, sigOf(j.pool, (j.list || []).map((x) => [x.host, x.online, x.state, x.age_s, x.problems_count, x.langs])), () => buildJudges(j));
    const pend = sub.pending_list || [];
    swapIf(SK.pending, sigOf(pend), () => buildPending(pend));
    const pp = (sub.per_problem || []).filter((x) => x.submits > 0);
    swapIf(SK.perProblem, sigOf(pp), () => buildPerProblem(pp));
    const recent = sub.recent || [];
    swapIf(SK.recent, sigOf(recent), () => buildRecent(recent));
    const tl = sub.timeline || [];
    swapIf(SK.timeline, sigOf(tl), () => buildTimeline(tl));
    SK.foot.textContent = T('Janela: últimas ', 'Window: last ') + (d.window || 0) + T(' submissões · atualizado ', ' submissions · updated ') + fmtClock(d.now) + ' · auto-refresh 12s';
  }

  async function load() {
    if (!SK.h2) skeleton();
    await refresh();
    if (stopTimer) stopTimer();
    stopTimer = everyVisible(panel, 12000, refresh);
  }
  return { panel, load };
}
