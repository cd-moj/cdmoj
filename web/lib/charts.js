// shared/charts.js — gráficos minimalistas em SVG, SEM bibliotecas externas
// (build-free / offline). Renderiza barras, pizza e rosca. Cada função devolve
// um elemento DOM (svg ou div com svg + legenda) pronto para inserir.
//
// NOTA: este módulo é novo e independente; não altera os demais shared/*.

const PALETTE = [
  '#216097', '#7a5ada', '#1a7f37', '#c4314b', '#a66a00', '#23b0de',
  '#12d88b', '#6060a1', '#ef8a56', '#d94f9a', '#5b6b7d', '#0aa', '#84a',
];

function svgEl(tag, attrs) {
  const e = document.createElementNS('http://www.w3.org/2000/svg', tag);
  for (const [k, v] of Object.entries(attrs || {})) e.setAttribute(k, v);
  return e;
}
function colorAt(i) { return PALETTE[i % PALETTE.length]; }
function esc(s) { return String(s); }

// ---- barras verticais --------------------------------------------------------
// data: [{label, value}], opts: {width,height,color,maxLabels}
export function barChart(data, opts = {}) {
  const W = opts.width || 720, H = opts.height || 240;
  const padL = 34, padB = opts.rotateLabels ? 48 : 22, padT = 10, padR = 8;
  const innerW = W - padL - padR, innerH = H - padT - padB;
  const max = Math.max(1, ...data.map(d => d.value));
  const n = Math.max(1, data.length);
  const bw = innerW / n;
  const svg = svgEl('svg', { class: 'chart', viewBox: `0 0 ${W} ${H}`, width: W, height: H, role: 'img' });

  // eixo y (3 marcas)
  for (let g = 0; g <= 2; g++) {
    const val = Math.round(max * g / 2);
    const y = padT + innerH - (innerH * g / 2);
    svg.append(svgEl('line', { x1: padL, y1: y, x2: W - padR, y2: y, stroke: '#e3e8f2', 'stroke-width': 1 }));
    const tx = svgEl('text', { x: padL - 5, y: y + 3, 'text-anchor': 'end', 'font-size': 10, fill: '#5b6b7d' });
    tx.textContent = val; svg.append(tx);
  }

  const everyLabel = Math.ceil(n / (opts.maxLabels || n));
  data.forEach((d, i) => {
    const h = (d.value / max) * innerH;
    const x = padL + i * bw;
    const y = padT + innerH - h;
    svg.append(svgEl('rect', { x: x + bw * 0.12, y, width: bw * 0.76, height: Math.max(0, h), fill: opts.color || colorAt(i), rx: 2 }));
    if (i % everyLabel === 0) {
      const cx = x + bw / 2;
      const ty = padT + innerH + 12;
      const t = svgEl('text', { 'font-size': 9, fill: '#5b6b7d' });
      if (opts.rotateLabels) {
        t.setAttribute('x', cx); t.setAttribute('y', ty + 4);
        t.setAttribute('text-anchor', 'end');
        t.setAttribute('transform', `rotate(-45 ${cx} ${ty + 4})`);
      } else {
        t.setAttribute('x', cx); t.setAttribute('y', ty); t.setAttribute('text-anchor', 'middle');
      }
      t.textContent = esc(d.label);
      svg.append(t);
    }
    const title = svgEl('title', {}); title.textContent = `${d.label}: ${d.value}`;
    svg.append(title);
  });
  return svg;
}

// ---- pizza / rosca -----------------------------------------------------------
// data: [{label,value,color?}], opts:{size,donut(0..1),colors}
export function pieChart(data, opts = {}) {
  const size = opts.size || 220, r = size / 2, cx = r, cy = r;
  const total = data.reduce((a, d) => a + (d.value || 0), 0);
  const wrap = document.createElement('div');
  const svg = svgEl('svg', { class: 'chart', viewBox: `0 0 ${size} ${size}`, width: size, height: size, role: 'img' });

  if (total <= 0) {
    svg.append(svgEl('circle', { cx, cy, r: r - 2, fill: '#eef3fb' }));
  } else {
    let acc = 0;
    data.forEach((d, i) => {
      const frac = (d.value || 0) / total;
      if (frac <= 0) return;
      const a0 = acc * 2 * Math.PI - Math.PI / 2;
      acc += frac;
      const a1 = acc * 2 * Math.PI - Math.PI / 2;
      const color = d.color || (opts.colors && opts.colors[i]) || colorAt(i);
      if (frac >= 0.9999) {
        const c = svgEl('circle', { cx, cy, r: r - 2, fill: color });
        const title = svgEl('title', {}); title.textContent = `${d.label}: ${d.value}`;
        c.append(title); svg.append(c);
      } else {
        const x0 = cx + (r - 2) * Math.cos(a0), y0 = cy + (r - 2) * Math.sin(a0);
        const x1 = cx + (r - 2) * Math.cos(a1), y1 = cy + (r - 2) * Math.sin(a1);
        const large = (a1 - a0) > Math.PI ? 1 : 0;
        const path = svgEl('path', {
          d: `M ${cx} ${cy} L ${x0} ${y0} A ${r - 2} ${r - 2} 0 ${large} 1 ${x1} ${y1} Z`,
          fill: color, stroke: '#fff', 'stroke-width': 1,
        });
        const title = svgEl('title', {}); title.textContent = `${d.label}: ${d.value} (${Math.round(frac * 100)}%)`;
        path.append(title); svg.append(path);
      }
    });
    const donut = opts.donut != null ? opts.donut : 0;
    if (donut > 0) svg.append(svgEl('circle', { cx, cy, r: (r - 2) * donut, fill: '#fff' }));
  }
  wrap.append(svg);

  // legenda
  const legend = document.createElement('div');
  legend.className = 'legend';
  data.forEach((d, i) => {
    if (!(d.value > 0)) return;
    const color = d.color || (opts.colors && opts.colors[i]) || colorAt(i);
    const span = document.createElement('span');
    span.innerHTML = `<span class="sw" style="background:${color}"></span>${esc(d.label)} (${d.value})`;
    legend.append(span);
  });
  wrap.append(legend);
  return wrap;
}

// ---- barras horizontais ------------------------------------------------------
// Ideal p/ distribuições categóricas de RÓTULO LONGO (veredictos, linguagens):
// cada categoria ocupa a sua própria linha — rótulo | barra proporcional | valor·%.
// Muito mais legível que uma pizza + legenda quando há nomes grandes/muitas fatias.
// data: [{label,value,color?}]; opts:{total, hideZero, maxRows}.
export function hBarChart(data, opts = {}) {
  let rows = (data || []).slice();
  if (opts.hideZero) rows = rows.filter(d => (d.value || 0) > 0);
  if (opts.maxRows && rows.length > opts.maxRows) rows = rows.slice(0, opts.maxRows);
  const total = opts.total != null ? opts.total : (data || []).reduce((a, d) => a + (d.value || 0), 0);
  const max = Math.max(1, ...rows.map(d => d.value || 0));
  const wrap = document.createElement('div');
  wrap.className = 'hbars';
  if (!rows.length) {
    const empty = document.createElement('div'); empty.className = 'muted small'; empty.textContent = '—';
    wrap.append(empty); return wrap;
  }
  rows.forEach((d, i) => {
    const color = d.color || colorAt(i);
    const row = document.createElement('div'); row.className = 'hbar-row';
    const lab = document.createElement('div'); lab.className = 'hbar-label'; lab.title = esc(d.label); lab.textContent = esc(d.label);
    const track = document.createElement('div'); track.className = 'hbar-track';
    const fill = document.createElement('div'); fill.className = 'hbar-fill';
    fill.style.width = Math.max(1.5, ((d.value || 0) / max) * 100) + '%';
    fill.style.background = color;
    track.append(fill);
    const val = document.createElement('div'); val.className = 'hbar-val';
    val.textContent = String(d.value || 0) + (total > 0 ? '  ·  ' + Math.round(((d.value || 0) / total) * 100) + '%' : '');
    row.append(lab, track, val);
    wrap.append(row);
  });
  return wrap;
}

// ---- linha / área -----------------------------------------------------------
// points: [{x:Date|number(epoch s)|string('YYYY-MM-DD'), y:number}] (ordenados por x),
// ou [{label, value}] (eixo x categórico igualmente espaçado).
// opts: {width,height,color,fill(bool),yLabel,maxLabels}
export function lineChart(points, opts = {}) {
  const W = opts.width || 720, H = opts.height || 240;
  const padL = 36, padB = 26, padT = 12, padR = 10;
  const innerW = W - padL - padR, innerH = H - padT - padB;
  const color = opts.color || colorAt(0);
  const svg = svgEl('svg', { class: 'chart', viewBox: `0 0 ${W} ${H}`, width: W, height: H, role: 'img' });

  // normaliza pontos -> {t:number(ms ou índice), y, label}
  const toMs = (x) => {
    if (x instanceof Date) return x.getTime();
    if (typeof x === 'number') return x < 1e12 ? x * 1000 : x; // epoch s -> ms
    const d = new Date(x); return isNaN(d.getTime()) ? null : d.getTime();
  };
  let pts = (points || []).map((p, i) => {
    if (p.x !== undefined) { const t = toMs(p.x); return t == null ? null : { t, y: +p.y || 0, label: p.label }; }
    return { t: i, y: +p.value || +p.y || 0, label: p.label }; // categórico
  }).filter(Boolean);

  const max = Math.max(1, ...pts.map(p => p.y));
  // eixo y (3 marcas)
  for (let g = 0; g <= 2; g++) {
    const val = Math.round(max * g / 2);
    const y = padT + innerH - (innerH * g / 2);
    svg.append(svgEl('line', { x1: padL, y1: y, x2: W - padR, y2: y, stroke: '#e3e8f2', 'stroke-width': 1 }));
    const tx = svgEl('text', { x: padL - 5, y: y + 3, 'text-anchor': 'end', 'font-size': 10, fill: '#5b6b7d' });
    tx.textContent = val; svg.append(tx);
  }
  if (pts.length < 2) {
    if (pts.length === 1) {
      const cx = padL + innerW / 2, cy = padT + innerH - (pts[0].y / max) * innerH;
      svg.append(svgEl('circle', { cx, cy, r: 3, fill: color }));
    }
    return svg;
  }

  const tMin = pts[0].t, tMax = pts[pts.length - 1].t, tSpan = Math.max(1, tMax - tMin);
  const sx = (t) => padL + ((t - tMin) / tSpan) * innerW;
  const sy = (y) => padT + innerH - (y / max) * innerH;
  const d = pts.map((p, i) => (i ? 'L' : 'M') + sx(p.t).toFixed(1) + ' ' + sy(p.y).toFixed(1)).join(' ');

  if (opts.fill !== false) {
    const area = `M ${sx(pts[0].t).toFixed(1)} ${(padT + innerH).toFixed(1)} ` +
      pts.map(p => 'L ' + sx(p.t).toFixed(1) + ' ' + sy(p.y).toFixed(1)).join(' ') +
      ` L ${sx(pts[pts.length - 1].t).toFixed(1)} ${(padT + innerH).toFixed(1)} Z`;
    svg.append(svgEl('path', { d: area, fill: color, 'fill-opacity': 0.12, stroke: 'none' }));
  }
  svg.append(svgEl('path', { d, fill: 'none', stroke: color, 'stroke-width': 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }));

  // marca o último ponto + tooltip por ponto
  pts.forEach((p, i) => {
    const c = svgEl('circle', { cx: sx(p.t), cy: sy(p.y), r: i === pts.length - 1 ? 3.2 : 0, fill: color });
    const title = svgEl('title', {}); title.textContent = (p.label != null ? p.label + ': ' : '') + p.y;
    c.append(title); svg.append(c);
  });

  // rótulos do eixo x: primeiro e último (datas), mais alguns intermediários
  const fmtX = (t) => {
    const dt = new Date(t);
    return String(dt.getDate()).padStart(2, '0') + '/' + String(dt.getMonth() + 1).padStart(2, '0');
  };
  const nLab = Math.min(opts.maxLabels || 6, pts.length);
  for (let k = 0; k < nLab; k++) {
    const idx = Math.round(k * (pts.length - 1) / (nLab - 1 || 1));
    const p = pts[idx];
    const tx = svgEl('text', { x: sx(p.t), y: padT + innerH + 14, 'text-anchor': k === 0 ? 'start' : k === nLab - 1 ? 'end' : 'middle', 'font-size': 9, fill: '#5b6b7d' });
    tx.textContent = p.label != null && typeof points[0] === 'object' && points[0].x === undefined ? p.label : fmtX(p.t);
    svg.append(tx);
  }
  return svg;
}

// ---- heatmap estilo GitHub (calendário de atividade diária) ------------------
// countsByDate: { 'YYYY-MM-DD': n }. opts:{weeks(~26),cell,gap,color,end(Date),
//   scaleMax (corta a escala de cor, ex.: no p95), fmt(v,date)->string (texto do tooltip;
//   default "<v> submissões" — passe p/ exibir tempo, ex.: "média 12s")}.
// Devolve um <div> com o SVG + legenda "menos … mais".
export function heatmap(countsByDate, opts = {}) {
  const weeks = opts.weeks || 26;
  const cell = opts.cell || 13, gap = opts.gap || 3;
  const base = opts.color || '#216097';
  const counts = countsByDate || {};
  const wrap = document.createElement('div');

  const tag = (dt) => dt.getFullYear() + '-' + String(dt.getMonth() + 1).padStart(2, '0') + '-' + String(dt.getDate()).padStart(2, '0');
  // fim = hoje (ou opts.end); recua até o domingo da semana mais antiga
  const end = opts.end ? new Date(opts.end) : new Date();
  end.setHours(0, 0, 0, 0);
  const start = new Date(end);
  start.setDate(start.getDate() - (weeks * 7 - 1));
  start.setDate(start.getDate() - start.getDay()); // alinha no domingo

  let maxV = 1;
  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) maxV = Math.max(maxV, counts[tag(d)] || 0);
  // escala de cor: por padrão o máximo do período; opts.scaleMax permite cortar no p95 p/ não
  // deixar um único outlier "lavar" o mapa (útil quando o valor é tempo médio, não contagem).
  const scale = Math.max(1, opts.scaleMax || maxV);

  const cols = Math.ceil(((end - start) / 86400000 + 1) / 7);
  const padTop = 18, padLeft = 32;
  const W = padLeft + cols * (cell + gap) + 4;
  const H = padTop + 7 * (cell + gap) + 4;
  const svg = svgEl('svg', { class: 'chart', viewBox: `0 0 ${W} ${H}`, width: W, height: H, role: 'img' });

  // 4 níveis de intensidade
  const shade = (v) => {
    if (!v) return '#eef3fb';
    const lvl = v >= scale * 0.75 ? 0.95 : v >= scale * 0.5 ? 0.72 : v >= scale * 0.25 ? 0.5 : 0.3;
    return mix('#eef3fb', base, lvl);
  };

  // dias da semana (Seg, Qua, Sex)
  const DOW = ['', 'Seg', '', 'Qua', '', 'Sex', ''];
  DOW.forEach((lbl, r) => {
    if (!lbl) return;
    const tx = svgEl('text', { x: 2, y: padTop + r * (cell + gap) + cell - 2, 'font-size': 10, fill: '#5b6b7d' });
    tx.textContent = lbl; svg.append(tx);
  });

  const MONTHS = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  let lastMonth = -1;
  const cur = new Date(start);
  for (let c = 0; c < cols; c++) {
    // rótulo do mês na 1ª semana em que ele aparece
    if (cur.getMonth() !== lastMonth) {
      lastMonth = cur.getMonth();
      const tx = svgEl('text', { x: padLeft + c * (cell + gap), y: padTop - 5, 'font-size': 10, fill: '#5b6b7d' });
      tx.textContent = MONTHS[lastMonth]; svg.append(tx);
    }
    for (let r = 0; r < 7; r++) {
      if (cur > end) break;
      const v = counts[tag(cur)] || 0;
      const x = padLeft + c * (cell + gap), y = padTop + r * (cell + gap);
      const rect = svgEl('rect', { x, y, width: cell, height: cell, rx: 2, fill: shade(v) });
      const title = svgEl('title', {});
      title.textContent = opts.fmt ? opts.fmt(v, tag(cur)) : `${tag(cur)}: ${v} ${v === 1 ? 'submissão' : 'submissões'}`;
      rect.append(title); svg.append(rect);
      cur.setDate(cur.getDate() + 1);
    }
  }
  wrap.append(svg);

  // legenda menos→mais
  const legend = document.createElement('div');
  legend.className = 'legend';
  const lg = document.createElement('span');
  lg.style.cssText = 'display:inline-flex;align-items:center;gap:.25rem';
  lg.append(document.createTextNode('menos '));
  [0, 0.3, 0.5, 0.72, 0.95].forEach(l => {
    const s = document.createElement('span');
    s.className = 'sw';
    s.style.background = l === 0 ? '#eef3fb' : mix('#eef3fb', base, l);
    lg.append(s);
  });
  lg.append(document.createTextNode(' mais'));
  legend.append(lg);
  wrap.append(legend);
  return wrap;
}

// ---- heatmap em grade dia-da-semana × hora ----------------------------------
// Matriz 7×24 (linhas = Dom..Sáb, colunas = horas 0–23) colorida por `value`. Ideal p/
// ver QUANDO, na semana, algo piora (ex.: tempo médio de resposta) — decisão de capacidade.
// cells: [{dow:0..6 (0=Dom), hour:0..23, value:number, n?:number}].
// opts:{cell,gap,color,scaleMax, fmt(value)->string (default "média <value>s")}.
// Devolve um <div> com o SVG + legenda "menos … mais".
export function heatmapGrid(cells, opts = {}) {
  const cell = opts.cell || 22, gap = opts.gap || 4;
  const base = opts.color || '#c4314b';
  const fmt = opts.fmt || ((v) => 'média ' + v + 's');
  const DAYS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
  const wrap = document.createElement('div');

  // grade[dow][hour] = {value, n}
  const grid = Array.from({ length: 7 }, () => new Array(24).fill(null));
  let maxV = 1;
  (cells || []).forEach((c) => {
    const d = +c.dow, h = +c.hour;
    if (d >= 0 && d < 7 && h >= 0 && h < 24) {
      grid[d][h] = { value: +c.value || 0, n: +c.n || 0 };
      maxV = Math.max(maxV, +c.value || 0);
    }
  });
  const scale = Math.max(1, opts.scaleMax || maxV);
  const shade = (v) => {
    if (!v) return '#eef3fb';
    const lvl = v >= scale * 0.75 ? 0.95 : v >= scale * 0.5 ? 0.72 : v >= scale * 0.25 ? 0.5 : 0.3;
    return mix('#eef3fb', base, lvl);
  };

  const padTop = 20, padLeft = 40;
  const W = padLeft + 24 * (cell + gap) + 2;
  const H = padTop + 7 * (cell + gap) + 2;
  const svg = svgEl('svg', { class: 'chart', viewBox: `0 0 ${W} ${H}`, width: W, height: H, role: 'img' });

  // rótulos de hora (0,3,6,…,21) no topo
  for (let h = 0; h < 24; h++) {
    if (h % 3 !== 0) continue;
    const tx = svgEl('text', { x: padLeft + h * (cell + gap), y: padTop - 6, 'font-size': 11, fill: '#5b6b7d' });
    tx.textContent = h + 'h'; svg.append(tx);
  }
  for (let d = 0; d < 7; d++) {
    const ty = svgEl('text', { x: 2, y: padTop + d * (cell + gap) + cell - 5, 'font-size': 11, fill: '#5b6b7d' });
    ty.textContent = DAYS[d]; svg.append(ty);
    for (let h = 0; h < 24; h++) {
      const g = grid[d][h];
      const v = g ? g.value : 0;
      const x = padLeft + h * (cell + gap), y = padTop + d * (cell + gap);
      const rect = svgEl('rect', { x, y, width: cell, height: cell, rx: 2, fill: shade(v) });
      const title = svgEl('title', {});
      title.textContent = g
        ? `${DAYS[d]} ${h}h · ${fmt(v)} · ${g.n} ${g.n === 1 ? 'sub' : 'subs'}`
        : `${DAYS[d]} ${h}h · sem dados`;
      rect.append(title); svg.append(rect);
    }
  }
  wrap.append(svg);

  // legenda menos→mais
  const legend = document.createElement('div');
  legend.className = 'legend';
  const lg = document.createElement('span');
  lg.style.cssText = 'display:inline-flex;align-items:center;gap:.25rem';
  lg.append(document.createTextNode('menos '));
  [0, 0.3, 0.5, 0.72, 0.95].forEach(l => {
    const s = document.createElement('span');
    s.className = 'sw';
    s.style.background = l === 0 ? '#eef3fb' : mix('#eef3fb', base, l);
    lg.append(s);
  });
  lg.append(document.createTextNode(' mais'));
  legend.append(lg);
  wrap.append(legend);
  return wrap;
}

// mistura linear entre duas cores hex (#rrggbb), f em [0..1]
function mix(a, b, f) {
  const pa = hex(a), pb = hex(b);
  const c = pa.map((v, i) => Math.round(v + (pb[i] - v) * f));
  return '#' + c.map(v => v.toString(16).padStart(2, '0')).join('');
}
function hex(s) {
  s = String(s).replace('#', '');
  if (s.length === 3) s = s.split('').map(ch => ch + ch).join('');
  return [parseInt(s.slice(0, 2), 16), parseInt(s.slice(2, 4), 16), parseInt(s.slice(4, 6), 16)];
}

export { PALETTE };
