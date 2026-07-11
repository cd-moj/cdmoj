// contest/admin/tasks.js — aba "🖨️ Tarefas do staff" do admin: panorama e AÇÃO sobre a fila
// de impressão + balões (GET /contest/staff/queue — o admin vê TUDO e o load já reconcilia os
// balões pendentes), desempenho por staff e a config de escopo por regex (staff-filters).
// Auto-refresh ≥15s e pausado com o painel oculto (o reconcile de balões roda a cada load da
// fila — não martelar).
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const fmtDate = (e) => new Date((+e || 0) * 1000).toLocaleString('pt-BR');
const fmtS = (s) => { s = Math.max(0, Math.round(+s || 0)); if (s < 60) return s + 's'; const m = Math.floor(s / 60); return m < 60 ? m + 'min' : Math.floor(m / 60) + 'h' + (m % 60 ? (m % 60) + 'min' : ''); };
const nowE = () => Math.floor(Date.now() / 1000);
const STATUS = {
  pending: { t: T('🕓 pendente', '🕓 pending'), cls: 'flag-warn' },
  printed: { t: T('🖨️ processada', '🖨️ processed'), cls: '' },
  delivered: { t: T('✅ entregue', '✅ delivered'), cls: '' },
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
    if (!w) { alert(T('Permita pop-ups para abrir o PDF.', 'Please allow pop-ups to open the PDF.')); return; }
    try { w.document.write('<!doctype html><meta charset="utf-8"><title>PDF</title><body style="font:16px sans-serif;padding:1rem">' + T('Gerando o PDF…', 'Generating the PDF…') + '</body>'); } catch (_) {}
    fetch('/api/v1/contest/staff/print-pdf?contest=' + enc(CONTEST) + '&id=' + enc(id),
      { headers: { Authorization: 'Bearer ' + (getToken(CONTEST) || '') } })
      .then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.blob(); })
      .then((b) => { const url = URL.createObjectURL(b); w.location.href = url; setTimeout(() => URL.revokeObjectURL(url), 120000); })
      .catch((e) => { try { w.document.body.innerHTML = T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')); } catch (_) {} });
  }
  async function act(id, action) {
    try { await apiPost('/contest/staff/print-action?contest=' + enc(CONTEST), { id, action }, G); await refresh(); }
    catch (e) { alert(e.message || T('falha', 'failed')); }
  }

  // --- filtros da fila (estado sobrevive ao re-render) ---
  const fKind = el('select', {}, el('option', { value: '' }, T('tudo', 'all')),
    el('option', { value: 'print' }, T('🖨️ impressão', '🖨️ print')), el('option', { value: 'balloon' }, T('🎈 balão', '🎈 balloon')));
  const fStatus = el('select', {}, el('option', { value: '' }, T('todos', 'all')),
    el('option', { value: 'pending' }, T('pendentes', 'pending')), el('option', { value: 'printed' }, T('processadas', 'processed')),
    el('option', { value: 'delivered' }, T('entregues', 'delivered')));
  const fQ = el('input', { type: 'search', placeholder: T('aluno / staff…', 'student / staff…'), style: 'min-width:170px' });
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
      card(T('🖨️ impressões pendentes', '🖨️ pending prints'), pendP, pendP > 0 && oldest > 600),
      card(T('🎈 balões pendentes', '🎈 pending balloons'), pendB, pendB > 0 && oldest > 600),
      card(T('mais antiga esperando', 'oldest waiting'), pend.length ? fmtS(oldest) : '—', oldest > 600),
      card(T('processadas (não entregues)', 'processed (not delivered)'), printed, printed > 5),
      card(T('entregues', 'delivered'), delivered)));
    if (oldest > 600) sumBox.append(el('div', { class: 'alert' },
      T('⚠ Há tarefa pendente há ', '⚠ There is a task pending for ') + fmtS(oldest) + T(' — o staff está dando conta? Você pode agir na fila abaixo.', ' — is the staff keeping up? You can act on the queue below.')));
  }

  function taskRow(t) {
    const isB = t.kind === 'balloon';
    const tipo = isB
      ? el('span', {}, '🎈 ', el('span', { style: 'display:inline-block;width:12px;height:12px;border-radius:50%;vertical-align:middle;border:1px solid #aaa;background:#' + (t.color_hex || 'ccc') }), ' ' + (t.color_name || ''))
      : el('span', {}, '🖨️');
    const item = isB ? (T('problema ', 'problem ') + (t.short || '?')) : ((t.filename || '') + (t.pages ? ' · ' + t.pages + T(' pág', ' pg') : ''));
    const st = STATUS[t.status] || { t: t.status, cls: '' };
    const who = t.status === 'delivered' ? (t.delivered_by || '')
      : t.status === 'printed' ? (t.processed_by || '')
      : (t.claimed_by ? t.claimed_by + T(' (pegou)', ' (claimed)') : '—');
    const age = t.status === 'pending' ? fmtS(nowE() - (t.time || nowE())) : fmtDate(t.time).slice(0, 17);
    const acts = el('div', { class: 'row', style: 'gap:.25rem' });
    if (!isB || t.status !== 'delivered') acts.append(el('button', { class: 'btn ghost', title: T('Abrir o PDF', 'Open the PDF'), onclick: () => openPdf(t.id) }, '📄'));
    if (t.status === 'pending') acts.append(el('button', { class: 'btn ghost', title: T('Marcar processada (impressa)', 'Mark processed (printed)'), onclick: () => act(t.id, 'processed') }, '🖨️✓'));
    if (t.status === 'printed') acts.append(el('button', { class: 'btn ghost', title: T('Marcar entregue', 'Mark delivered'), onclick: () => act(t.id, 'delivered') }, '✅'));
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
    listBox.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' de ', ' of ') + QUEUE.length + T(' tarefa(s).', ' task(s).')));
    if (!items.length) { listBox.append(el('div', { class: 'muted' }, T('Nenhuma tarefa', 'No task') + (QUEUE.length ? T(' com esses filtros.', ' with these filters.') : T(' ainda — pedidos de impressão e balões (1ª solução aceita) aparecem aqui.', ' yet — print requests and balloons (1st accepted solution) show up here.')))); }
    else {
      const tb = el('tbody'); items.forEach((t) => tb.append(taskRow(t)));
      listBox.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, '#'), el('th', {}, T('Tipo', 'Type')), el('th', {}, T('Aluno/time', 'Student/team')),
          el('th', {}, 'Item'), el('th', {}, 'Status'), el('th', {}, T('Idade/quando', 'Age/when')), el('th', {}, 'Staff'), el('th', {}, T('Ações', 'Actions')))), tb)));
    }
    renderPerf();
  }

  function renderPerf() {
    perfBox.innerHTML = '';
    const staff = (SF && SF.staff) || [];
    if (!staff.length) return;
    perfBox.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('📈 Desempenho por staff', '📈 Performance by staff')));
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
        el('td', {}, s.login, s.disabled ? el('span', { class: 'flag-anom small' }, T(' (desabilitado)', ' (disabled)')) : ''),
        el('td', {}, String(backlog)), el('td', {}, String(done)), el('td', {}, String(deliv.length)),
        el('td', { class: 'small' }, deliv.length ? ('~' + fmtS(avg)) : '—')));
    });
    perfBox.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Staff'), el('th', {}, T('Pend. no escopo', 'Pending in scope')), el('th', {}, T('Processadas', 'Processed')),
        el('th', {}, T('Entregues', 'Delivered')), el('th', {}, T('Tempo médio até entregar', 'Avg time to deliver')))), tb)),
      el('p', { class: 'muted small' }, T('Escopo vazio = o staff vê todas as tarefas. Configure abaixo.', 'Empty scope = the staff sees all tasks. Configure below.')));
  }

  // --- config de escopo por regex (antiga aba "Impressão") ---
  function renderConfig() {
    cfgBox.innerHTML = '';
    cfgBox.append(el('h3', { style: 'margin:1.2rem 0 .3rem' }, T('⚙️ Escopo dos staffs/chefes de sede', '⚙️ Scope of staff/site chiefs')));
    const staff = (SF && SF.staff) || [], regions = (SF && SF.regions) || [], filters = (SF && SF.filters) || {};
    if (!staff.length) {
      cfgBox.append(el('div', { class: 'muted' }, T('Nenhum usuário .staff/.cstaff neste contest. Crie um login terminando em ', 'No .staff/.cstaff user in this contest. Create a login ending in '),
        el('b', {}, '.staff'), T(' (fila de impressão/balões) ou ', ' (print/balloon queue) or '), el('b', {}, '.cstaff'),
        T(' (chefe de sede: etiquetas com senha, fila em leitura, cerimônia da sede) na aba Usuários.', ' (site chief: badges with password, read-only queue, site ceremony) in the Users tab.')));
      return;
    }
    cfgBox.append(el('p', { class: 'muted small' }, T('Cada login vê os alunos que casam com uma das entradas (uma por linha): ', 'Each login sees the students matching one of the entries (one per line): '),
      el('code', {}, T('region:<nome>', 'region:<name>')), T(' casa com a sede do time (aba Times), qualquer outra é regex no login. Lista vazia = vê TODOS. ', ' matches the team\'s site (Teams tab), anything else is a regex on the login. Empty list = sees ALL. '),
      T('No .staff o escopo governa a fila/ações; no .cstaff governa a fila (leitura), as ETIQUETAS de credenciais e a CERIMÔNIA de revelação da sede — configure-o sempre. Os botões de região semeiam ', 'On .staff the scope governs the queue/actions; on .cstaff it governs the queue (read-only), the credential BADGES and the site reveal CEREMONY — always configure it. The region buttons seed '),
      el('code', {}, T('region:<nome>', 'region:<name>')), '.'));
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
        (regions.length ? el('div', { class: 'small muted' }, T('Semear região:', 'Seed region:')) : ''), (regions.length ? chips : ''),
        ta));
    });
    const msg = el('div', { class: 'small' });
    const save = el('button', { class: 'btn' }, T('Salvar escopos', 'Save scopes'));
    save.addEventListener('click', async () => {
      save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
      const f = {};
      Object.keys(blocks).forEach((login) => { const lines = blocks[login].value.split(/\n+/).map((x) => x.trim()).filter(Boolean); if (lines.length) f[login] = lines; });
      try { await apiPost('/contest/admin/staff-filters?contest=' + enc(CONTEST), { filters: f }, G); msg.className = 'small'; msg.textContent = T('✓ salvo', '✓ saved'); save.disabled = false; refresh(); }
      catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
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
      listBox.innerHTML = ''; listBox.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error'))));
      return;
    }
    QUEUE = (q && q.requests) || [];
    if (sf) SF = sf;
    render(); renderConfig();
  }

  async function load() {
    panel.innerHTML = '';
    const dl = el('button', { class: 'btn ghost', title: T('Baixar a fila (CSV)', 'Download the queue (CSV)'), onclick: () => {
      const rows = [['seq', 'tipo', 'login', 'nome', 'univ', 'item', 'status', 'criada_em', 'claimed_by', 'processed_by', 'delivered_by', 'delivered_at'],
        ...QUEUE.map((t) => [t.seq, t.kind || 'print', t.login || '', t.fullname || '', t.univ || '',
          t.kind === 'balloon' ? (t.short || '') : (t.filename || ''), t.status,
          new Date((t.time || 0) * 1000).toISOString(), t.claimed_by || '', t.processed_by || '', t.delivered_by || '',
          t.delivered_at ? new Date(t.delivered_at * 1000).toISOString() : ''])];
      downloadText('tarefas-' + CONTEST + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    panel.append(el('div', { class: 'section' },
      el('h2', {}, T('🖨️ Tarefas do staff', '🖨️ Staff tasks')),
      el('p', { class: 'muted small' }, T('Impressões pedidas pelos alunos e balões (1ª solução aceita de cada time/problema). O admin acompanha e pode agir — abrir o PDF, marcar processada/entregue — quando um staff não der conta.', 'Prints requested by students and balloons (1st accepted solution of each team/problem). The admin follows along and can act — open the PDF, mark processed/delivered — when a staff can\'t keep up.')),
      sumBox,
      el('div', { class: 'row', style: 'margin:.4rem 0' },
        el('span', { class: 'small muted' }, T('Filtrar:', 'Filter:')), fKind, fStatus, fQ,
        el('button', { class: 'btn ghost', onclick: () => refresh() }, '↻'), dl),
      listBox, perfBox, cfgBox));
    await refresh();
    clearInterval(timer); timer = setInterval(() => { if (!panel.hidden) refresh(); }, 20000);
  }
  return { panel, load };
}
