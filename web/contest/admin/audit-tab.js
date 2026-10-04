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
  const KIND = () => ({ admin: '🛠️ admin', login: '🔑 login', submit: T('📤 submissão', '📤 submission', '📤 envío'), verdict: T('⚖️ veredicto', '⚖️ verdict', '⚖️ veredicto') });

  function auditSection() {
    const box = el('div', { class: 'section' }, el('h2', {}, T('🧾 Auditoria do contest', '🧾 Contest audit', '🧾 Auditoría de la competencia')));
    const fUser = el('input', { type: 'search', placeholder: T('usuário…', 'user…', 'usuario…'), style: 'width:140px' });
    const fAction = el('input', { type: 'search', placeholder: T('ação/veredicto…', 'action/verdict…', 'acción/veredicto…'), style: 'width:170px' });
    const fSince = el('input', { type: 'date' });
    const body = el('div', {});
    let lastEvents = [];
    // o CSV "p/ auditoria externa" pede o MÁXIMO da API (5000), não os 500 da tela — saía truncado sem aviso
    const dl = el('button', { class: 'btn ghost', title: T('Baixar (CSV) para auditoria externa', 'Download (CSV) for external audit', 'Descargar (CSV) para auditoría externa'), onclick: async () => {
      let evs = lastEvents, r = null;
      try { const qp = query(); qp.set('limit', '5000'); r = await apiGet('/contest/admin/audit-log?contest=' + enc(CONTEST) + '&' + qp.toString(), G); evs = r.events || evs; } catch { /* fica o da tela */ }
      const rows = [['epoch', T('datahora', 'datetime', 'fechahora'), T('tipo', 'kind', 'tipo'), T('quem', 'who', 'quién'), T('acao', 'action', 'acción'), T('detalhes', 'details', 'detalles')],
        ...evs.map((x) => [x.time, new Date(x.time * 1000).toISOString(), x.kind, x.who || '', x.action || '', x.details || ''])];
      downloadText('auditoria-' + CONTEST + '-' + stamp() + '.csv', toCsv(rows), 'text/csv');
      if (r && r.truncated) alert(T(`O CSV traz os ${evs.length} eventos mais recentes de ${r.total}. Use o filtro de data para baixar o resto.`, `The CSV has the ${evs.length} most recent events of ${r.total}. Use the date filter to download the rest.`, `El CSV trae los ${evs.length} eventos más recientes de ${r.total}. Usa el filtro de fecha para descargar el resto.`));
    } }, '⬇ CSV');
    function query() {
      const qp = new URLSearchParams();
      if (fUser.value.trim()) qp.set('user', fUser.value.trim());
      if (fAction.value.trim()) qp.set('action', fAction.value.trim());
      if (fSince.value) { const e = Math.floor(new Date(fSince.value + 'T00:00:00').getTime() / 1000); if (e) qp.set('since', String(e)); }
      return qp;
    }
    async function run() {
      body.innerHTML = '';
      const qp = query();
      let r;
      try { r = await apiGet('/contest/admin/audit-log?contest=' + enc(CONTEST) + (qp.toString() ? '&' + qp.toString() : ''), G); }
      catch (e) { body.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || T('erro', 'error', 'error')))); return; }
      const ev = r.events || []; lastEvents = ev;
      const kind = KIND();
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, r.truncated
        ? T(`os ${ev.length} mais recentes de ${r.total} evento(s) — filtre por data, usuário ou ação para ver o resto.`, `the ${ev.length} most recent of ${r.total} event(s) — filter by date, user or action to see the rest.`, `los ${ev.length} más recientes de ${r.total} evento(s) — filtra por fecha, usuario o acción para ver el resto.`)
        : ev.length + T(' evento(s).', ' event(s).', ' evento(s).')));
      if (!ev.length) { body.append(el('div', { class: 'muted' }, T('Nada encontrado.', 'Nothing found.', 'No se encontró nada.'))); return; }
      const tb = el('tbody');
      ev.forEach((x) => tb.append(el('tr', { class: 'audit-' + x.kind },
        el('td', { class: 'small' }, fmtDate(x.time)),
        el('td', { class: 'small' }, kind[x.kind] || x.kind),
        el('td', {}, x.who || ''),
        el('td', {}, x.action || ''),
        el('td', { class: 'small', style: 'font-family:var(--mono)' }, x.details || ''))));
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Quando', 'When', 'Cuándo')), el('th', {}, T('Tipo', 'Type', 'Tipo')), el('th', {}, T('Quem', 'Who', 'Quién')), el('th', {}, T('Ação', 'Action', 'Acción')), el('th', {}, T('Detalhes', 'Details', 'Detalles')))), tb)));
    }
    [fUser, fAction, fSince].forEach((i) => i.addEventListener('change', run));
    box.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' },
      el('span', { class: 'small muted' }, T('Filtros:', 'Filters:', 'Filtros:')), fUser, fAction, el('span', { class: 'small muted' }, T('desde', 'since', 'desde')), fSince,
      el('button', { class: 'btn ghost', onclick: run }, '↻'), dl), body);
    return { box, run };
  }

  function backupsSection() {
    const box = el('div', { class: 'section' }, el('h2', {}, T('💾 Backups dos usuários', '💾 User backups', '💾 Respaldos de usuarios')));
    const fUser = el('input', { type: 'search', placeholder: T('usuário…', 'user…', 'usuario…'), style: 'width:140px' });
    const fQ = el('input', { type: 'search', placeholder: T('nome do arquivo…', 'file name…', 'nombre de archivo…'), style: 'width:160px' });
    const body = el('div', {});
    async function run() {
      body.innerHTML = '';
      const qp = new URLSearchParams();
      if (fUser.value.trim()) qp.set('user', fUser.value.trim());
      if (fQ.value.trim()) qp.set('q', fQ.value.trim());
      let r;
      try { r = await apiGet('/contest/admin/backups?contest=' + enc(CONTEST) + (qp.toString() ? '&' + qp.toString() : ''), G); }
      catch (e) { body.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || T('erro', 'error', 'error')))); return; }
      const users = r.users || [];
      if (users.length) {
        const ub = el('div', { class: 'row', style: 'flex-wrap:wrap; gap:.5rem; margin:.3rem 0 .6rem' });
        users.forEach((u) => ub.append(el('span', { class: 'dash-card', style: 'min-width:0; padding:.35rem .6rem' },
          el('b', {}, u.login), ' ', el('span', { class: 'small muted' }, u.count + T(' arq · ', ' files · ', ' archivos · ') + Math.max(1, Math.round((u.bytes || 0) / 1024)) + ' KB'), ' ',
          el('a', { href: '#', class: 'small', title: T('Baixar zip com todos os arquivos deste usuário', 'Download a zip with all files of this user', 'Descargar un zip con todos los archivos de este usuario'),
            onclick: (e) => { e.preventDefault(); downloadAuthed(CONTEST, '/contest/admin/backup-zip?contest=' + enc(CONTEST) + '&login=' + enc(u.login), 'backups-' + u.login + '.zip'); } }, '⬇ ZIP'))));
        body.append(el('div', { style: 'margin-bottom:.3rem' }, el('b', {}, T('Por usuário: ', 'Per user: ', 'Por usuario: ')), ub));
      }
      const items = r.backups || [];
      body.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' }, items.length + T(' arquivo(s).', ' file(s).', ' archivo(s).')));
      if (!items.length) { body.append(el('div', { class: 'muted' }, T('Nada encontrado.', 'Nothing found.', 'No se encontró nada.'))); return; }
      const tb = el('tbody');
      items.forEach((b) => tb.append(el('tr', {},
        el('td', {}, b.login), el('td', {}, b.name),
        el('td', { class: 'small' }, Math.max(1, Math.round((b.size || 0) / 1024)) + ' KB'),
        el('td', { class: 'small' }, fmtDate(b.time)),
        el('td', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadAuthed(CONTEST, '/contest/backup-file?contest=' + enc(CONTEST) + '&login=' + enc(b.login) + '&id=' + enc(b.id), b.name); } }, T('⬇ baixar', '⬇ download', '⬇ descargar'))))));
      body.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Usuário', 'User', 'Usuario')), el('th', {}, T('Arquivo', 'File', 'Archivo')), el('th', {}, T('Tam.', 'Size', 'Tam.')), el('th', {}, T('Enviado', 'Uploaded', 'Subido')), el('th', {}, ''))), tb)));
    }
    [fUser, fQ].forEach((i) => i.addEventListener('change', run));
    box.append(el('div', { class: 'row', style: 'margin-bottom:.4rem' }, el('span', { class: 'small muted' }, T('Filtros:', 'Filters:', 'Filtros:')), fUser, fQ,
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
