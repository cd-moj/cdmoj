// contest/admin/audit-tab.js — "Operação › Auditoria": o feed unificado (ações de admin, logins,
// submissões, veredictos) com filtros e CSV, e os BACKUPS que os usuários subiram (por usuário,
// com ZIP). São as duas coisas que se pede depois da prova quando alguém contesta algo.
import { el } from '/shared/ui.js';
import { apiGet } from '/shared/api.js';
import { fmtDate, stamp, toCsv, downloadText, downloadAuthed } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

export function makeAuditTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', {});
  // rótulo por tipo: fábrica preguiçosa — chamar T() no topo do módulo congelaria o idioma antes
  // de initContestShell aplicar o LOCALE do contest.
  const KIND = () => ({ admin: '🛠️ admin', login: '🔑 login', submit: T('📤 submissão', '📤 submission'), verdict: T('⚖️ veredicto', '⚖️ verdict') });

  function auditSection() {
    const box = el('div', { class: 'section' }, el('h2', {}, T('🧾 Auditoria do contest', '🧾 Contest audit')));
    const fUser = el('input', { type: 'search', placeholder: T('usuário…', 'user…'), style: 'width:140px' });
    const fAction = el('input', { type: 'search', placeholder: T('ação/veredicto…', 'action/verdict…'), style: 'width:170px' });
    const fSince = el('input', { type: 'date' });
    const body = el('div', {});
    let lastEvents = [];
    const dl = el('button', { class: 'btn ghost', title: T('Baixar (CSV) para auditoria externa', 'Download (CSV) for external audit'), onclick: () => {
      const rows = [['epoch', 'datahora', 'tipo', 'quem', 'acao', 'detalhes'],
        ...lastEvents.map((x) => [x.time, new Date(x.time * 1000).toISOString(), x.kind, x.who || '', x.action || '', x.details || ''])];
      downloadText('auditoria-' + CONTEST + '-' + stamp() + '.csv', toCsv(rows), 'text/csv');
    } }, '⬇ CSV');
    async function run() {
      body.innerHTML = '';
      const qp = new URLSearchParams();
      if (fUser.value.trim()) qp.set('user', fUser.value.trim());
      if (fAction.value.trim()) qp.set('action', fAction.value.trim());
      if (fSince.value) { const e = Math.floor(new Date(fSince.value + 'T00:00:00').getTime() / 1000); if (e) qp.set('since', String(e)); }
      let r;
      try { r = await apiGet('/contest/admin/audit-log?contest=' + enc(CONTEST) + (qp.toString() ? '&' + qp.toString() : ''), G); }
      catch (e) { body.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }
      const ev = r.events || []; lastEvents = ev;
      const kind = KIND();
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, ev.length + T(' evento(s).', ' event(s).')));
      if (!ev.length) { body.append(el('div', { class: 'muted' }, T('Nada encontrado.', 'Nothing found.'))); return; }
      const tb = el('tbody');
      ev.forEach((x) => tb.append(el('tr', { class: 'audit-' + x.kind },
        el('td', { class: 'small' }, fmtDate(x.time)),
        el('td', { class: 'small' }, kind[x.kind] || x.kind),
        el('td', {}, x.who || ''),
        el('td', {}, x.action || ''),
        el('td', { class: 'small', style: 'font-family:var(--mono)' }, x.details || ''))));
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Quando', 'When')), el('th', {}, T('Tipo', 'Type')), el('th', {}, T('Quem', 'Who')), el('th', {}, T('Ação', 'Action')), el('th', {}, T('Detalhes', 'Details')))), tb)));
    }
    [fUser, fAction, fSince].forEach((i) => i.addEventListener('change', run));
    box.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' },
      el('span', { class: 'small muted' }, T('Filtros:', 'Filters:')), fUser, fAction, el('span', { class: 'small muted' }, T('desde', 'since')), fSince,
      el('button', { class: 'btn ghost', onclick: run }, '↻'), dl), body);
    return { box, run };
  }

  function backupsSection() {
    const box = el('div', { class: 'section' }, el('h2', {}, T('💾 Backups dos usuários', '💾 User backups')));
    const fUser = el('input', { type: 'search', placeholder: T('usuário…', 'user…'), style: 'width:140px' });
    const fQ = el('input', { type: 'search', placeholder: T('nome do arquivo…', 'file name…'), style: 'width:160px' });
    const body = el('div', {});
    async function run() {
      body.innerHTML = '';
      const qp = new URLSearchParams();
      if (fUser.value.trim()) qp.set('user', fUser.value.trim());
      if (fQ.value.trim()) qp.set('q', fQ.value.trim());
      let r;
      try { r = await apiGet('/contest/admin/backups?contest=' + enc(CONTEST) + (qp.toString() ? '&' + qp.toString() : ''), G); }
      catch (e) { body.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ') + (e.message || T('erro', 'error')))); return; }
      const users = r.users || [];
      if (users.length) {
        const ub = el('div', { class: 'row', style: 'flex-wrap:wrap; gap:.5rem; margin:.3rem 0 .6rem' });
        users.forEach((u) => ub.append(el('span', { class: 'dash-card', style: 'min-width:0; padding:.35rem .6rem' },
          el('b', {}, u.login), ' ', el('span', { class: 'small muted' }, u.count + T(' arq · ', ' files · ') + Math.max(1, Math.round((u.bytes || 0) / 1024)) + ' KB'), ' ',
          el('a', { href: '#', class: 'small', title: T('Baixar zip com todos os arquivos deste usuário', 'Download a zip with all files of this user'),
            onclick: (e) => { e.preventDefault(); downloadAuthed(CONTEST, '/contest/admin/backup-zip?contest=' + enc(CONTEST) + '&login=' + enc(u.login), 'backups-' + u.login + '.zip'); } }, '⬇ ZIP'))));
        body.append(el('div', { style: 'margin-bottom:.3rem' }, el('b', {}, T('Por usuário: ', 'Per user: ')), ub));
      }
      const items = r.backups || [];
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' arquivo(s).', ' file(s).')));
      if (!items.length) { body.append(el('div', { class: 'muted' }, T('Nada encontrado.', 'Nothing found.'))); return; }
      const tb = el('tbody');
      items.forEach((b) => tb.append(el('tr', {},
        el('td', {}, b.login), el('td', {}, b.name),
        el('td', { class: 'small' }, Math.max(1, Math.round((b.size || 0) / 1024)) + ' KB'),
        el('td', { class: 'small' }, fmtDate(b.time)),
        el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed(CONTEST, '/contest/backup-file?contest=' + enc(CONTEST) + '&login=' + enc(b.login) + '&id=' + enc(b.id), b.name); } }, T('⬇ baixar', '⬇ download'))))));
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Usuário', 'User')), el('th', {}, T('Arquivo', 'File')), el('th', {}, T('Tam.', 'Size')), el('th', {}, T('Enviado', 'Uploaded')), el('th', {}, ''))), tb)));
    }
    [fUser, fQ].forEach((i) => i.addEventListener('change', run));
    box.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' }, el('span', { class: 'small muted' }, T('Filtros:', 'Filters:')), fUser, fQ,
      el('button', { class: 'btn ghost', onclick: run }, '↻')), body);
    return { box, run };
  }

  async function load() {
    panel.innerHTML = '';
    const a = auditSection(), b = backupsSection();
    panel.append(a.box, b.box);
    await Promise.all([a.run(), b.run()]);
  }
  return { panel, load };
}
