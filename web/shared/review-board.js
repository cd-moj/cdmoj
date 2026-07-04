// shared/review-board.js — painel da fila de CORREÇÃO MANUAL (review), compartilhado entre a
// aba "⚖️ Tarefas do judge" do admin e a Situação do juiz-chefe (/contest/chief/). Resumo em
// cards, a FILA COMPLETA (filtros, idade, quem pegou, votos — o servidor só manda os votos p/
// admin/chefe) com AÇÃO direta ("Decidir"/"Resolver" = POST review/resolve, o override auditado
// que libera o veredicto AO ALUNO na hora), e o desempenho por juiz (review/stats).
// SEM timer próprio: quem monta agenda o refresh chamando load() (evita refresh duplo no chief).
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { logLink, srcLink } from '/shared/submission-links.js';
import { pokeChiefAlert } from '/shared/chief-alert.js';

const enc = encodeURIComponent;
const nowE = () => Math.floor(Date.now() / 1000);
const fmtS = (s) => { s = Math.max(0, Math.round(+s || 0)); if (s < 60) return s + 's'; const m = Math.floor(s / 60); return m < 60 ? m + 'min' : Math.floor(m / 60) + 'h' + (m % 60 ? (m % 60) + 'min' : ''); };
const STATUS = {
  open: '🕓 não avaliada', claimed: '👀 em avaliação', voting: '1️⃣ aguarda 2º voto',
  conflict: '⚠️ CONFLITO', agreed: '✅ acordada',
};

export function makeReviewBoard({ contest }) {
  const root = el('div', {});
  let ITEMS = [], OPTIONS = [], STATS = null, MANUAL = true;

  const card = (label, val, warn) => el('div', { class: 'dash-card' + (warn ? ' warn' : '') },
    el('div', { class: 'dash-val' }, String(val)), el('div', { class: 'dash-lbl' }, label));

  // filtros (sobrevivem ao re-render)
  const fStatus = el('select', {}, el('option', { value: '' }, 'todas'),
    el('option', { value: 'open' }, 'não avaliadas'), el('option', { value: 'claimed' }, 'em avaliação'),
    el('option', { value: 'voting' }, 'aguardando 2º voto'), el('option', { value: 'conflict' }, 'conflitos'));
  const fQ = el('input', { type: 'search', placeholder: 'aluno / problema / juiz…', style: 'min-width:170px' });
  fStatus.addEventListener('change', render);
  fQ.addEventListener('input', render);
  // o alerta global de conflito pode pedir p/ abrir já filtrado em conflitos
  window.addEventListener('moj:show-conflicts', () => { fStatus.value = 'conflict'; render(); });

  const sumBox = el('div', {});
  const listBox = el('div', {});
  const perfBox = el('div', {});

  function renderSummary(counts) {
    sumBox.innerHTML = '';
    if (!MANUAL) sumBox.append(el('div', { class: 'warn-box', style: 'margin:.3rem 0' },
      '⚠ O veredicto manual está DESLIGADO (ligue em Configurações). ' + (ITEMS.length ? 'Ainda há sobras na fila abaixo.' : 'Nada é segurado p/ revisão.')));
    const c = counts || {};
    const oldest = ITEMS.length ? Math.max(...ITEMS.map((t) => nowE() - (t.created_at || nowE()))) : 0;
    sumBox.append(el('div', { class: 'dash-cards' },
      card('não avaliadas', c.not_evaluated || 0, (c.not_evaluated || 0) > 0 && oldest > 600),
      card('sendo avaliadas', c.being_evaluated || 0),
      card('aguardando 2º voto', c.awaiting_second || 0),
      card('conflitos', c.conflicts || 0, (c.conflicts || 0) > 0),
      card('mais antiga esperando', ITEMS.length ? fmtS(oldest) : '—', oldest > 600)));
  }

  function decideRow(t) {
    const sel = el('select', {}, el('option', { value: '' }, '-- veredicto --'),
      ...OPTIONS.map((o) => el('option', { value: o.label }, o.label)));
    const isConf = t.conflict === true;
    const btn = el('button', {
      class: 'btn' + (isConf ? ' danger' : ' ghost'),
      title: 'Libera o veredicto AO ALUNO agora (override auditado' + (isConf ? '' : ' — sem esperar os 2 juízes') + ')',
    }, isConf ? 'Resolver' : 'Decidir');
    const msg = el('span', { class: 'small' });
    btn.addEventListener('click', async () => {
      if (!sel.value) { sel.focus(); return; }
      btn.disabled = true; msg.textContent = '…';
      try { await apiPost('/contest/review/resolve?contest=' + enc(contest), { id: t.id, verdict: sel.value }, { contest, auth: true }); pokeChiefAlert(); await load(); }
      catch (e) { btn.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
    });
    return el('div', { class: 'row', style: 'gap:.25rem; flex-wrap:wrap' }, sel, btn, msg);
  }

  function itemRow(t) {
    const who = (t.claimants || []).map((c) => c.by + ' (' + fmtS(c.elapsed_s) + ', expira em ' + fmtS(c.expires_in_s) + ')').join(', ');
    const votes = (t.votes && t.votes.length)
      ? el('div', {}, ...t.votes.map((v) => el('div', { class: 'small' }, el('b', {}, v.by), ' → ', v.label || v.verdict)))
      : el('span', { class: 'small muted' }, String(t.votes_n || 0) + ' voto(s)');
    return el('tr', { class: t.conflict ? 'flag-anom' : '' },
      el('td', {}, el('b', {}, (t.problem_id || '').split('#').pop())),
      el('td', {}, t.login || '', el('div', { class: 'small muted' }, t.lang || '')),
      el('td', { class: 'small' }, t.computed_verdict || ''),
      el('td', {}, el('span', { class: t.conflict ? 'flag-anom' : (t.status === 'open' ? 'flag-warn' : '') }, STATUS[t.status] || t.status)),
      el('td', { class: 'small' }, fmtS(nowE() - (t.created_at || nowE()))),
      el('td', { class: 'small' }, who || '—'),
      el('td', {}, votes),
      el('td', { class: 'small' }, el('div', { class: 'row', style: 'gap:.5rem' }, logLink(contest, t), srcLink(contest, t))),
      el('td', {}, decideRow(t)));
  }

  function render() {
    listBox.innerHTML = '';
    const q = fQ.value.trim().toLowerCase();
    const items = ITEMS.filter((t) =>
      (!fStatus.value || t.status === fStatus.value)
      && (!q || [t.login, t.problem_id, ...(t.claimants || []).map((c) => c.by), ...((t.votes || []).map((v) => v.by))]
        .some((x) => (x || '').toLowerCase().includes(q))));
    listBox.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + ' de ' + ITEMS.length + ' na fila.'));
    if (!items.length) {
      listBox.append(el('div', { class: 'muted' }, ITEMS.length ? 'Nada com esses filtros.' : 'Fila vazia — nenhuma submissão aguardando revisão. 🎉'));
    } else {
      const tb = el('tbody'); items.forEach((t) => tb.append(itemRow(t)));
      listBox.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, 'Prob'), el('th', {}, 'Aluno'), el('th', {}, 'Computado'),
          el('th', {}, 'Status'), el('th', {}, 'Idade'), el('th', {}, 'Quem pegou'), el('th', {}, 'Votos'),
          el('th', {}, 'Ver'), el('th', {}, 'Ação'))), tb)));
    }
    listBox.append(el('p', { class: 'small muted', style: 'margin:.4rem 0 0' },
      'Para avaliar como juiz (pegar + votar, fluxo dos 2 votos): ',
      el('a', { href: '/contest/judge/?c=' + enc(contest) }, 'área de avaliação →')));
  }

  function renderPerf() {
    perfBox.innerHTML = '';
    const js = (STATS && STATS.judges) || [], tot = (STATS && STATS.total) || {};
    if (!js.length) return;
    perfBox.append(el('h3', { style: 'margin:1rem 0 .3rem' }, '📈 Desempenho por juiz'));
    const tb = el('tbody');
    js.forEach((j) => tb.append(el('tr', {},
      el('td', {}, el('b', {}, j.judge)),
      el('td', {}, j.votes),
      el('td', { class: 'small' }, fmtS(j.avg_response_s) + (j.timed < j.votes ? ' · ' + j.timed + '/' + j.votes + ' medidos' : '')),
      el('td', {}, j.agreements),
      el('td', { style: (j.conflicts ? 'color:#c00' : '') }, j.conflicts))));
    perfBox.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Juiz'), el('th', {}, 'Veredictos'), el('th', {}, 'Tempo médio (claim→voto)'),
        el('th', {}, 'Concordâncias'), el('th', {}, 'Conflitos'))), tb)),
      el('p', { class: 'small muted' }, 'Total: ' + (tot.votes || 0) + ' veredicto(s) · tempo médio geral ' + fmtS(tot.avg_response_s || 0) + '.'));
  }

  async function load() {
    let r, s;
    try {
      [r, s] = await Promise.all([
        apiGet('/contest/review/list?contest=' + enc(contest), { contest, auth: true }),
        apiGet('/contest/review/stats?contest=' + enc(contest), { contest, auth: true }).catch(() => null),
      ]);
    } catch (e) {
      listBox.innerHTML = ''; listBox.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro')));
      return;
    }
    ITEMS = r.items || []; OPTIONS = r.options || []; MANUAL = r.manual !== false; STATS = s;
    renderSummary(r.counts); render(); renderPerf();
  }

  root.append(sumBox,
    el('div', { class: 'row', style: 'margin:.4rem 0' },
      el('span', { class: 'small muted' }, 'Filtrar:'), fStatus, fQ,
      el('button', { class: 'btn ghost', onclick: () => load() }, '↻')),
    listBox, perfBox);
  return { el: root, load };
}
