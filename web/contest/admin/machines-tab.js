// contest/admin/machines-tab.js — aba "💻 Máquinas": time × IP × User-Agent da rodada.
//
// É no aquecimento que os times ligam de fato os computadores da sala — então é ali que se
// descobre de onde vem cada time. O dado sai do access.log do contest recortado pela janela da
// rodada (nada novo é capturado). Na prova oficial, quem loga de IP/UA diferente do aquecimento
// aparece marcado: time na máquina errada, ou conta emprestada.
//
// As AÇÕES reusam o que já existe: preencher a sede é o mesmo POST da aba 👥 Times; armar o gate
// de navegador é o mesmo POST da aba ⚙️ Configurações (login_ua_substring).
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const fmt = (e) => (+e ? new Date(+e * 1000).toLocaleString() : '—');
const csvCell = (v) => { const s = String(v == null ? '' : v); return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; };
const toCsv = (rows) => rows.map((r) => r.map(csvCell).join(',')).join('\r\n') + '\r\n';
function download(name, text) {
  const url = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' }));
  const a = el('a', { href: url, download: name }); document.body.append(a); a.click();
  setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
}

export function makeMachinesTab(CONTEST) {
  const panel = el('div', { class: 'section' });
  const G = { contest: CONTEST, auth: true };
  let DATA = null, ROUNDS = [], round = '', filter = '', view = 'login';

  const msg = el('div', { class: 'small', style: 'margin:.4rem 0' });
  const setMsg = (t, cls) => { msg.className = 'small ' + (cls || ''); msg.textContent = t; };

  async function setRegion(logins, region) {
    const set = {}; logins.forEach((l) => { set[l] = { region }; });
    try {
      const j = await apiPost('/contest/admin/teams?contest=' + enc(CONTEST), { set }, G);
      setMsg(T(`✓ sede "${region}" gravada em ${logins.length} time(s)`, `✓ site "${region}" saved for ${logins.length} team(s)`)
        + (j && j.updated != null ? ` (${j.updated})` : ''));
      await load();
    } catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); }
  }
  async function armUaGate(sub) {
    if (!confirm(T('Trancar o login do contest nos navegadores cujo User-Agent contenha:\n\n', 'Lock contest login to browsers whose User-Agent contains:\n\n') + sub
      + T('\n\nContas de papel (.admin/.judge/.staff/…) continuam isentas.', '\n\nRole accounts (.admin/.judge/.staff/…) stay exempt.'))) return;
    try {
      await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), { login_ua_substring: sub }, G);
      setMsg(T('✓ gate de navegador armado (quem já entrou continua: use "deslogar divergentes" na aba Usuários)',
               '✓ browser gate armed (already-logged-in users stay: use "log out mismatched" in the Users tab)'));
    } catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); }
  }

  function byLoginTable() {
    const rows = (DATA.by_login || []).filter((r) => {
      if (!filter) return true;
      const f = filter.toLowerCase();
      return (r.login + ' ' + r.name + ' ' + r.region + ' ' + (r.ips || []).join(' ') + ' ' + (r.uas || []).join(' ')).toLowerCase().includes(f);
    });
    const tb = el('tbody');
    rows.forEach((r) => {
      const ips = (r.ips || []).join(', ');
      const ua = (r.uas || [])[0] || '';
      tb.append(el('tr', {},
        el('td', {}, el('b', {}, r.name || r.login), el('br'), el('span', { class: 'small muted' }, r.login)),
        el('td', {}, r.region || el('span', { class: 'muted' }, '—')),
        el('td', { class: r.multi_ip ? 'flag-anom' : '' }, ips || '—'),
        el('td', { class: 'small', style: 'max-width:22rem;overflow-wrap:anywhere' }, ua
          + ((r.uas || []).length > 1 ? T(` (+${r.uas.length - 1})`, ` (+${r.uas.length - 1})`) : '')),
        // GATE POR SEDE: o que a imagem da sede deste time deveria mandar × o que veio
        el('td', { class: 'small' + (r.ua_match === false ? ' flag-anom' : '') },
          r.ua_expected
            ? [el('code', {}, r.ua_expected), ' ',
               r.ua_match === false
                 ? el('span', { class: 'pill', style: 'background:#c0392b;color:#fff' }, T('fora do padrão', 'off-image'))
                 : el('span', { class: 'pill ok' }, '✓')]
            : el('span', { class: 'muted' }, T('sem gate', 'no gate'))),
        el('td', { class: 'small' }, fmt(r.first) + (r.logins > 1 ? T(` · ${r.logins} logins`, ` · ${r.logins} logins`) : '')),
        el('td', {}, r.changed ? el('span', { class: 'pill', style: 'background:#c0392b;color:#fff' },
          T('trocou de máquina', 'machine changed')) : (r.multi_ip ? el('span', { class: 'pill' }, T('vários IPs', 'several IPs')) : ''))));
    });
    return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {},
        el('th', {}, T('Time', 'Team')), el('th', {}, T('Sede', 'Site')), el('th', {}, 'IP'),
        el('th', {}, 'User-Agent'), el('th', {}, T('UA esperado (sede)', 'expected UA (site)')),
        el('th', {}, T('1º login', 'first login')), el('th', {}, ''))), tb));
  }

  function byIpTable() {
    const tb = el('tbody');
    (DATA.by_ip || []).filter((r) => !filter || r.ip.includes(filter)).forEach((r) => {
      const sedeInp = el('input', { placeholder: T('sede…', 'site…'), style: 'width:9rem' });
      tb.append(el('tr', {},
        el('td', {}, el('code', {}, r.ip)),
        el('td', { class: r.shared ? 'flag-anom' : '' }, (r.logins || []).join(', ')),
        el('td', {}, r.shared ? el('span', { class: 'pill' }, T('IP compartilhado', 'shared IP')) : ''),
        el('td', {}, el('div', { class: 'row', style: 'gap:.3rem' }, sedeInp,
          el('button', { class: 'btn ghost', onclick: () => {
            const v = sedeInp.value.trim();
            if (!v) { setMsg(T('digite o nome da sede', 'type the site name'), 'error-box'); return; }
            setRegion(r.logins || [], v);
          } }, T('aplicar sede', 'set site'))))));
    });
    return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'IP'), el('th', {}, T('Times', 'Teams')),
        el('th', {}, ''), el('th', {}, T('Ação', 'Action')))), tb));
  }

  function uaBox() {
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' },
      el('h3', { style: 'margin:.1rem 0 .4rem' }, T('🔒 Gate de navegador (login_ua_substring)', '🔒 Browser gate (login_ua_substring)')));
    const uas = DATA.uas || [];
    if (!uas.length) { box.append(el('p', { class: 'small muted' }, T('nenhum User-Agent registrado nesta rodada', 'no User-Agent recorded in this round'))); return box; }
    if (DATA.ua_suggestion) {
      box.append(el('p', { class: 'small' },
        T('Substring comum a TODOS os navegadores vistos: ', 'Substring common to ALL browsers seen: '),
        el('code', {}, DATA.ua_suggestion)),
        el('button', { class: 'btn', onclick: () => armUaGate(DATA.ua_suggestion) },
          T('usar como gate', 'use as gate')));
    } else {
      box.append(el('p', { class: 'small muted' },
        T('Os navegadores vistos não têm substring comum — um gate único deixaria alguém de fora. Escolha um abaixo (ou padronize a sala antes).',
          'The browsers seen share no common substring — a single gate would lock someone out. Pick one below (or standardize the room first).')));
    }
    const ul = el('ul', { style: 'margin:.4rem 0 0 1.1rem' });
    uas.forEach((u) => ul.append(el('li', { class: 'small', style: 'overflow-wrap:anywhere;margin:.2rem 0' },
      el('code', {}, u), ' ',
      el('button', { class: 'btn ghost', onclick: () => armUaGate(u) }, T('usar', 'use')))));
    box.append(ul);
    return box;
  }

  function render() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('💻 Máquinas dos times', '💻 Team machines')),
      el('p', { class: 'small muted' },
        T('De onde cada time logou nesta rodada (IP e navegador), do log de acessos do contest. Use o aquecimento para mapear a sala: depois, quem aparecer de outra máquina na prova fica marcado.',
          'Where each team logged in from during this round (IP and browser), from the contest access log. Use the warm-up to map the room: afterwards, anyone showing up from another machine during the contest gets flagged.')));

    const sel = el('select', { onchange: (e) => { round = e.target.value; load(); } },
      ...ROUNDS.map((r) => el('option', { value: r.slug, selected: r.slug === DATA.round },
        (r.name || r.slug) + (r.state === 'active' ? T(' (no ar)', ' (live)') : ''))));
    const f = el('input', { placeholder: T('filtrar time, login, IP ou navegador…', 'filter team, login, IP or browser…'),
      value: filter, style: 'min-width:16rem' });
    f.addEventListener('input', () => { filter = f.value; renderBody(); });
    const t = DATA.totals || {};
    panel.append(el('div', { class: 'row', style: 'gap:.6rem;align-items:center;flex-wrap:wrap;margin:.3rem 0' },
      el('span', { class: 'small' }, T('rodada:', 'round:')), sel, f,
      el('button', { class: 'btn ghost', onclick: () => { view = (view === 'login' ? 'ip' : 'login'); renderBody(); } },
        T('↔ ver por IP / por time', '↔ view by IP / by team')),
      el('button', { class: 'btn ghost', onclick: () => {
        const rows = [[T('login', 'login'), T('time', 'team'), T('sede', 'site'), 'ip', 'user_agent',
          T('ua_esperado', 'ua_expected'), T('ua_bate', 'ua_match'),
          T('logins', 'logins'), T('primeiro', 'first'), T('ultimo', 'last'), T('trocou', 'changed')]];
        (DATA.by_login || []).forEach((r) => (r.pairs || []).forEach((p) => rows.push([
          r.login, r.name, r.region, p.ip, p.ua, r.ua_expected || '',
          r.ua_expected ? (r.ua_match === false ? 'nao' : 'sim') : '',
          p.n, fmt(p.first), fmt(p.last), r.changed ? 'sim' : ''])));
        download('maquinas-' + CONTEST + '-' + (DATA.round || '') + '.csv', toCsv(rows));
      } }, T('⇣ CSV', '⇣ CSV'))));
    panel.append(el('div', { class: 'small muted' },
      T(`${t.logins || 0} conta(s) · ${t.ips || 0} IP(s) · ${t.changed || 0} trocaram de máquina · ${t.shared_ips || 0} IP(s) compartilhado(s) · ${t.ua_mismatch || 0} fora da imagem da sede`,
        `${t.logins || 0} account(s) · ${t.ips || 0} IP(s) · ${t.changed || 0} changed machine · ${t.shared_ips || 0} shared IP(s) · ${t.ua_mismatch || 0} off the site image`)),
      msg);
    const body = el('div', {});
    panel.append(body, uaBox());
    function renderBody() { body.innerHTML = ''; body.append(view === 'ip' ? byIpTable() : byLoginTable()); }
    renderBody();
  }

  async function load() {
    try {
      const [m, rj] = await Promise.all([
        apiGet('/contest/admin/machines?contest=' + enc(CONTEST) + (round ? '&round=' + enc(round) : ''), G),
        apiGet('/contest/admin/rounds?contest=' + enc(CONTEST), G).catch(() => ({ rounds: [] })),
      ]);
      DATA = m; ROUNDS = (rj.rounds || []).filter((r) => r.state !== 'pending');
      render();
    } catch (e) {
      panel.innerHTML = '';
      panel.append(el('h2', {}, T('💻 Máquinas dos times', '💻 Team machines')),
        el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load')));
    }
  }
  return { panel, load };
}
