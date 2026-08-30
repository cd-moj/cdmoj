// lib/mlinux-view.js — as SEÇÕES do panorama mlinux (nutellaboot), em um lugar só.
//
// Fonte ÚNICA de três telas que precisam ser iguais: o painel do admin (mlinux-tab.js), a
// página avulsa /contest/mlinux/ (cstaff/staff, escopada pelo servidor) e o mlinux.html do
// RELATÓRIO OFFLINE (report-gen.sh inlina este arquivo + charts.js + dom.js). Recebe UM
// agregado do var/nutella.cache.json — o `global`, um nó de `by_node` ou uma entrada de
// `sedes[]` (que tem extras: machines[], ranks, series próprios) — e devolve um ARRAY de
// elementos. Só depende de dom.js e charts.js (sem rede).
import { el } from '/shared/dom.js';
import { hBarChart, lineChart } from '/lib/charts.js';
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
`;

const GB = (mb) => (mb >= 10240 ? Math.round(mb / 1024) : Math.round(mb / 102.4) / 10);
const fmtMin = (m) => (m >= 120 ? Math.round(m / 60) + 'h' : m + 'min');

function card(big, sub) {
  return el('div', { class: 'stat-card' },
    el('div', { class: 'big-num' }, String(big)), el('div', { class: 'big-sub' }, sub));
}

function rankLine(r, label) {
  if (!r || !r.n) return null;
  const f = (x) => (x ? `#${x}/${r.n}` : '—');
  return el('div', {},
    el('b', {}, label + ' '),
    T(`RAM ${f(r.ram)} · CPU ${f(r.cpu)} · editores ${f(r.ed)}`,
      `RAM ${f(r.ram)} · CPU ${f(r.cpu)} · editors ${f(r.ed)}`));
}

// séries do cache guardam SOMAS (mem_sum/mem_n…) p/ o rollup ser exato — a média é daqui
function seriesCharts(series, win) {
  if (!series || !series.length) return [];
  const pts = (f) => series.map((s) => ({ x: s.t, y: f(s) }));
  const box = (title, chart) => el('div', {}, el('div', { class: 'chart-title' }, title), chart);
  const out = [el('h2', {}, T('Ao longo da prova', 'Over the contest'))];
  const grid = el('div', { class: 'two-col' });
  grid.append(
    box(T('Máquinas ativas', 'Active machines'),
      lineChart(pts((s) => s.act || 0), { height: 180 })),
    box(T('Memória média (%)', 'Average memory (%)'),
      lineChart(pts((s) => (s.mem_n ? Math.round(s.mem_sum / s.mem_n) : 0)), { height: 180 })),
    box(T('Load médio', 'Average load'),
      lineChart(pts((s) => (s.ld_n ? Math.round((s.ld_sum / s.ld_n) * 100) / 100 : 0)), { height: 180 })));
  // editores ao longo do tempo: os 3 mais usados (máquinas com o editor aberto na janela)
  const totals = {};
  series.forEach((s) => Object.entries(s.ed || {}).forEach(([k, v]) => { totals[k] = (totals[k] || 0) + v; }));
  Object.keys(totals).sort((a, b) => totals[b] - totals[a]).slice(0, 3).forEach((ed) => {
    grid.append(box(T(`Máquinas com ${ed} aberto`, `Machines with ${ed} open`),
      lineChart(pts((s) => (s.ed || {})[ed] || 0), { height: 180 })));
  });
  out.push(grid);
  return out;
}

export function mlinuxSections(a, opts = {}) {
  if (!a) return [el('p', { class: 'muted' }, T('Sem dados coletados.', 'No data collected.'))];
  const secs = [];

  // cartões
  secs.push(el('div', { class: 'stat-cards' },
    card(a.machines_total || 0, T('máquinas', 'machines')),
    card(a.seen || 0, T('vistas na prova', 'seen in contest')),
    card(GB(a.ram_total_mb || 0) + ' GB', T('RAM somada', 'total RAM')),
    card(a.cores_total || 0, T('núcleos', 'cores')),
    card(fmtMin(a.editors_total_min || 0), T('de editor aberto', 'of editor use')),
    card(a.bound || 0, T('vinculadas a time', 'bound to a team'))));

  // estado (só o que foge do normal)
  const flags = [];
  if (a.firewall_off) flags.push(T(`🔥 ${a.firewall_off} sem firewall`, `🔥 ${a.firewall_off} without firewall`));
  if (a.screen_lock) flags.push(T(`🔒 ${a.screen_lock} com tela travada`, `🔒 ${a.screen_lock} screen-locked`));
  if (a.disk_high) flags.push(T(`💾 ${a.disk_high} com /home ≥90%`, `💾 ${a.disk_high} with /home ≥90%`));
  if (a.alerts) flags.push(T(`⚠ ${a.alerts} alertas`, `⚠ ${a.alerts} alerts`));
  if (flags.length) {
    secs.push(el('div', { class: 'section' }, el('h2', {}, T('Atenção', 'Attention')),
      el('ul', { style: 'margin:.2rem 0 0 1.1rem' }, ...flags.map((x) => el('li', {}, x)))));
  }

  // ranks da sede (país e geral) — só em entrada de sedes[]
  if (a.ranks) {
    secs.push(el('div', { class: 'section' }, el('h2', {}, T('Posição da sede', 'Site standing')),
      rankLine(a.ranks.pais, T('No país:', 'In the country:')),
      rankLine(a.ranks.geral, T('No geral:', 'Overall:'))));
  }

  // rank de editores (minutos somados; nº de máquinas no rótulo)
  const eds = Object.entries(a.editors || {}).sort((x, y) => y[1] - x[1]);
  if (eds.length) {
    secs.push(el('div', { class: 'section' }, el('h2', {}, T('Editores', 'Editors')),
      hBarChart(eds.map(([k, v]) => ({
        label: k + ' (' + ((a.editors_machines || {})[k] || 0) + T(' máq.', ' mach.') + ')',
        value: v,
      })), { maxRows: 12, unit: 'min' })));
  }

  // specs: processadores + buckets de RAM
  const cpus = Object.entries(a.cpu || {}).sort((x, y) => y[1] - x[1]);
  const ramOrder = ['<8', '8', '16', '32', '>32'];
  const rams = ramOrder.filter((k) => (a.ram_buckets || {})[k])
    .map((k) => ({ label: k + ' GB', value: a.ram_buckets[k] }));
  const two = el('div', { class: 'two-col' });
  if (cpus.length) {
    two.append(el('div', {}, el('h2', {}, T('Processadores', 'Processors')),
      hBarChart(cpus.map(([k, v]) => ({ label: k, value: v })), { maxRows: 10 })));
  }
  if (rams.length) two.append(el('div', {}, el('h2', {}, 'RAM'), hBarChart(rams, {})));
  if (cpus.length || rams.length) secs.push(el('div', { class: 'section' }, two));

  // série temporal
  seriesCharts(a.series, opts.window).forEach((x) => secs.push(x));

  // máquinas da sede (só em sedes[]; o relatório NÃO usa — MAC fica fora dele)
  if (opts.showMachines && a.machines && a.machines.length) {
    const tb = el('tbody');
    a.machines.slice().sort((x, y) => (y.editors_time.total || 0) - (x.editors_time.total || 0))
      .forEach((m) => {
        const topEd = Object.entries(m.editors_time || {}).filter(([k]) => k !== 'total')
          .sort((x, y) => y[1] - x[1])[0];
        tb.append(el('tr', {},
          el('td', {}, el('code', {}, m.mac)),
          el('td', {}, m.processor || '?'),
          el('td', { class: 'n' }, String(m.cores || 0)),
          el('td', { class: 'n' }, GB(m.mem_mb || 0) + ' GB'),
          el('td', {}, topEd ? topEd[0] + ' (' + fmtMin(topEd[1]) + ')' : '—'),
          el('td', { class: 'n' }, fmtMin((m.editors_time || {}).total || 0)),
          el('td', {}, m.binding ? String(m.binding.user_id || m.binding.team || m.binding) : '—'),
          el('td', {}, [m.fw === false ? '🔥' : '', m.sl ? '🔒' : '',
            (m.home_pct || 0) >= 90 ? '💾' : ''].join(' '))));
      });
    secs.push(el('div', { class: 'section' }, el('h2', {}, T('Máquinas', 'Machines')),
      el('div', { class: 'tblwrap', style: 'overflow-x:auto' },
        el('table', { class: 'moj' },
          el('thead', {}, el('tr', {},
            el('th', {}, 'MAC'), el('th', {}, T('Processador', 'Processor')),
            el('th', { class: 'n' }, T('Núcleos', 'Cores')), el('th', { class: 'n' }, 'RAM'),
            el('th', {}, T('Editor mais usado', 'Top editor')),
            el('th', { class: 'n' }, T('Editor total', 'Editor total')),
            el('th', {}, T('Time', 'Team')), el('th', {}, ''))),
          tb))));
  }
  return secs;
}
