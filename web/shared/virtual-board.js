// shared/virtual-board.js — MOTOR do placar da Participação Virtual (e do modo Replay).
// PURO: sem import, sem DOM, sem rede — é o que deixa o teste diferencial rodar em gjs
// (server/test/smoke-virtual-board.gjs.sh: este motor em t=∞, só com fantasmas, tem de dar o
// MESMO placar que o servidor gravou em var/placar.txt).
//
// Entrada:
//   feed     = /treino/virtual/feed  {problems:[{letter,name}], teams:[[login,flag,univShort,name,
//              univFull,guest]], runs:[[sec,teamIdx,probIdx,"Y|N|X|?"]] (ordenado por sec),
//              penalty_minutes, duration}
//   virtuals = [{login,name,univ,flag,runs:[[sec,probIdx,flag,…]], you?}] — participações virtuais
//              (gravadas, de /treino/virtual/board, e a MINHA ao vivo); tempos já RELATIVOS
//   t        = segundos decorridos da prova (Infinity = resultado final)
// Saída: o MESMO objeto que parseICPC devolve (contest/score/score-icpc.js) — o renderizador do
// placar oficial desenha este sem saber a diferença. Linha virtual sai com guest+virtual (não
// consome posição oficial) e `gplace` = a posição que ela OCUPARIA entre os oficiais.
//
// REGRA DE CÉLULA — espelho de metrics_recompute (lib/users.sh) + updatescore-icpc.sh:
//   fac     = menor sec de um Y (≤ t);  tentativas = nº de runs que CONTAM (N ou Y) com sec ≤ fac
//   sem AC  = tentativas = nº de N (≤ t);  X nunca conta;  ? = pendente (célula "0/-" se só isso)
//   penalidade = Σ (tentativas-1)·PEN + floor(fac/60);  desempate: resolvidos ↓, penalidade ↑, último AC ↑
//   ★ = menor fac do problema entre os times do FEED, e só se não houver pendente mais antigo.

function cellOf(runs, t) {            // runs = [[sec, flag]] de UM (time, problema)
  let fac = null, pend = 0, pendMin = null;
  for (const [s, f] of runs) {
    if (s > t) continue;
    if (f === 'Y' && (fac === null || s < fac)) fac = s;
    if (f === '?') { pend++; if (pendMin === null || s < pendMin) pendMin = s; }
  }
  let tent = 0;
  for (const [s, f] of runs) {
    if (s > t || (f !== 'N' && f !== 'Y')) continue;
    if (fac === null ? f === 'N' : s <= fac) tent++;
  }
  return { fac, tent, pend, pendMin };
}

function rowOf(cells, pen) {
  let solved = 0, penalty = 0, lastmin = 0;
  for (const c of cells) {
    if (!c || c.fac === null) continue;
    const min = Math.floor(c.fac / 60);
    solved++; penalty += (c.tent - 1) * pen + min; if (min > lastmin) lastmin = min;
  }
  return { solved, penalty, lastmin };
}

const better = (a, b) => (b.solved - a.solved) || (a.penalty - b.penalty) || (a.lastmin - b.lastmin);

// índice (time → problema → runs), feito UMA vez por feed
export function indexFeed(feed) {
  const np = feed.problems.length;
  const by = feed.teams.map(() => Array.from({ length: np }, () => []));
  for (const [s, ti, pi, f] of feed.runs) if (by[ti] && by[ti][pi]) by[ti][pi].push([s, f]);
  return { np, by, secs: feed.runs.map((r) => r[0]) };
}

// quantas runs do feed já "aconteceram" em t — serve p/ o chamador só redesenhar quando muda
export function runsUpTo(idx, t) {
  let lo = 0, hi = idx.secs.length;
  while (lo < hi) { const m = (lo + hi) >> 1; if (idx.secs[m] <= t) lo = m + 1; else hi = m; }
  return lo;
}

// opts.teamOk(tm, ti) — recorte de COORTE ("Placar: Oficial / só convidados…"): time recusado fica
// FORA do cálculo, então posição e ★ saem como no placar próprio daquela visão no servidor
// (filtrar linha depois daria ★ errada — lib/cohorts.sh). Bandeira/universidade/sede/busca NÃO
// passam por aqui: são recorte de LINHA no renderizador, que renumera e mostra a posição geral.
export function boardAt(feed, idx, virtuals, t, balloons, opts) {
  const teamOk = (opts && opts.teamOk) || null;
  const pen = Number(feed.penalty_minutes) || 20;
  const letters = feed.problems.map((p) => p.letter);
  const rows = [];

  feed.teams.forEach((tm, ti) => {
    if (teamOk && !teamOk(tm, ti)) return;
    const cells = idx.by[ti].map((rs) => cellOf(rs, t));
    rows.push({ id: tm[0], flag: tm[1] || '', univShort: tm[2] || '', teamName: tm[3] || '', univFull: tm[4] || '',
      guest: !!tm[5], cohort: tm[6] || '', virtual: false, you: false, order: ti, cells, ...rowOf(cells, pen) });
  });

  // ★ com CERTEZA: mínimo entre os times do feed; pendente mais antigo (ou igual) segura a estrela
  const fts = letters.map((_, pi) => {
    let best = null, pmin = null;
    for (const r of rows) {
      const c = r.cells[pi];
      if (c.fac !== null && (best === null || c.fac < best)) best = c.fac;
      if (c.pendMin !== null && (pmin === null || c.pendMin < pmin)) pmin = c.pendMin;
    }
    return (best !== null && pmin !== null && pmin <= best) ? null : best;
  });

  (virtuals || []).forEach((v, k) => {
    const per = Array.from({ length: idx.np }, () => []);
    for (const r of (v.runs || [])) if (per[r[1]]) per[r[1]].push([r[0], r[2]]);
    const cells = per.map((rs) => cellOf(rs, t));
    rows.push({ id: '#' + v.login, flag: v.flag || '', univShort: v.univ || '', teamName: v.name || v.login, univFull: '',
      guest: true, virtual: true, you: !!v.you, order: feed.teams.length + k, cells, ...rowOf(cells, pen) });
  });

  rows.sort((a, b) => better(a, b) || (a.order - b.order));

  // posição oficial: ranking de COMPETIÇÃO (empate compartilha E consome); convidado/virtual não consome
  let seen = 0, prev = null;
  const official = [];
  for (const r of rows) {
    if (r.guest) { r.place = null; continue; }
    seen++;
    r.place = (prev && better(prev, r) === 0) ? prev.place : seen;
    prev = r; official.push(r);
  }
  for (const r of rows) {
    if (!r.virtual) { r.gplace = null; continue; }
    let ahead = 0;
    for (const o of official) { if (better(o, r) < 0) ahead++; else break; }
    r.gplace = ahead + 1;
  }

  const teams = rows.map((r) => {
    const probs = {}, probSecs = {};
    r.cells.forEach((c, pi) => {
      const sn = letters[pi];
      if (c.fac !== null) {
        const star = (!r.virtual && fts[pi] !== null && c.fac === fts[pi]) ? '*' : '';
        probs[sn] = c.tent + '/' + Math.floor(c.fac / 60) + star; probSecs[sn] = c.fac;
      } else probs[sn] = (c.tent === 0 && c.pend === 0) ? '' : (c.tent + '/-');
    });
    return { flag: r.flag, username: r.id, univShort: r.univShort, teamName: r.teamName, univFull: r.univFull,
      total: String(r.solved), penalty: String(r.penalty), lastac: String(r.lastmin),
      guest: r.guest, cohort: r.cohort || '', virtual: r.virtual, you: r.you, place: r.place, gplace: r.gplace, probs, probSecs };
  });
  return { mode: 'icpc', probShorts: letters, teams, balloons: balloons || {}, secs: true, guestNumbering: true };
}

// a linha de quem está olhando (p/ o cabeçalho "você está em Nº")
export const myRow = (parsed) => (parsed.teams.find((x) => x.you) || null);

// Com filtro de LINHA ativo (bandeira/universidade/sede/busca) o renderizador renumera os oficiais
// dentro do recorte; a linha virtual tem de acompanhar: a posição que ela ocuparia ENTRE OS VISÍVEIS.
// `keep(t)` = o mesmo predicado entregue ao renderizador. Sem filtro, devolve ao valor do placar inteiro.
export function sliceVirtualPlaces(parsed, keep) {
  const key = (x) => [-Number(x.total), Number(x.penalty), Number(x.lastac)];
  const lt = (a, b) => { const ka = key(a), kb = key(b); for (let i = 0; i < 3; i++) if (ka[i] !== kb[i]) return ka[i] < kb[i]; return false; };
  const off = parsed.teams.filter((x) => !x.guest && (!keep || keep(x)));
  parsed.teams.forEach((v) => { if (v.virtual) v.gplace = off.filter((o) => lt(o, v)).length + 1; });
  return parsed;
}
