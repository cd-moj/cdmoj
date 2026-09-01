// lib/mlinux-view.js — as SEÇÕES do panorama mlinux (nutellaboot), em um lugar só.
//
// Fonte ÚNICA de três telas que precisam ser iguais: o painel do admin (mlinux-tab.js), a
// página avulsa /contest/mlinux/ (cstaff/staff, escopada pelo servidor) e o mlinux.html do
// RELATÓRIO OFFLINE (report-gen.sh inlina este arquivo + charts.js + dom.js). Recebe UM
// agregado do var/nutella.cache.json — o `global`, um nó de `by_node` ou uma entrada de
// `sedes[]` (que tem extras: machines[], ranks, series próprios) — e devolve um ARRAY de
// elementos. Só depende de dom.js e charts.js (sem rede).
//
// Relatório 2.0 (01/09): o coletor deriva POR MÁQUINA o que aconteceu DURANTE A PROVA e
// guarda por sede só somas/contagens (rollup exato). Aqui viram: hardware por recorte (RAM,
// geração/idade de CPU — `cpuInfo` infere o ano do modelo), adoção de editores (aberto ≥ 60
// min NA PROVA), perfis puros, editores × colocação (o "vale dos IDEs", só com ≥ 30 times
// vinculados), pressão de memória (faixa de RAM × perfil) e observações automáticas. As
// definições estão no `<details>` "Como ler" do fim — mantenha-o em dia com o coletor.
//
// opts: { showMachines, contest:{start,end}, link:{mode,coverage}, data (o cache inteiro),
//         tree (regions.json, só name/subregions), sel:{kind:'g'|'n'|'s', key} }
import { el } from '/shared/dom.js';
import { hBarChart, lineChart, multiLineChart } from '/lib/charts.js';
import { T } from '/shared/i18n.js';

// CSS das seções (cartões/duas colunas/tabela): cada HOST injeta — o painel do admin e o
// relatório não têm o <style> local da página de estatísticas, de onde estas regras vêm.
export const MLINUX_CSS = `
.stat-cards{display:flex;gap:1rem;flex-wrap:wrap;margin-bottom:1rem}
.stat-card{flex:1;min-width:130px;background:#fff;border:1px solid #e3e9f2;border-radius:12px;padding:1rem 1.1rem;box-shadow:0 2px 10px rgba(20,40,80,.05)}
.big-num{font-size:1.7rem;font-weight:800;line-height:1;font-variant-numeric:tabular-nums}
.big-sub{color:#64748b;font-size:.85rem;margin-top:.2rem}
.two-col{display:flex;gap:1.2rem;flex-wrap:wrap}
.two-col>div{flex:1 1 320px;min-width:0}
.chart-title{text-align:center;font-weight:600;margin-bottom:.3rem}
svg.chart{max-width:100%;height:auto;display:block;margin:0 auto}
table.moj{width:100%;border-collapse:collapse;font-size:.88rem}
table.moj th,table.moj td{padding:.32rem .45rem;border-top:1px solid #eef2f8;text-align:left}
table.moj thead th{border-top:0;color:#64748b;font-size:.8rem}
table.moj td.n,table.moj th.n{text-align:right;font-variant-numeric:tabular-nums}
table.moj.narrow{width:auto}
table.moj tr.grp td{font-weight:600;background:#f7f9fc}
.ml-obs{border-left:4px solid #216097;background:#f5f7fb;padding:.5rem .9rem;border-radius:0 8px 8px 0;margin:.4rem 0 .8rem}
.ml-obs li{margin:.15rem 0}
.ml-card{background:#fff;border:1px solid #e3e9f2;border-radius:10px;padding:.7rem .9rem;color:#334}
.ml-note{color:#64748b;font-size:.85rem;margin:.2rem 0 .6rem}
`;

const MIN_RANK_TEAMS = 30;   // editores × colocação só com 30+ times vinculados e ranqueados
const BANDS = ['<8', '8', '12', '16', '24', '32', '>32'];
const PBANDS = ['8', '16', '32', '>32'];
const GROUPS = ['vscode', 'jetbrains', 'codeblocks', 'light'];
const PROFS = ['vscode', 'jetbrains', 'codeblocks', 'light', 'mixed', 'none'];
const ED_NAME = { code: 'VS Code', idea: 'IntelliJ IDEA', clion: 'CLion', pycharm: 'PyCharm',
  codeblocks: 'Code::Blocks', gedit: 'gedit', vim: 'Vim', emacs: 'Emacs', geany: 'Geany' };
const GROUP_COLOR = { vscode: '#2f6fdd', jetbrains: '#c0392b', codeblocks: '#e67e22', light: '#27ae60',
  other: '#7f8c8d', mixed: '#8e6bbf', none: '#b0b7c3' };
const BAND_COLOR = { '8': '#c0392b', '16': '#e67e22', '32': '#27ae60', '>32': '#2f6fdd' };

const edName = (k) => ED_NAME[k] || k;
const edGroup = (e) => (e === 'code' ? 'vscode'
  : (e === 'idea' || e === 'clion' || e === 'pycharm') ? 'jetbrains'
    : e === 'codeblocks' ? 'codeblocks'
      : (e === 'vim' || e === 'gedit' || e === 'geany' || e === 'emacs') ? 'light' : 'other');
const groupName = (g) => ({
  vscode: 'VS Code', jetbrains: 'JetBrains (IDEA, CLion, PyCharm)', codeblocks: 'Code::Blocks',
  light: T('Leves (Vim, gedit, Geany, Emacs)', 'Light (Vim, gedit, Geany, Emacs)'),
  other: T('Outro', 'Other'), mixed: T('Misto', 'Mixed'), none: T('Nenhum', 'None') }[g] || g);
const profName = (p) => (p === 'mixed' ? T('misto', 'mixed') : p === 'none' ? T('nenhum', 'none')
  : p === 'light' ? T('leve', 'light') : p === 'jetbrains' ? 'JetBrains' : p === 'vscode' ? 'VS Code'
    : p === 'codeblocks' ? 'Code::Blocks' : p);

const GB = (mb) => (mb >= 10240 ? Math.round(mb / 1024) : Math.round(mb / 102.4) / 10);
const fmtMin = (m) => (m >= 120 ? Math.round(m / 60) + 'h' : Math.round(m) + 'min');
const pct = (n, d) => (d ? Math.round((n || 0) * 100 / d) : null);
const pctS = (n, d) => (d ? pct(n, d) + '%' : '—');
const r1 = (x) => Math.round(x * 10) / 10;
const sum = (o) => Object.values(o || {}).reduce((s, v) => s + (v || 0), 0);

function card(big, sub) {
  return el('div', { class: 'stat-card' },
    el('div', { class: 'big-num' }, String(big)), el('div', { class: 'big-sub' }, sub));
}
function box(title, chart) { return el('div', {}, el('div', { class: 'chart-title' }, title), chart); }
// tabela: head = [{t, n?}], rows = [[cell…]]; cell = string|number|{t, n?, b?}
function tbl(head, rows, cls) {
  const th = (h) => el('th', { class: h.n ? 'n' : '' }, h.t);
  const td = (c) => {
    const o = (c && typeof c === 'object') ? c : { t: c };
    return el('td', { class: o.n ? 'n' : '' }, o.b ? el('b', {}, String(o.t)) : String(o.t == null ? '—' : o.t));
  };
  return el('div', { class: 'tblwrap', style: 'overflow-x:auto' },
    el('table', { class: 'moj' + (cls ? ' ' + cls : '') },
      el('thead', {}, el('tr', {}, ...head.map(th))),
      el('tbody', {}, ...rows.map((r) => el('tr', { class: r.grp ? 'grp' : '' }, ...r.cells.map(td))))));
}
const row = (cells, grp) => ({ cells, grp: !!grp });

// ---- CPU: modelo → fabricante, família, ano de lançamento ---------------------------------
// As tabelas de ano são as dos scripts do artigo da Revista Maratona (analise-hardware-times.py).
const INTEL_GEN_YEAR = { 1: 2010, 2: 2011, 3: 2012, 4: 2013, 5: 2015, 6: 2015, 7: 2017, 8: 2017, 9: 2018,
  10: 2020, 11: 2021, 12: 2021, 13: 2022, 14: 2023, 15: 2024 };
const RYZEN_SERIES_YEAR = { 1: 2017, 2: 2018, 3: 2019, 4: 2020, 5: 2021, 6: 2022, 7: 2022, 8: 2023, 9: 2024 };
export function cpuInfo(model) {
  const s = String(model || '').replace(/\((R|TM|tm|r)\)|®|™|\bCPU\b|@.*$/g, ' ').replace(/\s+/g, ' ').trim();
  const o = { vendor: 'other', family: 'other', year: null };
  let m;
  if (/\b(Intel|Core|Pentium|Celeron|Xeon)\b/i.test(s)) o.vendor = 'intel';
  else if (/\b(AMD|Ryzen|Athlon|Phenom|FX)\b|\bA(4|6|8|9|10|12)(-| PRO-)\d{4}/i.test(s)) o.vendor = 'amd';
  if ((m = s.match(/Core Ultra\s*[3579]?\s*(\d)\d{2}/i))) { o.family = 'Core Ultra'; o.year = m[1] === '2' ? 2024 : 2023; }
  else if ((m = s.match(/\bi([3579])[- ]N\d{3}/i))) { o.family = 'Core i' + m[1]; o.year = 2023; }
  else if ((m = s.match(/\bi([3579])[- ](\d{4,5})[A-Z]*/i))) {
    o.family = 'Core i' + m[1];
    const d = m[2], pre = s.match(/\b(\d{1,2})(st|nd|rd|th) Gen/i);
    const gen = pre ? +pre[1] : d.length === 5 ? +d.slice(0, 2) : d[0] === '1' ? +d.slice(0, 2) : +d[0];
    o.year = INTEL_GEN_YEAR[gen] || null;
  } else if (/Core\s*2/i.test(s)) { o.family = 'Core 2'; o.year = 2007; }
  else if ((m = s.match(/Pentium.*?\bG(\d)\d{3}/i))) { o.family = 'Pentium'; o.year = +m[1] >= 4 ? 2017 : 2015; }
  else if (/Pentium/i.test(s)) { o.family = 'Pentium'; o.year = 2015; }
  else if (/Celeron/i.test(s)) { o.family = 'Celeron'; o.year = 2016; }
  else if (/Xeon/i.test(s)) { o.family = 'Xeon'; }
  else if ((m = s.match(/Ryzen\s*([3579])\s*(PRO\s*)?(\d)\d{3}/i))) { o.family = 'Ryzen ' + m[1]; o.year = RYZEN_SERIES_YEAR[+m[3]] || null; }
  else if (/\bA(4|6|8|9|10|12)(-| PRO-)\d{4}|APU/i.test(s)) { o.family = 'AMD A'; o.year = 2013; }
  else if (/Athlon/i.test(s)) { o.family = 'Athlon'; o.year = 2014; }
  else if (/\bFX-\d{4}/i.test(s)) { o.family = 'FX'; o.year = 2012; }
  return o;
}
const ageBand = (y) => (y == null ? 'unknown' : y <= 2016 ? 'old' : y <= 2021 ? 'mid' : 'new');
const ageBandName = (b) => ({ old: T('antigo (até 2016)', 'old (up to 2016)'),
  mid: T('intermediário (2017 a 2021)', 'intermediate (2017 to 2021)'),
  new: T('atual (2022 ou depois)', 'current (2022 or later)'), unknown: T('sem ano', 'no year') }[b]);
// cpuStats({modelo: n}, anoRef) -> agregados p/ cartões/barras/tabela
function cpuStats(hist, ref) {
  const st = { n: 0, known: 0, ageSum: 0, vendor: {}, family: {}, age: {}, top: [] };
  Object.entries(hist || {}).forEach(([model, cnt]) => {
    const c = cnt || 0, i = cpuInfo(model);
    st.n += c; st.vendor[i.vendor] = (st.vendor[i.vendor] || 0) + c;
    st.family[i.family] = (st.family[i.family] || 0) + c;
    const b = ageBand(i.year); st.age[b] = (st.age[b] || 0) + c;
    if (i.year != null) { st.known += c; st.ageSum += c * (ref - i.year); }
    st.top.push([model, c]);
  });
  st.top.sort((a, b) => b[1] - a[1]);
  st.meanAge = st.known ? st.ageSum / st.known : null;
  return st;
}

// ---- contexto do recorte -----------------------------------------------------------------
function ramAvg(a) {   // RAM média das máquinas de time: média das MÉDIAS por sede no nó; a média da sede na sede
  if (!a) return null;
  if (a.ram_avg_sites && a.sedes && a.sedes.length > 1) return a.ram_avg_sites;
  return a.ram_n_tm ? a.ram_sum_tm / a.ram_n_tm : null;
}
function isSite(a) { return !!(a && a.id && a.name); }
// filhos do recorte p/ as tabelas comparativas: subregiões do nó (na árvore) com dado; sem
// subregião, as sedes do nó. Global = nós de topo + sedes fora da árvore.
function childrenOf(a, opts) {
  const d = opts.data; if (!d || isSite(a)) return [];
  const have = d.by_node || {}, sedes = d.sedes || [];
  const sedeBy = {}; sedes.forEach((s) => { sedeBy[s.name.toLowerCase()] = s; });
  const aggOf = (name) => (Object.prototype.hasOwnProperty.call(have, name) ? have[name] : sedeBy[name.toLowerCase()] || null);
  const findNode = (list, key) => {
    for (const r of list || []) { if (r.name === key) return r; const f = findNode(r.subregions, key); if (f) return f; }
    return null;
  };
  let list = [];
  const sel = opts.sel || { kind: 'g' };
  // nós `view:true` (recortes que AGREGAM times já contados nas sedes: supersedes, coortes)
  // ficam fora da comparação — somariam duas vezes
  const real = (r) => r && r.name && r.view !== true;
  if (sel.kind === 'n') {
    const node = findNode(opts.tree || [], sel.key);
    (node && node.subregions || []).filter(real).forEach((r) => { const g = aggOf(r.name); if (g && r.name !== sel.key) list.push({ name: r.name, agg: g }); });
  } else {
    (opts.tree || []).filter(real).forEach((r) => { const g = aggOf(r.name); if (g) list.push({ name: r.name, agg: g }); });
    const seen = new Set(list.map((x) => x.name.toLowerCase()));
    sedes.forEach((s) => { if (!seen.has(s.name.toLowerCase()) && !inTree(opts.tree, s.name)) list.push({ name: s.name, agg: s }); });
  }
  // sem subregião (ou só uma): comparar as SEDES do recorte
  if (list.length < 2) {
    const names = new Set((a.sedes || []).map((n) => n.toLowerCase()));
    list = sedes.filter((s) => names.has(s.name.toLowerCase())).map((s) => ({ name: s.name, agg: s }));
  }
  return list.filter((x) => (x.agg.pop && x.agg.pop.tm) || (x.agg.seen));
}
function inTree(tree, name) {
  const lo = name.toLowerCase();
  const walk = (list) => (list || []).some((r) => (r.name || '').toLowerCase() === lo || walk(r.subregions));
  return walk(tree);
}
function ctxOf(a, opts) {
  const c = opts.contest || opts.window || {};
  const start = c.start || 0, end = c.end || 0;
  return { start, end, dur: start && end ? Math.max(1, Math.round((end - start) / 60)) : 300,
    ref: start ? new Date(start * 1000).getFullYear() : new Date().getFullYear(),
    children: childrenOf(a, opts), pop: a.pop || {}, tm: (a.pop && a.pop.tm) || 0 };
}

// ---- 1. cartões ------------------------------------------------------------------------------
function cardsSection(a, cx) {
  const bands = a.ram_bands || {}, tm = cx.tm;
  const p8 = tm ? pct((bands['<8'] || 0) + (bands['8'] || 0), tm) : null;
  const cs = cpuStats(a.cpu_tm || a.cpu, cx.ref);
  const ram = ramAvg(a);
  const ld = a.ld_n ? r1(a.ld_sum / a.ld_n) : null;
  const topEd = Object.entries(a.ed_adopt || {}).sort((x, y) => y[1] - x[1])[0];
  return el('div', { class: 'stat-cards' },
    card(a.seen || 0, T('máquinas vistas na prova', 'machines seen in the contest')),
    card(tm, T('máquinas de time', 'team machines')),
    card(ram != null ? GB(ram) + ' GB' : '—', T('RAM média', 'average RAM')),
    card(p8 != null ? p8 + '%' : '—', T('em 8 GB ou menos', 'on 8 GB or less')),
    card(cs.meanAge != null ? r1(cs.meanAge) + ' ' + T('anos', 'yr') : '—', T('idade média da CPU', 'average CPU age')),
    card(ld != null ? ld : '—', T('load médio na prova', 'average load in the contest')),
    card(topEd ? pctS(topEd[1], tm) : '—', topEd ? edName(topEd[0]) : T('editor', 'editor')));
}

// ---- 2. observações automáticas (STE) --------------------------------------------------------
function observations(a, cx, opts) {
  const tm = cx.tm; if (tm < 10) return null;
  const li = [];
  const g = a.ed_groups || {}, bands = a.ram_bands || {}, cnt = a.ed_count || {};
  if (g.vscode != null) li.push(T(`VS Code ficou aberto por 60 minutos ou mais em ${pct(g.vscode, tm)}% das máquinas de time.`,
    `VS Code was open for 60 minutes or more on ${pct(g.vscode, tm)}% of team machines.`));
  const one = cnt['1'] || 0, multi = (cnt['2'] || 0) + (cnt['3+'] || 0);
  if (one + multi) li.push(T(`${pct(one, tm)}% dos times usaram um editor só. ${pct(multi, tm)}% usaram dois ou mais.`,
    `${pct(one, tm)}% of teams used one editor only. ${pct(multi, tm)}% used two or more.`));
  const re = a.rank_ed;
  if (re && re.n >= MIN_RANK_TEAMS && re.top30 && re.top30.n) {
    GROUPS.forEach((gr) => {
      const t = pct((re.top30.grp || {})[gr] || 0, re.top30.n), al = pct((re.all.grp || {})[gr] || 0, re.all.n);
      if (Math.abs(t - al) >= 10) li.push(T(`Entre os 30 primeiros do recorte, ${t}% usaram ${groupName(gr)}. No total, ${al}%.`,
        `Among the top 30 of this selection, ${t}% used ${groupName(gr)}. Overall, ${al}%.`));
    });
  }
  const p8 = pct((bands['<8'] || 0) + (bands['8'] || 0), tm);
  li.push(T(`${p8}% das máquinas de time têm 8 GB de RAM ou menos.`, `${p8}% of team machines have 8 GB of RAM or less.`));
  const kids = cx.children.filter((k) => (k.agg.pop || {}).tm >= 3 && ramAvg(k.agg) != null);
  if (kids.length >= 2) {
    const byRam = kids.slice().sort((x, y) => ramAvg(x.agg) - ramAvg(y.agg));
    const lo = byRam[0], hi = byRam[byRam.length - 1];
    li.push(T(`Menos RAM média: ${lo.name} (${GB(ramAvg(lo.agg))} GB). Mais RAM média: ${hi.name} (${GB(ramAvg(hi.agg))} GB).`,
      `Least average RAM: ${lo.name} (${GB(ramAvg(lo.agg))} GB). Most average RAM: ${hi.name} (${GB(ramAvg(hi.agg))} GB).`));
    const ages = kids.map((k) => ({ k, s: cpuStats(k.agg.cpu_tm || k.agg.cpu, cx.ref) })).filter((x) => x.s.meanAge != null)
      .sort((x, y) => y.s.meanAge - x.s.meanAge);
    if (ages.length >= 2) li.push(T(`Os processadores mais antigos estão em ${ages[0].k.name} (idade média ${r1(ages[0].s.meanAge)} anos).`,
      `The oldest processors are in ${ages[0].k.name} (average age ${r1(ages[0].s.meanAge)} years).`));
  }
  if (a.ld_n && a.seen) {
    const ld = r1(a.ld_sum / a.ld_n), cores = Math.round((a.cores_total || 0) / a.seen);
    const pr = a.pressure || {};
    let m8s = 0, m8n = 0;
    Object.entries(pr).forEach(([k, v]) => { if (k.split('|')[0] === '8') { m8s += v.mem4_sum || 0; m8n += v.mem4_n || 0; } });
    const m8 = m8n ? Math.round(m8s / m8n) : null;
    if (cores && ld / cores < 0.25) {
      li.push(T(`O load médio foi ${ld} em máquinas de ${cores} núcleos. A CPU não foi o gargalo.`,
        `Average load was ${ld} on ${cores}-core machines. The CPU was not the bottleneck.`)
        + (m8 != null ? ' ' + T(`Máquinas de 8 GB chegaram a ${m8}% de memória usada na última hora.`,
          `8 GB machines reached ${m8}% memory use in the last hour.`) : ''));
    }
  }
  const sw = swapByBand(a);
  if (sw['8'] && sw['16'] && sw['8'].n >= 3 && sw['16'].n >= 3) {
    const s8 = Math.round(sw['8'].sum / sw['8'].pts), s16 = Math.round(sw['16'].sum / sw['16'].pts);
    if (s8 >= 50 && s8 >= 2 * s16) li.push(T(`Máquinas de 8 GB usaram em média ${s8} MB de swap. As de 16 GB, ${s16} MB.`,
      `8 GB machines used ${s8} MB of swap on average. 16 GB machines, ${s16} MB.`));
  }
  if (opts.link && !isSite(a) && !(opts.sel && opts.sel.kind === 'n')) {
    li.push(opts.link.mode === 'ua'
      ? T(`O vínculo máquina-time cobriu ${opts.link.coverage}% dos times, pelo login no navegador do mlinux.`,
        `The machine-team link covered ${opts.link.coverage}% of teams, via the login from the mlinux browser.`)
      : T('Sem vínculo suficiente máquina-time. As máquinas de time são as máquinas usadas na prova.',
        'Not enough machine-team links. Team machines are the machines used in the contest.'));
  }
  if (!li.length) return null;
  return el('div', { class: 'section' }, el('h2', {}, T('🔎 Observações', '🔎 Observations')),
    el('div', { class: 'ml-obs' }, el('ul', { style: 'margin:.2rem 0 .2rem 1.1rem' }, ...li.map((x) => el('li', {}, x)))));
}
function swapByBand(a) {
  const out = {};
  Object.entries(a.pressure || {}).forEach(([k, v]) => {
    const b = k.split('|')[0]; out[b] = out[b] || { n: 0, sum: 0, pts: 0 };
    out[b].n += v.n || 0; out[b].sum += v.sw_sum || 0; out[b].pts += v.sw_n || 0;
  });
  return out;
}

// ---- 3. hardware -----------------------------------------------------------------------------
function hardwareSection(a, cx) {
  const tm = cx.tm; if (!tm) return null;
  const bands = a.ram_bands || {};
  const cs = cpuStats(a.cpu_tm || a.cpu, cx.ref);
  const secs = [el('h2', {}, T('🖥 Hardware das máquinas de time', '🖥 Team machine hardware'))];
  const two = el('div', { class: 'two-col' });
  two.append(box(T('RAM instalada (GB)', 'Installed RAM (GB)'),
    hBarChart(BANDS.filter((b) => bands[b]).map((b) => ({ label: b + ' GB', value: bands[b],
      color: BAND_COLOR[b.replace('<', '').replace('12', '16').replace('24', '32')] || '#7f8c8d' })), { total: tm })));
  two.append(box(T('Idade do processador', 'Processor age'),
    hBarChart(['new', 'mid', 'old', 'unknown'].filter((b) => cs.age[b]).map((b) => ({ label: ageBandName(b), value: cs.age[b],
      color: { new: '#27ae60', mid: '#e67e22', old: '#c0392b', unknown: '#b0b7c3' }[b] })), { total: cs.n })));
  secs.push(two);
  const two2 = el('div', { class: 'two-col' });
  const fam = Object.entries(cs.family).sort((x, y) => y[1] - x[1]);
  two2.append(box(T('Família', 'Family'), hBarChart(fam.map(([k, v]) => ({ label: k, value: v })), { total: cs.n, maxRows: 8 })));
  two2.append(box(T('Modelos mais comuns', 'Most common models'),
    hBarChart(cs.top.slice(0, 10).map(([k, v]) => ({ label: k.replace(/\(R\)|\(TM\)|CPU|@.*$/g, '').replace(/\s+/g, ' ').trim(), value: v })), { total: cs.n })));
  secs.push(two2);
  const vend = cs.vendor;
  secs.push(el('p', { class: 'ml-note' },
    T(`Intel ${pctS(vend.intel, cs.n)} · AMD ${pctS(vend.amd, cs.n)}. Idade = ${cx.ref} menos o ano de lançamento do modelo.`,
      `Intel ${pctS(vend.intel, cs.n)} · AMD ${pctS(vend.amd, cs.n)}. Age = ${cx.ref} minus the model release year.`)));
  // tabela por sub-recorte
  const kids = cx.children.filter((k) => (k.agg.pop || {}).tm);
  if (kids.length >= 2) {
    const rows = kids.map((k) => {
      const g = k.agg, n = g.pop.tm, b = g.ram_bands || {}, c = cpuStats(g.cpu_tm || g.cpu, cx.ref);
      return { k, n, ram: ramAvg(g), p8: pct((b['<8'] || 0) + (b['8'] || 0), n), p16: pct((b['12'] || 0) + (b['16'] || 0), n),
        p32: pct((b['24'] || 0) + (b['32'] || 0) + (b['>32'] || 0), n), age: c.meanAge, top: c.top[0] ? c.top[0][0] : '' };
    }).sort((x, y) => (x.ram || 0) - (y.ram || 0));
    secs.push(el('h3', {}, T('Por recorte', 'By selection')));
    secs.push(tbl([{ t: T('Recorte', 'Selection') }, { t: T('Times', 'Teams'), n: true }, { t: T('Máq. de time', 'Team mach.'), n: true },
      { t: T('RAM média', 'Avg RAM'), n: true }, { t: '≤ 8 GB', n: true }, { t: '12–16 GB', n: true }, { t: '≥ 24 GB', n: true },
      { t: T('Idade CPU', 'CPU age'), n: true }, { t: T('CPU mais comum', 'Most common CPU') }],
    rows.map((r) => row([r.k.name, { t: (r.k.agg.pop || {}).teams || 0, n: true }, { t: r.n, n: true },
      { t: r.ram != null ? GB(r.ram) + ' GB' : '—', n: true }, { t: r.p8 + '%', n: true }, { t: r.p16 + '%', n: true }, { t: r.p32 + '%', n: true },
      { t: r.age != null ? r1(r.age) : '—', n: true }, r.top.replace(/\(R\)|\(TM\)|CPU|@.*$/g, '').replace(/\s+/g, ' ').trim()]))));
    const lo = rows[0], hi = rows[rows.length - 1];
    const ages = rows.filter((r) => r.age != null).sort((x, y) => y.age - x.age);
    secs.push(el('p', { class: 'ml-note' },
      T(`Menos RAM: ${lo.k.name} (${GB(lo.ram)} GB). Mais RAM: ${hi.k.name} (${GB(hi.ram)} GB).`,
        `Least RAM: ${lo.k.name} (${GB(lo.ram)} GB). Most RAM: ${hi.k.name} (${GB(hi.ram)} GB).`)
      + (ages.length >= 2 ? ' ' + T(`CPUs mais antigas: ${ages[0].k.name} (${r1(ages[0].age)} anos). Mais novas: ${ages[ages.length - 1].k.name} (${r1(ages[ages.length - 1].age)} anos).`,
        `Oldest CPUs: ${ages[0].k.name} (${r1(ages[0].age)} years). Newest: ${ages[ages.length - 1].k.name} (${r1(ages[ages.length - 1].age)} years).`) : '')));
  }
  return el('div', { class: 'section' }, ...secs);
}

// ---- 4. editores -----------------------------------------------------------------------------
function editorsSection(a, cx) {
  const tm = cx.tm; if (!tm) return null;
  const ad = a.ed_adopt || {}, g = a.ed_groups || {}, cnt = a.ed_count || {}, pf = a.profiles || {};
  const secs = [el('h2', {}, T('⌨ Editores na prova', '⌨ Editors in the contest'))];
  secs.push(el('p', { class: 'ml-note' },
    T('Um editor conta como usado quando ficou aberto por 60 minutos ou mais durante a prova. Um time pode usar mais de um.',
      'An editor counts as used when it was open for 60 minutes or more during the contest. A team can use more than one.')));
  secs.push(el('div', { class: 'stat-cards' },
    ...GROUPS.map((gr) => card(pctS(g[gr], tm), groupName(gr))),
    card(pctS(cnt['1'], tm), T('times com 1 editor', 'teams with 1 editor')),
    card(pctS((cnt['2'] || 0) + (cnt['3+'] || 0), tm), T('com 2 ou mais', 'with 2 or more'))));
  const two = el('div', { class: 'two-col' });
  const eds = Object.entries(ad).sort((x, y) => y[1] - x[1]);
  two.append(box(T('Adoção por editor (máquinas de time)', 'Adoption per editor (team machines)'),
    hBarChart(eds.map(([k, v]) => ({ label: edName(k), value: v, color: GROUP_COLOR[edGroup(k)] })), { total: tm, maxRows: 12 })));
  two.append(box(T('Perfil puro (um grupo em 60% ou mais da prova)', 'Pure profile (one group for 60% or more of the contest)'),
    hBarChart(PROFS.filter((p) => pf[p]).map((p) => ({ label: profName(p), value: pf[p], color: GROUP_COLOR[p] })), { total: tm })));
  secs.push(two);
  // perfis por sub-recorte
  const kids = cx.children.filter((k) => (k.agg.pop || {}).tm >= 3);
  if (kids.length >= 2) {
    secs.push(el('h3', {}, T('Por recorte', 'By selection')));
    const rows = kids.map((k) => {
      const ag = k.agg, n = ag.pop.tm, gg = ag.ed_groups || {}, aa = ag.ed_adopt || {}, pp = ag.profiles || {};
      const dom = Object.entries(pp).filter(([p]) => p !== 'mixed' && p !== 'none').sort((x, y) => y[1] - x[1])[0];
      return row([k.name, { t: n, n: true }, { t: pctS(gg.vscode, n), n: true }, { t: pctS(gg.jetbrains, n), n: true },
        { t: pctS(gg.codeblocks, n), n: true }, { t: pctS(gg.light, n), n: true }, { t: pctS(aa.vim, n), n: true },
        dom ? profName(dom[0]) + ' ' + pctS(dom[1], n) : '—']);
    });
    secs.push(tbl([{ t: T('Recorte', 'Selection') }, { t: T('Máq.', 'Mach.'), n: true }, { t: 'VS Code', n: true }, { t: 'JetBrains', n: true },
      { t: 'Code::Blocks', n: true }, { t: T('Leves', 'Light'), n: true }, { t: 'Vim', n: true }, { t: T('Perfil dominante', 'Dominant profile') }], rows));
  }
  // linha do tempo: máquinas com cada editor aberto, por janela de 10 min
  const series = a.series || [];
  if (series.length && cx.start) {
    const totals = {};
    series.forEach((s) => Object.entries(s.ed || {}).forEach(([k, v]) => { totals[k] = Math.max(totals[k] || 0, v); }));
    const keys = Object.keys(totals).filter((k) => totals[k] >= Math.max(1, (a.seen || 0) * 0.01)).sort((x, y) => totals[y] - totals[x]);
    const lines = keys.map((k) => ({ label: edName(k), color: GROUP_COLOR[edGroup(k)] === '#7f8c8d' ? undefined : undefined,
      points: series.map((s) => ({ x: (s.t - cx.start) / 60, y: (s.ed || {})[k] || 0 })).filter((p) => p.x >= 0 && p.x <= cx.dur) }));
    if (lines.length) {
      secs.push(el('h3', {}, T('Máquinas com o editor aberto ao longo da prova', 'Machines with the editor open over the contest')));
      secs.push(multiLineChart(lines, { step: false, xMax: cx.dur, height: 260 }));
    }
  }
  return el('div', { class: 'section' }, ...secs);
}

// ---- 5. editores × colocação -------------------------------------------------------------------
function rankSection(a, cx, opts) {
  const re = a.rank_ed;
  const h = el('h2', {}, T('🏆 Editores e colocação', '🏆 Editors and placement'));
  const mode = (opts.link && opts.link.mode) || 'proxy';
  if (mode !== 'ua') {
    return el('div', { class: 'section' }, h, el('div', { class: 'ml-card' },
      T('Sem vínculo máquina-time nesta coleta. Este quadro precisa do login pelo navegador do mlinux, que informa a máquina.',
        'No machine-team link in this collection. This panel needs the login from the mlinux browser, which reports the machine.')));
  }
  if (!re || re.n < MIN_RANK_TEAMS) {
    return el('div', { class: 'section' }, h, el('div', { class: 'ml-card' },
      T(`Este recorte tem ${re ? re.n : 0} time(s) vinculado(s) a uma máquina e com posição no placar. Este quadro aparece com ${MIN_RANK_TEAMS} ou mais times.`,
        `This selection has ${re ? re.n : 0} team(s) linked to a machine and placed on the scoreboard. This panel needs ${MIN_RANK_TEAMS} or more teams.`)));
  }
  const cols = [['all', T('Todos', 'All')], ['top30', 'Top 30'], ['q1', T('Top 25%', 'Top 25%')], ['p10', T('Top 10%', 'Top 10%')]];
  const cell = (slice, k, map) => ({ t: pctS(((re[slice] || {})[map] || {})[k], (re[slice] || {}).n), n: true });
  const rows = [];
  GROUPS.forEach((gr) => rows.push(row([groupName(gr), ...cols.map(([s]) => cell(s, gr, 'grp'))], true)));
  const eds = Object.entries(re.all.ed || {}).sort((x, y) => y[1] - x[1]);
  eds.forEach(([k]) => rows.push(row([edName(k), ...cols.map(([s]) => cell(s, k, 'ed'))])));
  return el('div', { class: 'section' }, h,
    el('p', { class: 'ml-note' },
      T(`Parte dos times de cada grupo que usou o editor (60 minutos ou mais). Top k = os k times deste recorte mais bem colocados no placar geral. ${re.n} times vinculados.`,
        `Share of the teams in each group that used the editor (60 minutes or more). Top k = the k best-placed teams of this selection on the overall scoreboard. ${re.n} linked teams.`)),
    tbl([{ t: T('Editor', 'Editor') }, ...cols.map(([s, l]) => ({ t: l + ' (' + ((re[s] || {}).n || 0) + ')', n: true }))], rows, 'narrow'));
}

// ---- 6. pressão de memória ---------------------------------------------------------------------
function pressureSection(a, cx) {
  const pr = a.pressure || {};
  const keys = Object.keys(pr); if (!keys.length) return null;
  const secs = [el('h2', {}, T('🧠 Pressão de memória', '🧠 Memory pressure'))];
  secs.push(el('p', { class: 'ml-note' },
    T('Memória usada e swap ao longo da prova, por RAM instalada e por perfil de editor. Média das máquinas de time do recorte, em janelas de 30 minutos.',
      'Memory in use and swap over the contest, by installed RAM and by editor profile. Average of the team machines of the selection, in 30-minute windows.')));
  // por faixa de RAM (soma dos perfis)
  const byBand = {};
  keys.forEach((k) => {
    const [b] = k.split('|'); byBand[b] = byBand[b] || { n: 0, bins: {} };
    byBand[b].n += pr[k].n || 0;
    (pr[k].series || []).forEach((s) => { const t = byBand[b].bins[s.t] = byBand[b].bins[s.t] || { mem_sum: 0, mem_n: 0, sw_sum: 0, sw_n: 0 };
      t.mem_sum += s.mem_sum || 0; t.mem_n += s.mem_n || 0; t.sw_sum += s.sw_sum || 0; t.sw_n += s.sw_n || 0; });
  });
  const line = (bins, f) => Object.keys(bins).map(Number).sort((x, y) => x - y).filter((t) => t >= 0 && t / 60 <= cx.dur)
    .map((t) => ({ x: t / 60 + 15, y: f(bins[t]) })).filter((p) => p.y != null);
  const bandsHere = PBANDS.filter((b) => byBand[b] && byBand[b].n >= 3);
  if (bandsHere.length) {
    const two = el('div', { class: 'two-col' });
    two.append(box(T('Memória usada (%) por RAM instalada', 'Memory in use (%) by installed RAM'),
      multiLineChart(bandsHere.map((b) => ({ label: b + ' GB (' + byBand[b].n + ')', color: BAND_COLOR[b],
        points: line(byBand[b].bins, (t) => (t.mem_n ? Math.round(t.mem_sum / t.mem_n) : null)) })),
      { step: false, xMax: cx.dur, yMax: 100, yUnit: '%', height: 240 })));
    two.append(box(T('Swap usado (MB) por RAM instalada', 'Swap in use (MB) by installed RAM'),
      multiLineChart(bandsHere.map((b) => ({ label: b + ' GB (' + byBand[b].n + ')', color: BAND_COLOR[b],
        points: line(byBand[b].bins, (t) => (t.sw_n ? Math.round(t.sw_sum / t.sw_n) : null)) })),
      { step: false, xMax: cx.dur, height: 240 })));
    secs.push(two);
  }
  // 8 GB por perfil (onde a pressão aparece)
  const p8 = keys.filter((k) => k.split('|')[0] === '8' && pr[k].n >= 3 && k.split('|')[1] !== 'none');
  if (p8.length >= 2) {
    const bins = (k) => { const o = {}; (pr[k].series || []).forEach((s) => { o[s.t] = s; }); return o; };
    secs.push(box(T('Máquinas de 8 GB: memória usada (%) por perfil de editor', '8 GB machines: memory in use (%) by editor profile'),
      multiLineChart(p8.map((k) => ({ label: profName(k.split('|')[1]) + ' (' + pr[k].n + ')', color: GROUP_COLOR[k.split('|')[1]],
        points: line(bins(k), (t) => (t.mem_n ? Math.round(t.mem_sum / t.mem_n) : null)) })),
      { step: false, xMax: cx.dur, yMax: 100, yUnit: '%', height: 240 })));
  }
  // tabela faixa × perfil (n ≥ 3)
  const rows = keys.map((k) => ({ k, v: pr[k], b: k.split('|')[0], p: k.split('|')[1] })).filter((x) => x.v.n >= 3)
    .sort((x, y) => (PBANDS.indexOf(x.b) - PBANDS.indexOf(y.b)) || (y.v.n - x.v.n));
  if (rows.length) {
    secs.push(tbl([{ t: 'RAM' }, { t: T('Perfil', 'Profile') }, { t: 'N', n: true }, { t: T('Mem. início', 'Mem. start'), n: true },
      { t: T('Mem. última hora', 'Mem. last hour'), n: true }, { t: T('Swap médio', 'Avg swap'), n: true }, { t: T('Swap máx.', 'Max swap'), n: true }],
    rows.map((x) => row([x.b + ' GB', profName(x.p), { t: x.v.n, n: true },
      { t: x.v.mem0_n ? Math.round(x.v.mem0_sum / x.v.mem0_n) + '%' : '—', n: true },
      { t: x.v.mem4_n ? Math.round(x.v.mem4_sum / x.v.mem4_n) + '%' : '—', n: true },
      { t: x.v.sw_n ? Math.round(x.v.sw_sum / x.v.sw_n) + ' MB' : '—', n: true },
      { t: (x.v.sw_max || 0) + ' MB', n: true }]))));
    secs.push(el('p', { class: 'ml-note' }, T('Grupos com menos de 3 máquinas não aparecem.', 'Groups with fewer than 3 machines are not shown.')));
  }
  return el('div', { class: 'section' }, ...secs);
}

// ---- 7. ao longo da prova (séries de 10 min) -------------------------------------------------
function seriesCharts(series) {
  if (!series || !series.length) return [];
  const pts = (f) => series.map((s) => ({ x: s.t, y: f(s) }));
  const out = [el('h2', {}, T('📈 Ao longo da coleta', '📈 Over the collection window'))];
  const grid = el('div', { class: 'two-col' });
  grid.append(
    box(T('Máquinas ativas', 'Active machines'), lineChart(pts((s) => s.act || 0), { height: 180 })),
    box(T('Memória média (%)', 'Average memory (%)'),
      lineChart(pts((s) => (s.mem_n ? Math.round(s.mem_sum / s.mem_n) : 0)), { height: 180 })),
    box(T('Swap médio (MB)', 'Average swap (MB)'),
      lineChart(pts((s) => (s.sw_n ? Math.round(s.sw_sum / s.sw_n) : 0)), { height: 180 })),
    box(T('Load médio', 'Average load'),
      lineChart(pts((s) => (s.ld_n ? Math.round((s.ld_sum / s.ld_n) * 100) / 100 : 0)), { height: 180 })));
  if (series.some((s) => s.fw_off)) grid.append(box(T('Máquinas sem firewall', 'Machines without firewall'), lineChart(pts((s) => s.fw_off || 0), { height: 180 })));
  out.push(grid);
  return out;
}

// ---- 8. operação: frota vista, atenção, posição da sede, máquinas ------------------------------
function attentionSection(a) {
  const flags = [];
  if (a.firewall_off) flags.push(T(`🔥 ${a.firewall_off} sem firewall`, `🔥 ${a.firewall_off} without firewall`));
  if (a.screen_lock) flags.push(T(`🔒 ${a.screen_lock} com tela travada`, `🔒 ${a.screen_lock} screen-locked`));
  if (a.disk_high) flags.push(T(`💾 ${a.disk_high} com /home ≥90%`, `💾 ${a.disk_high} with /home ≥90%`));
  if (a.alerts) flags.push(T(`⚠ ${a.alerts} alertas`, `⚠ ${a.alerts} alerts`));
  if (!flags.length) return null;
  return el('div', { class: 'section' }, el('h2', {}, T('Atenção', 'Attention')),
    el('ul', { style: 'margin:.2rem 0 0 1.1rem' }, ...flags.map((x) => el('li', {}, x))));
}
function rankLine(r, label) {
  if (!r || !r.n) return null;
  const f = (x) => (x ? `#${x}/${r.n}` : '—');
  return el('div', {}, el('b', {}, label + ' '),
    T(`RAM ${f(r.ram)} · CPU ${f(r.cpu)} · editores ${f(r.ed)}`, `RAM ${f(r.ram)} · CPU ${f(r.cpu)} · editors ${f(r.ed)}`));
}
function fleetSection(a, cx, opts) {
  const secs = [el('h2', {}, T('⚙ Frota vista na prova', '⚙ Fleet seen in the contest'))];
  const pop = a.pop || {};
  secs.push(el('p', { class: 'ml-note' },
    T(`${a.machines_total || 0} máquinas cadastradas, ${a.seen || 0} vistas na janela, ${pop.used || 0} usadas na prova, ${pop.linked || 0} vinculadas a um time pelo login. Reservas e máquinas sem uso ficam fora das seções acima.`,
      `${a.machines_total || 0} registered machines, ${a.seen || 0} seen in the window, ${pop.used || 0} used in the contest, ${pop.linked || 0} linked to a team by the login. Spares and unused machines stay out of the sections above.`)));
  const two = el('div', { class: 'two-col' });
  const rb = a.ram_bands_all || {};
  const rams = BANDS.filter((b) => rb[b]).map((b) => ({ label: b + ' GB', value: rb[b] }));
  if (rams.length) two.append(box(T('RAM de todas as vistas', 'RAM of all seen'), hBarChart(rams, {})));
  const cpus = Object.entries(a.cpu || {}).sort((x, y) => y[1] - x[1]);
  if (cpus.length) two.append(box(T('Processadores de todas as vistas', 'Processors of all seen'),
    hBarChart(cpus.map(([k, v]) => ({ label: k.replace(/\(R\)|\(TM\)|CPU|@.*$/g, '').replace(/\s+/g, ' ').trim(), value: v })), { maxRows: 10 })));
  if (a.ranks) two.append(el('div', {}, el('div', { class: 'chart-title' }, T('Posição da sede', 'Site standing')),
    rankLine(a.ranks.pais, T('No país:', 'In the country:')), rankLine(a.ranks.geral, T('No geral:', 'Overall:')),
    el('div', { class: 'ml-note' }, T('RAM e CPU médias das máquinas de time; editores = minutos de editor na prova.', 'Average RAM and CPU of team machines; editors = editor minutes in the contest.'))));
  secs.push(two);
  // máquinas da sede (só em sedes[]; o relatório NÃO usa — MAC fica fora dele)
  if (opts.showMachines && a.machines && a.machines.length) {
    const tb = el('tbody');
    a.machines.slice().sort((x, y) => (y.pts || 0) - (x.pts || 0) || ((y.editors_time || {}).total || 0) - ((x.editors_time || {}).total || 0))
      .forEach((m) => {
        tb.append(el('tr', {},
          el('td', {}, el('code', {}, m.mac)),
          el('td', {}, m.processor || '?'),
          el('td', { class: 'n' }, String(m.cores || 0)),
          el('td', { class: 'n' }, GB(m.mem_mb || 0) + ' GB'),
          el('td', {}, m.team ? String(m.team) + (m.chosen === false ? ' ' + T('(2ª máquina)', '(2nd machine)') : '')
            : m.binding ? String(m.binding.user_id || m.binding.team || m.binding) : '—'),
          el('td', {}, (m.eds || []).map(edName).join(', ') || '—'),
          el('td', {}, m.prof ? profName(m.prof) : '—'),
          el('td', { class: 'n' }, m.edmax != null ? fmtMin(m.edmax) : '—'),
          el('td', {}, [m.used ? '' : T('ociosa', 'idle'), m.fw === false ? '🔥' : '', m.sl ? '🔒' : '',
            (m.home_pct || 0) >= 90 ? '💾' : ''].filter(Boolean).join(' '))));
      });
    secs.push(el('h3', {}, T('Máquinas', 'Machines')));
    secs.push(el('div', { class: 'tblwrap', style: 'overflow-x:auto' },
      el('table', { class: 'moj' },
        el('thead', {}, el('tr', {},
          el('th', {}, 'MAC'), el('th', {}, T('Processador', 'Processor')),
          el('th', { class: 'n' }, T('Núcleos', 'Cores')), el('th', { class: 'n' }, 'RAM'),
          el('th', {}, T('Time', 'Team')), el('th', {}, T('Editores na prova', 'Editors in contest')),
          el('th', {}, T('Perfil', 'Profile')), el('th', { class: 'n' }, T('Editor máx.', 'Top editor')), el('th', {}, ''))),
        tb)));
  }
  return el('div', { class: 'section' }, ...secs);
}

// ---- 9. como ler ------------------------------------------------------------------------------
function legend(opts) {
  const li = (k, txt) => el('li', {}, el('b', {}, k + ': '), txt);
  const mode = (opts.link && opts.link.mode) || 'proxy';
  return el('details', { class: 'small', style: 'margin:.3rem 0 .6rem' },
    el('summary', {}, T('Como ler este relatório', 'How to read this report')),
    el('ul', { style: 'margin:.2rem 0 0 1.1rem' },
      li(T('Vista na prova', 'Seen in the contest'), T('máquina que reportou ao nutellaboot na janela da coleta (prova mais uma hora antes e depois).',
        'machine that reported to nutellaboot within the collection window (the contest plus one hour before and after).')),
      li(T('Máquina de time', 'Team machine'), mode === 'ua'
        ? T('a máquina em que o time fez login pelo navegador do mlinux (o navegador informa a máquina). Um time com duas máquinas conta a de mais amostras na prova. Máquinas usadas sem login vinculado também entram.',
          'the machine where the team logged in through the mlinux browser (the browser reports the machine). A team with two machines counts the one with more samples in the contest. Machines used without a linked login also count.')
        : T('máquina com algum editor aberto por 10 minutos ou mais durante a prova. Nesta coleta o vínculo pelo login não cobriu times suficientes.',
          'machine with some editor open for 10 minutes or more during the contest. In this collection the login link did not cover enough teams.')),
      li(T('Editor usado', 'Editor used'), T('aberto por 60 minutos ou mais durante a prova, medido nas amostras da máquina (cerca de uma por minuto). O tempo acumulado desde a instalação não entra.',
        'open for 60 minutes or more during the contest, measured in the machine samples (about one per minute). Cumulative time since installation does not count.')),
      li(T('Perfil puro', 'Pure profile'), T('um grupo de editores aberto em 60% ou mais das amostras da prova. Leve exige quase nenhum uso de IDE pesada. Sem grupo dominante: misto.',
        'one editor group open in 60% or more of the contest samples. Light requires almost no heavy IDE use. No dominant group: mixed.')),
      li(T('Grupos', 'Groups'), 'VS Code · JetBrains (IntelliJ IDEA, CLion, PyCharm) · Code::Blocks · ' + T('leves (Vim, gedit, Geany, Emacs).', 'light (Vim, gedit, Geany, Emacs).')),
      li(T('RAM média', 'Average RAM'), T('em um recorte com várias sedes, é a média das médias de cada sede. Sedes grandes não dominam.',
        'in a selection with several sites, it is the mean of the per-site means. Large sites do not dominate.')),
      li(T('Idade da CPU', 'CPU age'), T('ano da prova menos o ano de lançamento inferido do modelo (geração Intel, série Ryzen). Modelos sem ano conhecido ficam fora da média.',
        'contest year minus the release year inferred from the model (Intel generation, Ryzen series). Models with no known year stay out of the mean.')),
      li(T('Top k', 'Top k'), T('os k times do recorte mais bem colocados no placar geral. O quadro só aparece com 30 ou mais times vinculados. Convidados não têm posição.',
        'the k best-placed teams of the selection on the overall scoreboard. The panel needs 30 or more linked teams. Guests have no position.')),
      li(T('Memória e swap', 'Memory and swap'), T('média das amostras da máquina na prova. Início = primeiros 30 minutos. Última hora = últimos 60 minutos.',
        'average of the machine samples in the contest. Start = first 30 minutes. Last hour = last 60 minutes.'))));
}

export function mlinuxSections(a, opts = {}) {
  if (!a) return [el('p', { class: 'muted' }, T('Sem dados coletados.', 'No data collected.'))];
  const cx = ctxOf(a, opts);
  const secs = [];
  const push = (x) => { if (x) secs.push(x); };
  if (a.pop) {
    push(cardsSection(a, cx));
    push(attentionSection(a));
    push(observations(a, cx, opts));
    push(hardwareSection(a, cx));
    push(editorsSection(a, cx));
    push(rankSection(a, cx, opts));
    push(pressureSection(a, cx));
    seriesCharts(a.series).forEach(push);
    push(fleetSection(a, cx, opts));
    push(legend(opts));
    return secs;
  }
  // cache antigo (antes do relatório 2.0): só o que existe
  push(el('div', { class: 'stat-cards' },
    card(a.machines_total || 0, T('máquinas', 'machines')), card(a.seen || 0, T('vistas na prova', 'seen in contest')),
    card(GB(a.ram_total_mb || 0) + ' GB', T('RAM somada', 'total RAM')), card(a.cores_total || 0, T('núcleos', 'cores'))));
  push(attentionSection(a));
  push(el('p', { class: 'ml-note' }, T('Cache antigo. Rode "Coletar agora" para o relatório completo.', 'Old cache. Run "Collect now" for the full report.')));
  seriesCharts(a.series).forEach(push);
  push(fleetSection(a, cx, opts));
  return secs;
}
