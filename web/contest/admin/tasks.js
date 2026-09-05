// contest/admin/tasks.js — aba "🖨️ Staff" do admin: panorama e AÇÃO sobre a fila de impressão +
// balões (GET /contest/staff/queue — o admin vê TUDO e o load já reconcilia os balões
// pendentes), desempenho por staff e a config de escopo por regex (staff-filters).
// Auto-refresh ≥15s e pausado com o painel oculto (o reconcile de balões roda a cada load da
// fila — não martelar).
//
// ATUALIZAÇÃO EM LUGAR (regra da casa): o esqueleto nasce uma vez; a fila e o resumo trocam só
// quando a assinatura muda; a config de escopo NUNCA é refeita com um textarea sujo ou focado
// (até 05/09 o tick de 20 s apagava o que o admin estava digitando).
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { fmtDate, fmtS, toCsv, downloadText, swapIf, sigOf, everyVisible } from '/shared/admin-ui.js';

const enc = encodeURIComponent;
const nowE = () => Math.floor(Date.now() / 1000);
// fábrica, não const de módulo: T() no topo congelaria o idioma antes do LOCALE do contest
const STATUS = () => ({
  pending: { t: T('🕓 pendente', '🕓 pending'), cls: 'flag-warn' },
  printed: { t: T('🖨️ processada', '🖨️ processed'), cls: '' },
  delivered: { t: T('✅ entregue', '✅ delivered'), cls: '' },
});
const safeRe = (rx) => { try { return new RegExp(rx, 'i'); } catch { return null; } };

export function makeTasksTab(CONTEST, opts = {}) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', {});
  let stopTimer = null;
  let QUEUE = [];        // fila completa (admin)
  let SF = null;         // {staff:[{login,...}], regions:[], filters:{login:[entradas]}}
  let TEAMS = {};        // login -> {region,...} (/contest/teams — p/ o token region:<nome>)
  // has(mod): o shell diz quais módulos estão ligados (balões e sedes mudam o que se mostra)
  const has = typeof opts.has === 'function' ? opts.has : () => true;

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

  // --- filtros da fila (nós persistentes: sobrevivem a todo tick) ---
  const optBalloon = el('option', { value: 'balloon' }, T('🎈 balão', '🎈 balloon'));
  const fKind = el('select', {}, el('option', { value: '' }, T('tudo', 'all')),
    el('option', { value: 'print' }, T('🖨️ impressão', '🖨️ print')), optBalloon);
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
  const errBox = el('div', {});

  const card = (label, val, warn) => el('div', { class: 'dash-card' + (warn ? ' warn' : '') },
    el('div', { class: 'dash-val' }, String(val)), el('div', { class: 'dash-lbl' }, label));

  function buildSummary() {
    const box = el('div', {});
    const pend = QUEUE.filter((t) => t.status === 'pending');
    const pendP = pend.filter((t) => t.kind !== 'balloon').length;
    const pendB = pend.filter((t) => t.kind === 'balloon').length;
    const oldest = pend.length ? Math.max(...pend.map((t) => nowE() - (t.time || nowE()))) : 0;
    const printed = QUEUE.filter((t) => t.status === 'printed').length;
    const delivered = QUEUE.filter((t) => t.status === 'delivered').length;
    box.append(el('div', { class: 'dash-cards' },
      card(T('🖨️ impressões pendentes', '🖨️ pending prints'), pendP, pendP > 0 && oldest > 600),
      ...(has('baloes') ? [card(T('🎈 balões pendentes', '🎈 pending balloons'), pendB, pendB > 0 && oldest > 600)] : []),
      card(T('mais antiga esperando', 'oldest waiting'), pend.length ? fmtS(oldest) : '—', oldest > 600),
      card(T('processadas (não entregues)', 'processed (not delivered)'), printed, printed > 5),
      card(T('entregues', 'delivered'), delivered)));
    if (oldest > 600) box.append(el('div', { class: 'alert' },
      T('⚠ Há tarefa pendente há ', '⚠ There is a task pending for ') + fmtS(oldest) + T(' — o staff está dando conta? Você pode agir na fila abaixo.', ' — is the staff keeping up? You can act on the queue below.')));
    return box;
  }

  function taskRow(t) {
    const isB = t.kind === 'balloon';
    const tipo = isB
      ? el('span', {}, '🎈 ', el('span', { style: 'display:inline-block;width:12px;height:12px;border-radius:50%;vertical-align:middle;border:1px solid #aaa;background:#' + (t.color_hex || 'ccc') }))
      : el('span', {}, '🖨️');
    const item = isB ? (T('problema ', 'problem ') + (t.short || '?')) : ((t.filename || '') + (t.pages ? ' · ' + t.pages + T(' pág', ' pg') : ''));
    const st = STATUS()[t.status] || { t: t.status, cls: '' };
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

  function buildList() {
    const box = el('div', {});
    const q = fQ.value.trim().toLowerCase();
    const items = QUEUE.filter((t) =>
      (!fKind.value || (fKind.value === 'balloon') === (t.kind === 'balloon'))
      && (!fStatus.value || t.status === fStatus.value)
      && (!q || [t.login, t.fullname, t.claimed_by, t.processed_by, t.delivered_by].some((x) => (x || '').toLowerCase().includes(q))));
    box.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' de ', ' of ') + QUEUE.length + T(' tarefa(s).', ' task(s).')));
    if (!items.length) { box.append(el('div', { class: 'muted' }, T('Nenhuma tarefa', 'No task') + (QUEUE.length ? T(' com esses filtros.', ' with these filters.') : T(' ainda — pedidos de impressão e balões aparecem aqui.', ' yet — print requests and balloons appear here.')))); return box; }
    const tb = el('tbody'); items.forEach((t) => tb.append(taskRow(t)));
    box.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, '#'), el('th', {}, T('Tipo', 'Type')), el('th', {}, T('Aluno/time', 'Student/team')),
        el('th', {}, 'Item'), el('th', {}, 'Status'), el('th', {}, T('Idade/quando', 'Age/when')), el('th', {}, 'Staff'), el('th', {}, T('Ações', 'Actions')))), tb)));
    return box;
  }

  function buildPerf() {
    const staff = (SF && SF.staff) || [];
    if (!staff.length) return null;
    const box = el('div', {}, el('h3', { style: 'margin:1rem 0 .3rem' }, T('📈 Desempenho por staff', '📈 Performance by staff')));
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
    box.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'Staff'), el('th', {}, T('Pend. no escopo', 'Pending in scope')), el('th', {}, T('Processadas', 'Processed')),
        el('th', {}, T('Entregues', 'Delivered')), el('th', {}, T('Tempo médio até entregar', 'Avg time to deliver')))), tb)),
      el('p', { class: 'muted small' }, T('Escopo vazio = o staff vê todas as tarefas. Configure abaixo.', 'Empty scope = the staff sees all tasks. Configure below.')));
    return box;
  }

  // a fila: a idade "Xs" das pendentes muda com o relógio — a assinatura leva o minuto
  function render() {
    swapIf(sumBox, sigOf(QUEUE.map((t) => [t.status, t.kind, t.time]), Math.floor(nowE() / 30), has('baloes')), buildSummary);
    swapIf(listBox, sigOf(QUEUE, fKind.value, fStatus.value, fQ.value, Math.floor(nowE() / 30)), buildList);
    swapIf(perfBox, sigOf(SF && SF.staff, SF && SF.filters, QUEUE.map((t) => [t.status, t.processed_by, t.delivered_by, t.delivered_at, t.time, t.login]), TEAMS), buildPerf);
  }

  // --- config de escopo por regex (antiga aba "Impressão") ---
  // Só é REFEITA quando o dado do servidor mudou E nenhum textarea está sujo/focado — o
  // que o admin digita nunca é apagado por um tick.
  let blocks = {};
  function cfgDirty() {
    if (cfgBox.contains(document.activeElement)) return true;
    return Object.values(blocks).some((ta) => ta.value !== (ta.dataset.orig || ''));
  }
  function buildConfig() {
    const box = el('div', {});
    box.append(el('h3', { style: 'margin:1.2rem 0 .3rem' }, T('⚙️ Escopo dos staffs/chefes de sede', '⚙️ Scope of staff/site chiefs')));
    const staff = (SF && SF.staff) || [], regions = (SF && SF.regions) || [], filters = (SF && SF.filters) || {};
    blocks = {};
    if (!staff.length) {
      box.append(el('div', { class: 'muted' }, T('Nenhum usuário .staff/.cstaff neste contest. Crie um login terminando em ', 'No .staff/.cstaff user in this contest. Create a login ending in '),
        el('b', {}, '.staff'), T(' (fila de impressão/balões) ou ', ' (print/balloon queue) or '), el('b', {}, '.cstaff'),
        T(' (chefe de sede: etiquetas com senha, fila em leitura, cerimônia da sede) em Pessoas › Contas.', ' (site chief: badges with password, read-only queue, site ceremony) in People › Accounts.')));
      return box;
    }
    box.append(el('p', { class: 'muted small' }, T('Cada login vê os alunos que casam com uma das entradas (uma por linha): ', 'Each login sees the students matching one of the entries (one per line): '),
      el('code', {}, T('region:<nome>', 'region:<name>')), T(' casa com a sede do time (Evento › Times), qualquer outra é regex no login. Lista vazia = vê TODOS. ', ' matches the team\'s site (Event › Teams), anything else is a regex on the login. Empty list = sees ALL. '),
      T('No .staff o escopo governa a fila/ações; no .cstaff governa a fila (leitura), as ETIQUETAS de credenciais e a CERIMÔNIA de revelação da sede — configure-o sempre. Os botões de sede semeiam ', 'For .staff the scope governs the queue/actions; for .cstaff it governs the queue (read-only), the credential BADGES and the site REVEAL ceremony — always configure it. The site buttons seed '),
      el('code', {}, T('region:<nome>', 'region:<name>')), '.'));
    staff.forEach((s) => {
      const ta = el('textarea', { rows: '3', style: 'width:100%; font-family:monospace' });
      ta.value = (filters[s.login] || []).join('\n'); ta.dataset.orig = ta.value;
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
      box.append(el('div', { class: 'field', style: 'border-top:1px solid var(--line); padding-top:.5rem' },
        el('label', {}, el('b', {}, s.login), (s.fullname ? el('span', { class: 'small muted' }, ' — ' + s.fullname) : ''),
          (s.disabled ? el('span', { class: 'small', style: 'margin-left:.4rem; color:#a00' }, T('(desabilitado)', '(disabled)')) : '')),
        (regions.length && has('sedes') ? el('div', { class: 'small muted' }, T('Semear região:', 'Seed region:')) : ''), (regions.length && has('sedes') ? chips : ''),
        ta));
    });
    const msg = el('div', { class: 'small' });
    const save = el('button', { class: 'btn' }, T('Salvar escopos', 'Save scopes'));
    save.addEventListener('click', async () => {
      save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
      const f = {};
      Object.keys(blocks).forEach((login) => { const lines = blocks[login].value.split(/\n+/).map((x) => x.trim()).filter(Boolean); if (lines.length) f[login] = lines; });
      try {
        await apiPost('/contest/admin/staff-filters?contest=' + enc(CONTEST), { filters: f }, G);
        Object.values(blocks).forEach((ta) => { ta.dataset.orig = ta.value; });   // salvo = limpo
        msg.className = 'small'; msg.textContent = T('✓ salvo', '✓ saved'); save.disabled = false; await refresh();
      } catch (e) { save.disabled = false; msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    });
    box.append(el('div', { class: 'row', style: 'margin-top:.7rem' }, save, msg));
    return box;
  }
  function renderConfig() {
    const sig = sigOf(SF && SF.staff, SF && SF.regions, SF && SF.filters, has('sedes'));
    if (cfgBox.dataset.sig === sig) return;
    if (cfgBox.dataset.sig && cfgDirty()) return;   // admin digitando: adia p/ o próximo tick
    swapIf(cfgBox, sig, buildConfig);
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
      errBox.innerHTML = ''; errBox.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error'))));
      return;
    }
    errBox.innerHTML = '';
    QUEUE = (q && q.requests) || [];
    if (sf) SF = sf;
    render(); renderConfig();
  }

  let built = false;
  function skeleton() {
    const dl = el('button', { class: 'btn ghost', title: T('Baixar a fila (CSV)', 'Download the queue (CSV)'), onclick: () => {
      const rows = [[T('seq', 'seq'), T('tipo', 'kind'), 'login', T('nome', 'name'), T('univ', 'univ'), T('item', 'item'), 'status', T('criada_em', 'created_at'), 'claimed_by', 'processed_by', 'delivered_by', 'delivered_at'],
        ...QUEUE.map((t) => [t.seq, t.kind || 'print', t.login || '', t.fullname || '', t.univ || '',
          t.kind === 'balloon' ? (t.short || '') : (t.filename || ''), t.status,
          new Date((t.time || 0) * 1000).toISOString(), t.claimed_by || '', t.processed_by || '', t.delivered_by || '',
          t.delivered_at ? new Date(t.delivered_at * 1000).toISOString() : ''])];
      downloadText('tarefas-' + CONTEST + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    panel.innerHTML = '';
    panel.append(el('div', { class: 'section' },
      el('h2', {}, T('🖨️ Staff — fila e escopo', '🖨️ Staff — queue and scope')),
      el('p', { class: 'muted small' }, T('Impressões pedidas pelos alunos e balões (1ª solução aceita de cada time/problema). O admin acompanha e pode agir — abrir o PDF, marcar processada, marcar entregue.', 'Print requests from students and balloons (first accepted solution per team/problem). The admin follows and can act — open the PDF, mark processed, mark delivered.')),
      errBox, sumBox,
      el('div', { class: 'row', style: 'margin:.4rem 0' },
        el('span', { class: 'small muted' }, T('Filtrar:', 'Filter:')), fKind, fStatus, fQ,
        el('button', { class: 'btn ghost', onclick: () => refresh() }, '↻'), dl),
      listBox, perfBox, cfgBox));
    built = true;
  }

  async function load() {
    if (!built) skeleton();
    optBalloon.hidden = !has('baloes');   // sem o módulo balões o filtro nem oferece o tipo
    await refresh();
    if (stopTimer) stopTimer();
    stopTimer = everyVisible(panel, 20000, refresh);
  }
  return { panel, load };
}
