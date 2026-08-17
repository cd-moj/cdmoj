// contest/score/score-cols.js — a LARGURA das colunas do placar, em um lugar só.
//
// O placar NUNCA rola para o lado (regra do produto): o CSS usa `table-layout:fixed`, e num
// layout fixo quem manda são as larguras declaradas — então cada coluna precisa de um <col>.
// Antes era layout automático + `white-space:nowrap`: o nome comprido do time esticava a
// tabela e, com 14 problemas, em 1024px só três colunas de problema apareciam.
//
// A conta NÃO está aqui: o JS só informa o CENÁRIO (quantos problemas, se há bandeira e
// penalidade) em variáveis CSS, e o `ui.css` calcula as larguras — assim cada faixa de tela
// pode REDISTRIBUIR (no celular a coluna de problema encolhe porque o número vira ✓, e o
// nome do time ganha o espaço). Fazer a conta em JS travaria a distribuição no desktop.
const cols = (cg, n, cls) => {
  for (let i = 0; i < n; i++) {
    const c = document.createElement('col');
    c.className = cls;
    cg.append(c);
  }
};

// scoreColgroup(table, nProbs, {flag, penalty, total}) -> <colgroup> (ordem do cabeçalho:
// # · bandeira? · time · N problemas · total? · penalidade?). Também carimba no <table> as
// variáveis que o CSS usa para dividir o espaço.
export function scoreColgroup(nProbs, opts = {}) {
  const n = Math.max(0, nProbs | 0);
  const cg = document.createElement('colgroup');
  cg.dataset.nprob = String(n);
  cg.dataset.flag = opts.flag ? '1' : '0';
  cg.dataset.pen = opts.penalty ? '1' : '0';
  cols(cg, 1, 'c-place');
  if (opts.flag) cols(cg, 1, 'c-flag');
  cols(cg, 1, 'c-team');
  cols(cg, n, 'c-prob');
  if (opts.total !== false) cols(cg, 1, 'c-total');
  if (opts.penalty) cols(cg, 1, 'c-pen');
  return cg;
}

// applyScoreVars(table, nProbs, {flag, penalty, total}) — as variáveis que o ui.css consome.
export function applyScoreVars(table, nProbs, opts = {}) {
  const n = Math.max(0, nProbs | 0);
  table.style.setProperty('--nprob', String(n || 1));
  table.style.setProperty('--w-flag', opts.flag ? 'var(--w-flag-on)' : '0%');
  table.style.setProperty('--w-pen', opts.penalty ? 'var(--w-pen-on)' : '0%');
  table.style.setProperty('--w-total', opts.total === false ? '0%' : 'var(--w-total-on)');
}

// board(table, nProbs, opts) — atalho: colgroup + variáveis de uma vez.
export function scoreCols(table, nProbs, opts = {}) {
  applyScoreVars(table, nProbs, opts);
  table.append(scoreColgroup(nProbs, opts));
}

// cellTitle(short, value) -> texto do title da célula ("A: 1 tentativa, 28 min").
// No celular o número sai da tela (vira ✓/✗), então o title é o que resta para consultar.
export function cellTitle(short, value, t) {
  const tr = t || ((pt) => pt);
  const m = String(value || '').match(/^(\d+)\/(\d+|-)/);
  if (!m) return short;
  const tries = Number(m[1]);
  const when = m[2];
  const attempts = tries + ' ' + (tries === 1 ? tr('tentativa', 'attempt') : tr('tentativas', 'attempts'));
  return when === '-'
    ? short + ': ' + attempts + tr(', sem resolver', ', unsolved')
    : short + ': ' + attempts + ', ' + when + ' min';
}

// scoreColsGeneric(table, header, {iFlag,iUser,iTeam}) — placar de colunas livres
// (treino/heurístico/outro): as de texto (login/time) são largas, as demais dividem o resto.
export function scoreColsGeneric(table, header, idx = {}) {
  const isText = (i) => i === idx.iUser || i === idx.iTeam;
  const hasFlag = (header || []).some((_, i) => i === idx.iFlag);
  const nText = (header || []).reduce((a, _, i) => a + (isText(i) ? 1 : 0), 0);
  const nOther = (header || []).length - nText - (hasFlag ? 1 : 0);
  applyScoreVars(table, nOther, { flag: hasFlag, penalty: false, total: false });
  const cg = document.createElement('colgroup');
  cols(cg, 1, 'c-place');
  (header || []).forEach((_, i) => {
    if (i === idx.iFlag) cols(cg, 1, 'c-flag');
    else if (isText(i)) cols(cg, 1, 'c-team');
    else cols(cg, 1, 'c-prob');
  });
  // com 2 colunas de texto (login + time) cada uma fica com metade do "time"
  if (nText > 1) table.style.setProperty('--w-team-div', String(nText));
  table.append(cg);
}
