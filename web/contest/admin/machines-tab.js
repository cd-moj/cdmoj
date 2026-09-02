// contest/admin/machines-tab.js — aba "💻 Máquinas": time × IP × User-Agent da rodada.
//
// É no aquecimento que os times ligam de fato os computadores da sala — então é ali que se
// descobre de onde vem cada time. O dado sai do access.log do contest recortado pela janela da
// rodada (nada novo é capturado). Na prova oficial, quem loga de IP/UA diferente do aquecimento
// aparece marcado: time na máquina errada, ou conta emprestada.
//
// As AÇÕES reusam o que já existe: preencher a sede é o mesmo POST da aba 👥 Times. E é AQUI que
// se configura o GATE DE NAVEGADOR POR SEDE (seção `gateBox`, POST /contest/admin/ua-gate) —
// porque é aqui que se vê o esperado × visto de cada time, que é o que diz se a regra está certa.
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
  let DATA = null, ROUNDS = [], GATE = null, SLOCK = null, round = '', filter = '', view = 'login';

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
  // lista editável (uma linha por item) usada pelos overrides por sede, regras por regex e isentos
  function listEditor(items, render) {
    const wrap = el('div', { style: 'display:flex;flex-direction:column;gap:.25rem' });
    const rows = [];
    const add = (v) => {
      const r = render(v || {});
      rows.push(r);
      const line = el('div', { class: 'row', style: 'gap:.35rem;align-items:center' }, ...r.els,
        el('button', { class: 'btn ghost small danger', title: T('remover', 'remove'), onclick: () => { r.dead = true; line.remove(); } }, '✕'));
      wrap.append(line);
    };
    (items || []).forEach(add);
    return { wrap, add, get: () => rows.filter((r) => !r.dead).map((r) => r.get()).filter((v) => v != null) };
  }

  // ---- GATE DE NAVEGADOR POR SEDE (POST /contest/admin/ua-gate) ----
  // A imagem de cada sede manda um UA com um pedaço do login do time (teambrspso001 -> brspso),
  // então UMA regra com captura cobre todas as sedes; o resto é override/isento. É aqui, e não em
  // Configurações, porque é aqui que se vê o esperado × visto de cada time.
  function gateBox() {
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' });
    const g = (GATE && GATE.gate) || {};
    const on = (g.mode || 'off') === 'enforce';
    box.append(el('h3', { style: 'margin:.1rem 0 .3rem' }, T('🔒 Gate de navegador por sede', '🔒 Per-site browser gate')),
      el('p', { class: 'small muted' },
        T('A imagem de prova de cada sede manda um User-Agent que carrega um pedaço do login do time (teambrspso001 → brspso). Uma regra com captura cobre todas as sedes de uma vez. Contas de papel (.admin/.judge/.staff/…) nunca são barradas.',
          'Each site image sends a User-Agent carrying a slice of the team login (teambrspso001 → brspso). One capture rule covers every site at once. Role accounts (.admin/.judge/.staff/…) are never blocked.')));

    const mode = el('input', { type: 'checkbox', checked: on });
    box.append(el('div', { class: on ? 'alert' : '' },
      el('label', { class: 'row', style: 'gap:.5rem;align-items:center' }, mode,
        el('b', {}, T('Barrar quem não vem da imagem da sede', 'Block anyone not coming from the site image')),
        el('span', { class: 'small muted' }, on
          ? T('(ativo — o login devolve 403 ua_gate)', '(active — login returns 403 ua_gate)')
          : T('(desligado — a configuração fica guardada)', '(off — the configuration is kept)')))));

    // sessão única por time (lib/session-index.sh): só tem efeito com o gate ligado
    const single = el('input', { type: 'checkbox', checked: g.single_session !== false });
    box.append(el('div', { style: 'margin:.3rem 0' },
      el('label', { class: 'row', style: 'gap:.5rem;align-items:center' }, single,
        el('b', {}, T('Sessão única por time', 'Single session per team')),
        el('span', { class: 'small muted' },
          T('login em outra máquina derruba a sessão anterior (troca por defeito continua funcionando). As quedas aparecem em Pessoas › Sessões & anomalias.',
            'a login on another machine ends the previous session (switching after a failure still works). Drops show up in People › Sessions & anomalies.')))));
    // TRAVA DE SEDE POR IP (lib/site-lock.sh): conf SITE_LOCK, própria rota — o gate de UA e a
    // sessão única não seguram `curl --resolve` da máquina de prova ao treino; o IP de origem sim
    const sl = SLOCK || {};
    const slChk = el('input', { type: 'checkbox', checked: !!sl.enabled });
    const slMsg = el('span', { class: 'small' });
    const nAct = ((sl.claims || []).filter((c) => c.active)).length;
    slChk.addEventListener('change', async () => {
      slMsg.textContent = '…';
      try {
        await apiPost('/contest/admin/site-lock?contest=' + enc(CONTEST), { action: 'set', enabled: slChk.checked }, G);
        slMsg.textContent = slChk.checked ? T('✓ trava ligada: o próximo login de competidor prende o IP da sede', '✓ lock on: the next competitor login pins the site IP')
          : T('✓ trava desligada (IPs já presos continuam até vencer; solte-os em Sessões & anomalias)', '✓ lock off (already pinned IPs stay until expiry; release them in Sessions & anomalies)');
      } catch (e) { slMsg.className = 'small error-box'; slMsg.textContent = e.message || T('falha', 'failed'); }
    });
    box.append(el('div', { class: sl.enabled ? 'alert' : '', style: 'margin:.3rem 0' },
      el('label', { class: 'row', style: 'gap:.5rem;align-items:center' }, slChk,
        el('b', {}, T('Trava de sede por IP', 'Per-site IP lock')),
        el('span', { class: 'small muted' },
          T('cada login de competidor prende o IP de origem (a saída da sede) a ESTA prova até o fim + folga: daquele IP, treino, índice e outros contests respondem 403 site_locked (curl --resolve não escapa). Contas de papel ficam isentas. Toda reivindicação e todo bloqueio vão ao audit e a Pessoas › Sessões & anomalias.',
            'each competitor login pins the source IP (the site egress) to THIS contest until the end + grace: from that IP, training, index and other contests answer 403 site_locked (curl --resolve does not escape). Role accounts are exempt. Every claim and every block goes to the audit and to People › Sessions & anomalies.'))),
      sl.enabled ? el('div', { class: 'small', style: 'margin-top:.2rem' }, T(`${nAct} IP(s) preso(s) agora`, `${nAct} IP(s) pinned now`), ' · ', el('a', { href: '#pessoas/sessoes' }, T('ver em Sessões & anomalias', 'see in Sessions & anomalies'))) : null,
      slMsg));
    const rx = el('input', { value: (g.from_login && g.from_login.regex) || '', placeholder: '^team([a-z]{6})[0-9]{3}$', style: 'width:16rem;font-family:var(--mono)' });
    const ex = el('input', { value: (g.from_login && g.from_login.expect) || '\\1', placeholder: '\\1', style: 'width:7rem;font-family:var(--mono)' });
    const someLogin = ((DATA && DATA.by_login) || []).map((r) => r.login).find((l) => !/\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$/.test(l)) || '';
    const chkIn = el('input', { value: someLogin, placeholder: T('login do time', 'team login'), style: 'width:11rem;font-family:var(--mono)' });
    const chkOut = el('span', { class: 'small' }, '—');
    const doCheck = async () => {
      const l = chkIn.value.trim(); if (!l) return;
      chkOut.textContent = '…';
      try {
        const r = await apiPost('/contest/admin/ua-gate?contest=' + enc(CONTEST), { action: 'check', login: l }, G);
        const c = r.check || {};
        chkOut.innerHTML = '';
        chkOut.append(c.gated
          ? el('span', {}, T('UA precisa conter ', 'UA must contain '), el('code', {}, c.expected),
            c.region ? el('span', { class: 'muted' }, ' · ' + T('sede ', 'site ') + c.region) : null)
          : el('span', { class: 'pill' }, T('isento (entra com qualquer navegador)', 'exempt (any browser gets in)')));
      } catch (e) { chkOut.textContent = e.message || T('falha', 'failed'); }
    };
    box.append(el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap;align-items:flex-end;margin-top:.4rem' },
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('regex do login (com captura)', 'login regex (with capture)')), rx),
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('UA esperado', 'expected UA')), ex),
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('testar com o login', 'test with login')),
        el('div', { class: 'row', style: 'gap:.3rem' }, chkIn,
          el('button', { class: 'btn ghost', onclick: doCheck }, T('testar', 'test')))),
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('resultado', 'result')), chkOut)));
    if (someLogin) doCheck();

    const regions = ((GATE && GATE.regions) || []).map((r) => r.name);
    const byRegion = listEditor(Object.entries(g.by_region || {}).map(([k, v]) => ({ k, v })), (v) => {
      const k = el('input', { value: v.k || '', placeholder: T('sede', 'site'), list: 'ua-regions-dl', style: 'width:9rem' });
      const s = el('input', { value: v.v || '', placeholder: 'brspcp-especial', style: 'width:11rem;font-family:var(--mono)' });
      return { els: [k, el('span', { class: 'muted' }, '→'), s], get: () => (k.value.trim() ? { k: k.value.trim(), v: s.value.trim() } : null) };
    });
    const byRegex = listEditor(g.by_regex || [], (v) => {
      const k = el('input', { value: v.regex || '', placeholder: '^conv', style: 'width:9rem;font-family:var(--mono)' });
      const s = el('input', { value: v.expect || '', placeholder: 'convidado', style: 'width:11rem;font-family:var(--mono)' });
      return { els: [k, el('span', { class: 'muted' }, '→'), s], get: () => (k.value.trim() ? { regex: k.value.trim(), expect: s.value.trim() } : null) };
    });
    const exempt = listEditor((g.exempt || []).map((s) => ({ s })), (v) => {
      const k = el('input', { value: v.s || '', placeholder: '^ccl', style: 'width:14rem;font-family:var(--mono)' });
      return { els: [k], get: () => (k.value.trim() || null) };
    });
    const fb = el('input', { value: g.fallback || '', placeholder: T('(nenhum — sem regra, o time entra)', '(none — with no rule the team gets in)'), style: 'width:14rem;font-family:var(--mono)' });
    const grp = (label, hint, ed, btnLabel) => el('details', { class: 'fgroup' },
      el('summary', {}, label),
      el('div', { class: 'small muted', style: 'margin:.2rem 0 .4rem' }, hint),
      ed.wrap, el('button', { class: 'btn ghost small', style: 'margin-top:.3rem', onclick: () => ed.add({}) }, btnLabel));
    box.append(
      grp(T('Overrides por sede', 'Per-site overrides'),
        T('a sede tem imagem própria e o UA não segue a captura — vence a regra geral.',
          'the site has its own image and its UA does not follow the capture — beats the general rule.'),
        byRegion, T('+ sede', '+ site')),
      grp(T('Regras por regex de login', 'Login regex rules'),
        T('para grupos que não seguem o padrão de nome (convidados, reservas).',
          'for groups that do not follow the naming pattern (guests, spares).'),
        byRegex, T('+ regra', '+ rule')),
      grp(T('Isentos (a margem)', 'Exempt (the margin)'),
        T('regex OU login literal: estes times entram de qualquer navegador. É aqui que entra o time cuja máquina falhou.',
          'regex OR literal login: these teams get in from any browser. This is where the team with a broken machine goes.'),
        exempt, T('+ isento', '+ exempt')),
      el('datalist', { id: 'ua-regions-dl' }, ...regions.map((r) => el('option', { value: r }))),
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('fallback (quem não casa nenhuma regra)', 'fallback (matching no rule)')), fb));
    // atalho: os UA realmente vistos nesta rodada viram fallback com um clique (era o gate antigo)
    const uas = (DATA && DATA.uas) || [];
    if (uas.length) {
      const ul = el('ul', { style: 'margin:.3rem 0 0 1.1rem' });
      uas.forEach((u) => ul.append(el('li', { class: 'small', style: 'overflow-wrap:anywhere;margin:.2rem 0' },
        el('code', {}, u), ' ',
        el('button', { class: 'btn ghost small', onclick: () => { fb.value = u; } }, T('usar como fallback', 'use as fallback')))));
      box.append(el('details', { class: 'fgroup' },
        el('summary', {}, T(`Navegadores vistos nesta rodada (${uas.length})`, `Browsers seen in this round (${uas.length})`)),
        (GATE && GATE.legacy)
          ? el('div', { class: 'small muted' }, T('LOGIN_UA_SUBSTRING legado no conf: ', 'legacy LOGIN_UA_SUBSTRING in conf: ') + GATE.legacy)
          : null,
        ul));
    }

    const save = async () => {
      try {
        await apiPost('/contest/admin/ua-gate?contest=' + enc(CONTEST), {
          action: 'set', mode: mode.checked ? 'enforce' : 'off',
          from_login: rx.value.trim() ? { regex: rx.value.trim(), expect: ex.value.trim() || '\\1' } : null,
          by_region: Object.fromEntries(byRegion.get().map((o) => [o.k, o.v])),
          by_regex: byRegex.get(), exempt: exempt.get(), fallback: fb.value.trim(),
          single_session: single.checked,
        }, G);
        setMsg(T('✓ gate salvo. Quem já está logado continua — use "Deslogar UA divergente" em Pessoas › Sessões & anomalias.',
          '✓ gate saved. Already-logged-in users stay — use "Log out mismatched UA" in People › Sessions & anomalies.'));
        await load();
      } catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); }
    };
    box.append(el('div', { class: 'row', style: 'gap:.5rem;margin-top:.5rem' },
      el('button', { class: 'btn', onclick: save }, T('Salvar gate', 'Save gate')),
      el('button', { class: 'btn ghost', onclick: load }, T('descartar', 'discard'))));
    return box;
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

  function render() {
    panel.innerHTML = '';
    panel.append(gateBox(),
      el('h2', {}, T('💻 Máquinas dos times', '💻 Team machines')),
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
    panel.append(body);
    function renderBody() { body.innerHTML = ''; body.append(view === 'ip' ? byIpTable() : byLoginTable()); }
    renderBody();
  }

  async function load() {
    try {
      const [m, rj, ug, sl] = await Promise.all([
        apiGet('/contest/admin/machines?contest=' + enc(CONTEST) + (round ? '&round=' + enc(round) : ''), G),
        apiGet('/contest/admin/rounds?contest=' + enc(CONTEST), G).catch(() => ({ rounds: [] })),
        apiGet('/contest/admin/ua-gate?contest=' + enc(CONTEST), G).catch(() => null),
      apiGet('/contest/admin/site-lock?contest=' + enc(CONTEST), G).catch(() => null),
      ]);
      DATA = m; ROUNDS = (rj.rounds || []).filter((r) => r.state !== 'pending'); GATE = ug; SLOCK = sl;
      render();
    } catch (e) {
      panel.innerHTML = '';
      panel.append(el('h2', {}, T('💻 Máquinas dos times', '💻 Team machines')),
        el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load')));
    }
  }
  return { panel, load };
}
