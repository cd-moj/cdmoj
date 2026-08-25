// contest/admin/status-tab.js — "Operação › Situação": o dashboard AO VIVO da prova
// (auto-refresh 12s, só quando o painel está visível). Junta 3 fontes: /contest/admin/dashboard,
// /contest/admin/sessions e /contest/staff/queue — e transforma o que está fora do lugar em
// AÇÕES SUGERIDAS (juiz offline, pool inteiro fora, pendência esperando, conta compartilhada).
import { el } from '/shared/ui.js';
import { apiGet } from '/shared/api.js';
import { fmtS, fmtClock, vClass, downloadAuthed } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

export function makeStatusTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', { class: 'section' });
  let timer = null;
  const card = (label, val, warn) => el('div', { class: 'dash-card' + (warn ? ' warn' : '') },
    el('div', { class: 'dash-val' }, String(val)), el('div', { class: 'dash-lbl' }, label));

  async function refresh() {
    let d, sess, tq;
    try {
      [d, sess, tq] = await Promise.all([
        apiGet('/contest/admin/dashboard?contest=' + enc(CONTEST), G),
        apiGet('/contest/admin/sessions?contest=' + enc(CONTEST), G).catch(() => null),
        apiGet('/contest/staff/queue?contest=' + enc(CONTEST), G).catch(() => null),
      ]);
    } catch (e) {
      panel.innerHTML = '';
      panel.append(el('h2', {}, T('📊 Situação', '📊 Status')), el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error'))));
      return;
    }
    const sub = d.submissions || {}, resp = sub.response || {}, j = d.judges || {};
    const judges = j.list || [];
    const offline = judges.filter((x) => !x.online).length;
    // pool de juízes do contest (CONTEST_JUDGES; modelo ESTRITO — pool offline segura a fila)
    const pool = Array.isArray(j.pool) ? j.pool : [];
    const poolOnline = pool.filter((h) => judges.some((x) => x.host === h && x.online)).length;
    const online = sess ? (sess.sessions || []).length : '—', alerts = sess ? (sess.alerts || []) : [];
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
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('📊 Situação da prova', '📊 Contest status'),
        el('a', { href: '/contest/score/reveal.html?c=' + enc(CONTEST), target: '_blank',
                  class: 'btn ghost', style: 'margin-left:.7rem;font-size:.85rem' },
          T('🏆 Cerimônia de revelação', '🏆 Reveal ceremony')),
        // relatório final estático (tar.gz navegável offline: placar aberto, runs,
        // clarifications, estatísticas, tarefas do staff, infra) — GET admin/report
        el('button', { class: 'btn ghost', style: 'margin-left:.5rem;font-size:.85rem',
          onclick: async (ev) => {
            const b = ev.currentTarget, old = b.textContent;
            b.disabled = true; b.textContent = T('⏳ gerando…', '⏳ generating…');
            try { await downloadAuthed(CONTEST, '/contest/admin/report?contest=' + enc(CONTEST), 'relatorio-' + CONTEST + '.tar.gz'); }
            finally { b.disabled = false; b.textContent = old; }
          } }, T('📦 Relatório estático', '📦 Static report'))),
      el('div', { class: 'dash-cards' },
        card(T('Logados', 'Logged in'), online),
        card(T('Juízes online', 'Judges online'), (j.online || 0) + '/' + (j.total || 0), (j.total || 0) > 0 && (j.online || 0) === 0),
        card(T('Juízes ocupados', 'Judges busy'), j.busy || 0),
        card(T('Fila', 'Queue'), (j.queue_depth || 0) + (j.assigned ? ' (+' + j.assigned + T(' em juiz)', ' in judge)') : ''), (j.queue_depth || 0) > 5),
        card(T('Pendentes', 'Pending'), sub.pending || 0, (sub.pending || 0) > 0),
        card(T('Maior espera', 'Longest wait'), fmtS(sub.max_wait_s), (sub.max_wait_s || 0) > 60),
        card(T('Resposta média', 'Avg response'), fmtS(resp.avg_s)),
        card(T('Resposta p95', 'p95 response'), fmtS(resp.p95_s), (resp.p95_s || 0) > 120),
        ...taskCards));

    // ⚖️ avaliação manual de veredicto (só aparece quando há fila/conflito)
    const rv = d.review || {};
    if ((rv.pending_total || 0) > 0 || (rv.being_evaluated || 0) > 0 || (rv.conflicts || 0) > 0) {
      const ev = rv.evaluators || [];
      const rtb = el('tbody');
      ev.forEach((e) => rtb.append(el('tr', {},
        el('td', {}, (e.problem_id || '').split('#').pop()),
        el('td', { class: 'small' }, e.computed_verdict || ''),
        el('td', {}, e.conflict ? el('b', { style: 'color:#c00' }, T('conflito', 'conflict')) : (e.status || '')),
        el('td', { class: 'small' }, (e.claimants || []).map((c) => c.judge + ' (' + fmtS(c.elapsed_s) + ')').join(', ') || '—'))));
      panel.append(el('div', { style: 'margin-top:.7rem' }, el('h3', {}, T('⚖️ Avaliação manual', '⚖️ Manual evaluation')),
        el('div', { class: 'dash-cards' },
          card(T('Não avaliadas', 'Not evaluated'), rv.not_evaluated || 0, (rv.not_evaluated || 0) > 0),
          card(T('Sendo avaliadas', 'Being evaluated'), rv.being_evaluated || 0),
          card(T('Conflitos', 'Conflicts'), rv.conflicts || 0, (rv.conflicts || 0) > 0)),
        ev.length ? el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
          el('thead', {}, el('tr', {}, el('th', {}, T('Problema', 'Problem')), el('th', {}, T('Computado', 'Computed')), el('th', {}, 'Status'), el('th', {}, T('Avaliando (tempo)', 'Evaluating (time)')))), rtb)) : el('p', { class: 'muted small' }, T('ninguém avaliando agora', 'nobody evaluating right now')),
        (rv.conflicts || 0) > 0 ? el('p', { class: 'small' }, T('⚠ Resolva conflitos no ', '⚠ Resolve conflicts in the '), el('a', { href: '/contest/chief/?c=' + enc(CONTEST) }, T('painel do juiz-chefe', 'chief judge panel')), '.') : ''));
    }

    // ações sugeridas (palpáveis): só aparecem quando há algo a fazer
    const actions = [];
    if ((j.total || 0) === 0) actions.push(T('Nenhum juiz registrado — nada será julgado. Suba um agente de juiz.', 'No judge registered — nothing will be judged. Bring up a judge agent.'));
    else if ((j.online || 0) === 0) actions.push(T('Todos os juízes estão OFFLINE — submissões não serão julgadas. Verifique os agentes.', 'All judges are OFFLINE — submissions will not be judged. Check the agents.'));
    else if (offline > 0) actions.push(offline + T(' juiz(es) offline — capacidade reduzida.', ' judge(s) offline — reduced capacity.'));
    if (pool.length && poolOnline === 0)
      actions.push(T('Pool de juízes definido (', 'Judge pool defined (') + pool.join(', ') + T(') mas NENHUM host do pool está online — as submissões ficarão NA FILA até um voltar.', ') but NO pool host is online — submissions will stay QUEUED until one returns.'));
    else if (pool.length && poolOnline < pool.length)
      actions.push(T('Pool de juízes com host offline (', 'Judge pool with offline host (') + pool.filter((h) => !judges.some((x) => x.host === h && x.online)).join(', ') + T(') — capacidade do pool reduzida.', ') — reduced pool capacity.'));
    if ((sub.pending || 0) > 0 && (j.online || 0) > 0 && (j.busy || 0) === 0 && (sub.max_wait_s || 0) > 60)
      actions.push(T('Há pendências esperando >1min mas nenhum juiz ocupado — possível problema de fila/roteamento.', 'There are pending items waiting >1min but no judge busy — possible queue/routing problem.'));
    if ((sub.max_wait_s || 0) > 180) actions.push(T('Submissão esperando ', 'Submission waiting ') + fmtS(sub.max_wait_s) + T(' — investigar o juiz/linguagem.', ' — investigate the judge/language.'));
    if (tOld > 600) actions.push(T('Tarefa de impressão/balão pendente há ', 'Print/balloon task pending for ') + fmtS(tOld) + T(' — veja Operação › Staff (você pode agir por lá).', ' — see Operations › Staff (you can act there).'));
    alerts.forEach((a) => actions.push(a.login + T(' logado de ', ' logged in from ') + [a.multi_ip && 'IPs', a.multi_ua && T('máquinas/navegadores', 'machines/browsers')].filter(Boolean).join(T(' e ', ' and ')) + T(' diferentes (possível conta compartilhada).', ' (different — possibly a shared account).')));
    if (actions.length) panel.append(el('div', { class: 'section', style: 'background:#fff7ec;border:1px solid #f3c08e' },
      el('b', {}, T('⚠ Atenção', '⚠ Attention')), el('ul', { style: 'margin:.3rem 0 0; padding-left:1.2rem' }, ...actions.map((a) => el('li', {}, a)))));

    // saúde dos juízes (por host); ⭐ = host do pool do contest
    panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('🖥️ Juízes (', '🖥️ Judges (') + judges.length + ')' +
      (pool.length ? ' — pool: ' + pool.join(', ') : '')));
    if (!judges.length) panel.append(el('div', { class: 'flag-anom' }, T('Nenhum juiz registrado.', 'No judge registered.')));
    else {
      const tb = el('tbody');
      judges.forEach((x) => tb.append(el('tr', {},
        el('td', {}, el('span', { class: x.online ? '' : 'flag-anom', title: pool.includes(x.host) ? T('no pool do contest', 'in the contest pool') : '' },
          (pool.includes(x.host) ? '⭐ ' : '') + (x.online ? '🟢 ' : '🔴 ') + x.host)),
        el('td', { class: 'small' }, x.state || '—'),
        el('td', { class: 'small' + (x.online ? '' : ' flag-anom') }, x.online ? 'online' : (T('offline há ', 'offline for ') + fmtS(x.age_s))),
        el('td', { class: 'small' }, String(x.problems_count || 0) + ' probs'),
        el('td', { class: 'small ua' }, (x.langs || []).join(' ')))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Juiz', 'Judge')), el('th', {}, T('Estado', 'State')), el('th', {}, T('Visto', 'Seen')), el('th', {}, 'Cache'), el('th', {}, T('Linguagens', 'Languages')))), tb)));
    }

    // pendentes (ação: quem está esperando, há quanto tempo)
    const pend = sub.pending_list || [];
    panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('⏳ Pendentes (', '⏳ Pending (') + pend.length + ')'));
    if (!pend.length) panel.append(el('div', { class: 'muted' }, T('Nenhuma submissão aguardando o juiz.', 'No submission waiting for the judge.')));
    else {
      const tb = el('tbody');
      pend.forEach((p) => tb.append(el('tr', {}, el('td', {}, p.login), el('td', {}, p.problem),
        el('td', { class: 'small' }, fmtClock(p.submitted_at)),
        el('td', { class: p.waiting_s > 120 ? 'flag-anom' : (p.waiting_s > 30 ? 'flag-warn' : '') }, fmtS(p.waiting_s)))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Login'), el('th', {}, 'Prob'), el('th', {}, T('Enviado', 'Sent')), el('th', {}, T('Esperando', 'Waiting')))), tb)));
    }

    // atividade por problema
    const pp = (sub.per_problem || []).filter((x) => x.submits > 0);
    if (pp.length) {
      panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('📚 Por problema', '📚 By problem')));
      const tb = el('tbody');
      pp.forEach((x) => tb.append(el('tr', {}, el('td', {}, el('b', {}, x.problem)),
        el('td', { class: 'n' }, String(x.submits)),
        el('td', { class: 'n' + (x.pending ? ' flag-anom' : '') }, String(x.pending)),
        el('td', { class: 'n' }, String(x.accepted)))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Prob'), el('th', { class: 'n' }, 'Subs'), el('th', { class: 'n' }, 'Pend'), el('th', { class: 'n' }, 'AC'))), tb)));
    }

    // submissões recentes (feed palpável)
    const recent = sub.recent || [];
    if (recent.length) {
      panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('🧾 Submissões recentes', '🧾 Recent submissions')));
      const tb = el('tbody');
      recent.forEach((x) => tb.append(el('tr', {}, el('td', { class: 'small' }, fmtClock(x.at)),
        el('td', {}, x.login), el('td', {}, x.problem),
        el('td', {}, el('span', { class: vClass(x.verdict) }, x.verdict || '—')),
        el('td', { class: 'small' }, x.response_s != null ? fmtS(x.response_s) : (x.pending ? '⏳' : '—')))));
      panel.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Hora', 'Time')), el('th', {}, 'Login'), el('th', {}, 'Prob'), el('th', {}, T('Veredicto', 'Verdict')), el('th', {}, T('Resposta', 'Response')))), tb)));
    }

    // timeline (submissões/min + espera média), escala correta sobre as barras visíveis
    const tl = sub.timeline || [];
    if (tl.length) {
      const maxS = Math.max(1, ...tl.map((b) => b.submits || 0));
      const maxW = Math.max(1, ...tl.map((b) => b.avg_wait_s || 0));
      panel.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('📈 Atividade (submissões/min e espera média)', '📈 Activity (submissions/min and average wait)')));
      const rows = tl.map((b) => {
        const peak = (b.avg_wait_s || 0) >= Math.max(30, maxW * 0.7) && (b.submits || 0) >= Math.max(2, maxS * 0.5);
        return el('div', { class: 'spark-row' + (peak ? ' peak' : '') },
          el('span', { class: 'spark-t small' }, fmtClock(b.t).slice(0, 5)),
          el('span', { class: 'spark-bar', style: 'width:' + Math.round(100 * (b.submits || 0) / maxS) + '%' }),
          el('span', { class: 'small muted' }, (b.submits || 0) + T(' sub · espera ~', ' sub · wait ~') + fmtS(b.avg_wait_s) + (peak ? T(' ⬅ pico', ' ⬅ peak') : '')));
      });
      panel.append(el('div', { class: 'spark' }, ...rows),
        el('div', { class: 'small muted', style: 'margin-top:.2rem' }, T('Barra ∝ submissões no minuto (máx visível = ', 'Bar ∝ submissions per minute (max visible = ') + maxS + ')'));
    }

    panel.append(el('div', { class: 'small muted', style: 'margin-top:.6rem' },
      T('Janela: últimas ', 'Window: last ') + (d.window || 0) + T(' submissões · atualizado ', ' submissions · updated ') + fmtClock(d.now) + ' · auto-refresh 12s'));
  }

  async function load() {
    await refresh();
    clearInterval(timer); timer = setInterval(() => { if (!panel.hidden && panel.isConnected) refresh(); }, 12000);
  }
  return { panel, load };
}
