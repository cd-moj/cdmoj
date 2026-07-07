// contest/admin/tasks.js — aba "🖨️ Tarefas do staff" do admin: panorama e AÇÃO sobre a fila
// de impressão + balões (GET /contest/staff/queue — o admin vê TUDO e o load já reconcilia os
// balões pendentes), desempenho por staff e a config de escopo por regex (staff-filters).
// Auto-refresh ≥15s e pausado com o painel oculto (o reconcile de balões roda a cada load da
// fila — não martelar).
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';

const enc = encodeURIComponent;
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');
const fmtS = (s) => { s = Math.max(0, Math.round(+s || 0)); if (s < 60) return s + 's'; const m = Math.floor(s / 60); return m < 60 ? m + 'min' : Math.floor(m / 60) + 'h' + (m % 60 ? (m % 60) + 'min' : ''); };
const nowE = () => Math.floor(Date.now() / 1000);
const STATUS = {
  pending: { t: '🕓 pendente', cls: 'flag-warn' },
  printed: { t: '🖨️ processada', cls: '' },
  delivered: { t: '✅ entregue', cls: '' },
};
const safeRe = (rx) => { try { return new RegExp(rx, 'i'); } catch { return null; } };
const csvCell = (v) => { const s = String(v == null ? '' : v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
const toCsv = (rows) => rows.map((r) => r.map(csvCell).join(',')).join('\r\n') + '\r\n';
function downloadText(filename, text, mime) {
  const blob = new Blob([text], { type: (mime || 'text/plain') + ';charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: filename }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}

export function makeTasksTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', {});
  let timer = null;
  let QUEUE = [];        // fila completa (admin)
  let SF = null;         // {staff:[{login,...}], regions:[], filters:{login:[entradas]}}
  let TEAMS = {};        // login -> {region,...} (/contest/teams — p/ o token region:<nome>)

  // uma entrada de escopo casa com o aluno? "region:<nome>" = igualdade com a sede do time
  // (via /contest/teams); outra coisa = regex no login (mesma semântica do staff_can_see).
  function scopeMatch(entry, login) {
    if (entry.startsWith('region:')) {
      const want = entry.slice(7).trim().toLowerCase();
      return want !== '' && ((TEAMS[login] || {}).region || '').toLowerCase() === want;
    }
    const re = safeRe(entry);
    return re ? re.test(login || '') : false;
  }

  // abre o PDF combinado numa nova aba (Bearer via blob — padrão do staff.js)
  function openPdf(id) {
    const w = window.open('', '_blank');
    if (!w) { alert('Permita pop-ups para abrir o PDF.'); return; }
    try { w.document.write('<!doctype html><meta charset="utf-8"><title>PDF</title><body style="font:16px sans-serif;padding:1rem">Gerando o PDF…</body>'); } catch (_) {}
    fetch('/api/v1/contest/staff/print-pdf?contest=' + enc(CONTEST) + '&id=' + enc(id),
      { headers: { Authorization: 'Bearer ' + (getToken(CONTEST) || '') } })
      .then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.blob(); })
      .then((b) => { const url = URL.createObjectURL(b); w.location.href = url; setTimeout(() => URL.revokeObjectURL(url), 120000); })
      .catch((e) => { try { w.document.body.innerHTML = 'Falha: ' + (e.message || 'erro'); } catch (_) {} });
  }
  async function act(id, action) {
    try { await apiPost('/contest/staff/print-action?contest=' + enc(CONTEST), { id, action }, G); await refresh(); }
    catch (e) { alert(e.message || 'falha'); }
  }

  // --- filtros da fila (estado sobrevive ao re-render) ---
  const fKind = el('select', {}, el('option', { value: '' }, 'tudo'),
    el('option', { value: 'print' }, '🖨️ impressão'), el('option', { value: 'balloon' }, '🎈 balão'));
  const fStatus = el('select', {}, el('option', { value: '' }, 'todos'),
    el('option', { value: 'pending' }, 'pendentes'), el('option', { value: 'printed' }, 'processadas'),
    el('option', { value: 'delivered' }, 'entregues'));
  const fQ = el('input', { type: 'search', placeholder: 'aluno / staff…', style: 'min-width:170px' });
  [fKind, fStatus].forEach((i) => i.addEventListener('change', render));
  fQ.addEventListener('input', render);

  const sumBox = el('div', {});
  const listBox = el('div', {});
  const perfBox = el('div', {});
  const cfgBox = el('div', {});

  const card = (label, val, warn) => el('div', { class: 'dash-card' + (warn ? ' warn' : '') },
    el('div', { class: 'dash-val' }, String(val)), el('div', { class: 'dash-lbl' }, label));

  function renderSummary() {
    sumBox.innerHTML = '';
    const pend = QUEUE.filter((t) => t.status === 'pending');
    const pendP = pend.filter((t) => t.kind !== 'balloon').length;
    const pendB = pend.filter((t) => t.kind === 'balloon').length;
    const oldest = pend.length ? Math.max(...pend.map((t) => nowE() - (t.time || nowE()))) : 0;
    const printed = QUEUE.filter((t) => t.status === 'printed').length;
    const delivered = QUEUE.filter((t) => t.status === 'delivered').length;
    sumBox.append(el('div', { class: 'dash-cards' },
      card('🖨️ impressões pendentes', pendP, pendP > 0 && oldest > 600),
      card('🎈 balões pendentes', pendB, pendB > 0 && oldest > 600),
      card('mais antiga esperando', pend.length ? fmtS(oldest) : '—', oldest > 600),
      card('processadas (não entregues)', printed, printed > 5),
      card('entregues', delivered)));
    if (oldest > 600) sumBox.append(el('div', { class: 'alert' },
      '⚠ Há tarefa pendente há ' + fmtS(oldest) + ' — o staff está dando conta? Você pode agir na fila abaixo.'));
  }

  function taskRow(t) {
    const isB = t.kind === 'balloon';
    const tipo = isB
      ? el('span', {}, '🎈 ', el('span', { style: 'display:inline-block;width:12px;height:12px;border-radius:50%;vertical-align:middle;border:1px solid #aaa;background:#' + (t.color_hex || 'ccc') }), ' ' + (t.color_name || ''))
      : el('span', {}, '🖨️');
    const item = isB ? ('problema ' + (t.short || '?')) : ((t.filename || '') + (t.pages ? ' · ' + t.pages + ' pág' : ''));
    const st = STATUS[t.status] || { t: t.status, cls: '' };
    const who = t.status === 'delivered' ? (t.delivered_by || '')
      : t.status === 'printed' ? (t.processed_by || '')
      : (t.claimed_by ? t.claimed_by + ' (pegou)' : '—');
    const age = t.status === 'pending' ? fmtS(nowE() - (t.time || nowE())) : fmtDate(t.time).slice(0, 17);
    const acts = el('div', { class: 'row', style: 'gap:.25rem' });
    if (!isB || t.status !== 'delivered') acts.append(el('button', { class: 'btn ghost', title: 'Abrir o PDF', onclick: () => openPdf(t.id) }, '📄'));
    if (t.status === 'pending') acts.append(el('button', { class: 'btn ghost', title: 'Marcar processada (impressa)', onclick: () => act(t.id, 'processed') }, '🖨️✓'));
    if (t.status === 'printed') acts.append(el('button', { class: 'btn ghost', title: 'Marcar entregue', onclick: () => act(t.id, 'delivered') }, '✅'));
    return el('tr', {},
      el('td', { class: 'small' }, '#' + (t.seq || '')),
      el('td', {}, tipo),
      el('td', {}, (t.fullname || t.login || ''), el('div', { class: 'small muted' }, (t.login || '') + (t.univ ? ' · ' + t.univ : ''))),
      el('td', { class: 'small' }, item),
      el('td', {}, el('span', { class: t.status === 'pending' ? 'flag-warn' : '' }, st.t)),
      el('td', { class: 'small' }, age),
      el('td', { class: 'small' }, who),
      el('td', {}, acts));
  }

  function render() {
    renderSummary();
    listBox.innerHTML = '';
    const q = fQ.value.trim().toLowerCase();
    const items = QUEUE.filter((t) =>
      (!fKind.value || (fKind.value === 'balloon') === (t.kind === 'balloon'))
      && (!fStatus.value || t.status === fStatus.value)
      && (!q || [t.login, t.fullname, t.claimed_by, t.processed_by, t.delivered_by].some((x) => (x || '').toLowerCase().includes(q))));
    listBox.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + ' de ' + QUEUE.length + ' tarefa(s).'));
    if (!items.length) { listBox.append(el('div', { class: 'muted' }, 'Nenhuma tarefa' + (QUEUE.length ? ' com esses filtros.' : ' ainda — pedidos de impressão e balões (1ª solução aceita) aparecem aqui.'))); }
    else {
      const tb = el('tbody'); items.forEach((t) => tb.append(taskRow(t)));
      listBox.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, '#'), el('th', {}, 'Tipo'), el('th', {}, 'Aluno/time'),
          el('th', {}, 'Item'), el('th', {}, 'Status'), el('th', {}, 'Idade/quando'), el('th', {}, 'Staff'), el('th', {}, 'Ações'))), tb)));
    }
    renderPerf();
  }

  function renderPerf() {
    perfBox.innerHTML = '';
    const staff = (SF && SF.staff) || [];
    if (!staff.length) return;
    perfBox.append(el('h3', { style: 'margin:1rem 0 .3rem' }, '📈 Desempenho por staff'));
    const tb = el('tbody');
    staff.forEach((s) => {
      const done = QUEUE.filter((t) => t.processed_by === s.login).length;
      const deliv = QUEUE.filter((t) => t.delivered_by === s.login);
      const avg = deliv.length ? Math.round(deliv.reduce((a, t) => a + Math.max(0, (t.delivered_at || 0) - (t.time || 0)), 0) / deliv.length) : 0;
      // backlog no ESCOPO desse staff (mesma semântica de staff_can_see: lista vazia = tudo;
      // entrada region:<nome> casa com a sede do time, o resto é regex no login)
      const scope = ((SF.filters || {})[s.login] || []).filter(Boolean);
      const backlog = QUEUE.filter((t) => t.status === 'pending' && (!scope.length || scope.some((en) => scopeMatch(en, t.login || '')))).length;
      tb.append(el('tr', {},
        el('td', {}, s.login, s.disabled ? el('span', { class: 'flag-anom small' }, ' (desabilitado)') : ''),
        el('td', {}, String(backlog)), el('td', {}, String(done)), el('td', {}, String(deliv.length)),
        el('td', { class: 'small' }, deliv.length ? ('~' + fmtS(avg)) : '—')));
    });
    perfBox.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Staff'), el('th', {}, 'Pend. no escopo'), el('th', {}, 'Processadas'),
        el('th', {}, 'Entregues'), el('th', {}, 'Tempo médio até entregar'))), tb)),
      el('p', { class: 'muted small' }, 'Escopo vazio = o staff vê todas as tarefas. Configure abaixo.'));
  }

  // --- config de escopo por regex (antiga aba "Impressão") ---
  function renderConfig() {
    cfgBox.innerHTML = '';
    cfgBox.append(el('h3', { style: 'margin:1.2rem 0 .3rem' }, '⚙️ Escopo dos staffs/chefes de sede'));
    const staff = (SF && SF.staff) || [], regions = (SF && SF.regions) || [], filters = (SF && SF.filters) || {};
    if (!staff.length) {
      cfgBox.append(el('div', { class: 'muted' }, 'Nenhum usuário .staff/.cstaff neste contest. Crie um login terminando em ',
        el('b', {}, '.staff'), ' (fila de impressão/balões) ou ', el('b', {}, '.cstaff'),
        ' (chefe de sede: etiquetas com senha, fila em leitura, cerimônia da sede) na aba Usuários.'));
      return;
    }
    cfgBox.append(el('p', { class: 'muted small' }, 'Cada login vê os alunos que casam com uma das entradas (uma por linha): ',
      el('code', {}, 'region:<nome>'), ' casa com a sede do time (aba Times), qualquer outra é regex no login. Lista vazia = vê TODOS. ',
      'No .staff o escopo governa a fila/ações; no .cstaff governa a fila (leitura), as ETIQUETAS de credenciais e a CERIMÔNIA de revelação da sede — configure-o sempre. Os botões de região semeiam ',
      el('code', {}, 'region:<nome>'), '.'));
    const blocks = {};
    staff.forEach((s) => {
      const ta = el('textarea', { rows: '3', style: 'width:100%; font-family:monospace' });
      ta.value = (filters[s.login] || []).join('\n');
      blocks[s.login] = ta;
      const chips = el('div', { class: 'row', style: 'flex-wrap:wrap; gap:.3rem; margin:.3rem 0' });
      regions.forEach((rg) => { if (!rg || (!rg.name && !rg.regex)) return;
        // com nome, semeia o token region:<nome> (legível, casa com a sede do time);
        // região sem nome cai no regex clássico
        const entry = rg.name ? ('region:' + rg.name) : rg.regex;
        chips.append(el('button', { class: 'btn ghost', style: 'padding:.1rem .45rem', type: 'button',
          onclick: () => { const cur = ta.value.trim(); const lines = cur ? cur.split(/\n+/) : [];
            if (!lines.includes(entry)) { lines.push(entry); ta.value = lines.join('\n'); } } },
          '+ ' + (rg.name || rg.regex))); });
      cfgBox.append(el('div', { class: 'field', style: 'border-top:1px solid var(--line); padding-top:.5rem' },
        el('label', {}, el('b', {}, s.login), (s.fullname ? el('span', { class: 'small muted' }, ' — ' + s.fullname) : ''),
          (s.disabled ? el('span', { class: 'small', style: 'margin-left:.4rem; color:#a00' }, '(desabilitado)') : '')),
        (regions.length ? el('div', { class: 'small muted' }, 'Semear região:') : ''), (regions.length ? chips : ''),
        ta));
    });
    const msg = el('div', { class: 'small' });
    const save = el('button', { class: 'btn' }, 'Salvar escopos');
    save.addEventListener('click', async () => {
      save.disabled = true; msg.className = 'small'; msg.textContent = 'Salvando…';
      const f = {};
      Object.keys(blocks).forEach((login) => { const lines = blocks[login].value.split(/\n+/).map((x) => x.trim()).filter(Boolean); if (lines.length) f[login] = lines; });
      try { await apiPost('/contest/admin/staff-filters?contest=' + enc(CONTEST), { filters: f }, G); msg.className = 'small'; msg.textContent = '✓ salvo'; save.disabled = false; refresh(); }
      catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || 'falha'; }
    });
    cfgBox.append(el('div', { class: 'row', style: 'margin-top:.7rem' }, save, msg));
  }

  async function refresh() {
    let q, sf;
    try {
      let tm;
      [q, sf, tm] = await Promise.all([
        apiGet('/contest/staff/queue?contest=' + enc(CONTEST), G),
        apiGet('/contest/admin/staff-filters?contest=' + enc(CONTEST), G).catch(() => null),
        apiGet('/contest/teams?contest=' + enc(CONTEST), G).catch(() => null),
      ]);
      if (tm && tm.teams) TEAMS = tm.teams;
    } catch (e) {
      listBox.innerHTML = ''; listBox.append(el('div', { class: 'error-box' }, 'Falha: ' + (e.message || 'erro')));
      return;
    }
    QUEUE = (q && q.requests) || [];
    if (sf) SF = sf;
    render(); renderConfig();
  }

  async function load() {
    panel.innerHTML = '';
    const dl = el('button', { class: 'btn ghost', title: 'Baixar a fila (CSV)', onclick: () => {
      const rows = [['seq', 'tipo', 'login', 'nome', 'univ', 'item', 'status', 'criada_em', 'claimed_by', 'processed_by', 'delivered_by', 'delivered_at'],
        ...QUEUE.map((t) => [t.seq, t.kind || 'print', t.login || '', t.fullname || '', t.univ || '',
          t.kind === 'balloon' ? (t.short || '') : (t.filename || ''), t.status,
          new Date((t.time || 0) * 1000).toISOString(), t.claimed_by || '', t.processed_by || '', t.delivered_by || '',
          t.delivered_at ? new Date(t.delivered_at * 1000).toISOString() : ''])];
      downloadText('tarefas-' + CONTEST + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    panel.append(el('div', { class: 'section' },
      el('h2', {}, '🖨️ Tarefas do staff'),
      el('p', { class: 'muted small' }, 'Impressões pedidas pelos alunos e balões (1ª solução aceita de cada time/problema). O admin acompanha e pode agir — abrir o PDF, marcar processada/entregue — quando um staff não der conta.'),
      sumBox,
      el('div', { class: 'row', style: 'margin:.4rem 0' },
        el('span', { class: 'small muted' }, 'Filtrar:'), fKind, fStatus, fQ,
        el('button', { class: 'btn ghost', onclick: () => refresh() }, '↻'), dl),
      listBox, perfBox, cfgBox));
    await refresh();
    clearInterval(timer); timer = setInterval(() => { if (!panel.hidden) refresh(); }, 20000);
  }
  return { panel, load };
}
