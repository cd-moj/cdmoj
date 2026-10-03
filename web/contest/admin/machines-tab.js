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
import { fmtEpoch as fmt, fmtDate, fmtClock, toCsv, downloadText, PRIV_RE } from '/shared/admin-ui.js';

const enc = encodeURIComponent;

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
      setMsg(T(`✓ sede "${region}" gravada em ${logins.length} time(s)`, `✓ site "${region}" saved for ${logins.length} team(s)`, `✓ sede "${region}" guardada para ${logins.length} equipo(s)`)
        + (j && j.updated != null ? ` (${j.updated})` : ''));
      await load();
    } catch (e) { setMsg(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
  }
  // lista editável (uma linha por item) usada pelos overrides por sede, regras por regex e isentos
  function listEditor(items, render) {
    const wrap = el('div', { style: 'display:flex;flex-direction:column;gap:.25rem' });
    const rows = [];
    const add = (v) => {
      const r = render(v || {});
      rows.push(r);
      const line = el('div', { class: 'row', style: 'gap:.35rem;align-items:center' }, ...r.els,
        el('button', { class: 'btn ghost small danger', title: T('remover', 'remove', 'quitar'), onclick: () => { r.dead = true; line.remove(); } }, '✕'));
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
    // o MODO DE VERDADE: sem ua-gate.json o servidor devolve "enforce" só p/ o LOGIN_UA_SUBSTRING legado valer —
    // sem ele (e sem regra) nada é barrado. A caixa marcada "ativo — o login devolve 403" sem gate nenhum foi o
    // que fez o organizador do TCP 2026 (03/10/2026) achar que o gate funcionava.
    const configured = !!(GATE && GATE.configured), hasRule = !!(GATE && GATE.has_rule);
    const curMode = !configured ? ((GATE && GATE.legacy) ? 'enforce' : 'off') : (g.mode || 'off');
    const on = curMode === 'enforce' && hasRule;
    box.append(el('h3', { style: 'margin:.1rem 0 .3rem' }, T('🔒 Gate de navegador por sede', '🔒 Per-site browser gate', '🔒 Gate de navegador por sede')),
      el('p', { class: 'small muted' },
        T('A imagem de prova de cada sede manda um User-Agent que carrega um pedaço do login do time (teambrspso001 → brspso). Uma regra com captura cobre todas as sedes de uma vez. Contas de papel (.admin/.judge/.staff/…) nunca são barradas.',
          'Each site image sends a User-Agent carrying a slice of the team login (teambrspso001 → brspso). One capture rule covers every site at once. Role accounts (.admin/.judge/.staff/…) are never blocked.',
          'Cada imagen de sede envía un User-Agent que lleva un fragmento del login del equipo (teambrspso001 → brspso). Una regla con captura cubre todas las sedes de una vez. Las cuentas de papel (.admin/.judge/.staff/…) nunca son bloqueadas.')));

    // TRÊS modos: desligado · OBSERVAR (mostra esperado × visto e o "UA fora do esperado" nas Anomalias, sem barrar
    // nem derrubar sessão — dá p/ ligar no meio da prova) · BARRAR (o login devolve 403 ua_gate)
    const MODES = () => [
      ['off', T('Desligado', 'Off', 'Desactivado'), T('qualquer navegador entra (a configuração fica guardada)', 'any browser gets in (the configuration is kept)', 'cualquier navegador entra (la configuración se conserva)')],
      ['observe', T('Observar', 'Observe', 'Observar'), T('ninguém é barrado: o painel e as Anomalias mostram quem entrou fora da imagem da sede', 'nobody is blocked: the panel and Anomalies show who logged in outside the site image', 'nadie es bloqueado: el panel y las Anomalías muestran quién entró fuera de la imagen de la sede')],
      ['enforce', T('Barrar', 'Block', 'Bloquear'), T('quem não vem da imagem da sede leva 403 no login (ua_gate)', 'anyone not coming from the site image gets 403 at login (ua_gate)', 'quien no viene de la imagen de la sede recibe 403 en el login (ua_gate)')],
    ];
    let modeSel = curMode;
    const modeRadios = el('div', { style: 'display:flex;flex-direction:column;gap:.2rem;margin:.2rem 0' },
      ...MODES().map(([v, lbl, hint]) => el('label', { class: 'row', style: 'gap:.5rem;align-items:center' },
        el('input', { type: 'radio', name: 'ua-gate-mode-' + CONTEST, value: v, checked: v === curMode, onchange: () => { modeSel = v; } }),
        el('b', {}, lbl), el('span', { class: 'small muted' }, hint))));
    // o que vale AGORA, em uma frase (sem regra, nenhum modo faz nada)
    const nowTxt = !hasRule
      ? T('⚠ Nenhuma regra: ninguém é barrado nem observado, e a sessão única não vale. Preencha a regex do login (ou uma sede/regra/fallback) e escolha o modo.',
          '⚠ No rule: nobody is blocked or observed, and single session does not apply. Fill in the login regex (or a site/rule/fallback) and choose the mode.',
          '⚠ Ninguna regla: nadie es bloqueado ni observado, y la sesión única no vale. Completa la regex del login (o una sede/regla/fallback) y elige el modo.')
      : curMode === 'enforce' ? T('Agora: BARRANDO — o login devolve 403 ua_gate fora da imagem da sede.', 'Now: BLOCKING — login returns 403 ua_gate outside the site image.', 'Ahora: BLOQUEANDO — el login devuelve 403 ua_gate fuera de la imagen de la sede.')
      : curMode === 'observe' ? T('Agora: OBSERVANDO — ninguém é barrado; quem entra fora do padrão aparece em Máquinas › Anomalias.', 'Now: OBSERVING — nobody is blocked; anyone logging in off-pattern shows up in Machines › Anomalies.', 'Ahora: OBSERVANDO — nadie es bloqueado; quien entra fuera del patrón aparece en Máquinas › Anomalías.')
      : T('Agora: desligado — qualquer navegador entra.', 'Now: off — any browser gets in.', 'Ahora: desactivado — cualquier navegador entra.');
    box.append(el('div', { class: on ? 'alert' : (!hasRule ? 'notice' : '') },
      el('div', { class: 'small', style: 'font-weight:600' }, nowTxt), modeRadios));

    // sessão única por time (lib/session-index.sh): só tem efeito no modo Barrar
    const single = el('input', { type: 'checkbox', checked: g.single_session !== false });
    box.append(el('div', { style: 'margin:.3rem 0' },
      el('label', { class: 'row', style: 'gap:.5rem;align-items:center' }, single,
        el('b', {}, T('Sessão única por time', 'Single session per team', 'Sesión única por equipo')),
        el('span', { class: 'small muted' },
          T('só no modo Barrar: login em outra máquina derruba a sessão anterior (troca por defeito continua funcionando). As quedas aparecem em Máquinas › Anomalias.',
            'Block mode only: a login on another machine ends the previous session (switching after a failure still works). Drops show up in Machines › Anomalies.',
            'solo en el modo Bloquear: un login en otra máquina termina la sesión anterior (el cambio tras una falla sigue funcionando). Las caídas aparecen en Máquinas › Anomalías.')))));
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
        slMsg.textContent = slChk.checked ? T('✓ trava ligada: o próximo login de competidor prende o IP da sede', '✓ lock on: the next competitor login pins the site IP', '✓ bloqueo activo: el próximo login de competidor fija el IP de la sede')
          : T('✓ trava desligada (IPs já presos continuam até vencer; solte-os na trava abaixo)', '✓ lock off (already pinned IPs stay until expiry; release them in the lock below)', '✓ bloqueo desactivado (los IP ya fijados se quedan hasta vencer; suéltalos en el bloqueo de abajo)');
      } catch (e) { slMsg.className = 'small error-box'; slMsg.textContent = e.message || T('falha', 'failed', 'fallido'); }
    });
    box.append(el('div', { class: sl.enabled ? 'alert' : '', style: 'margin:.3rem 0' },
      el('label', { class: 'row', style: 'gap:.5rem;align-items:center' }, slChk,
        el('b', {}, T('Trava de sede por IP', 'Per-site IP lock', 'Bloqueo de sede por IP')),
        el('span', { class: 'small muted' },
          T('cada login de competidor prende o IP de origem (a saída da sede) a ESTA prova até o fim + folga: daquele IP, treino, índice e outros contests respondem 403 site_locked (curl --resolve não escapa). Contas de papel ficam isentas. Toda reivindicação e todo bloqueio vão ao audit e a Máquinas › Anomalias.',
            'each competitor login pins the source IP (the site egress) to THIS contest until the end + grace: from that IP, training, index and other contests answer 403 site_locked (curl --resolve does not escape). Role accounts are exempt. Every claim and every block goes to the audit and to Machines › Anomalies.',
            'cada login de competidor fija el IP de origen (la salida de la sede) a ESTA competencia hasta el fin + margen: desde ese IP, entrenamiento, índice y otras competencias responden 403 site_locked (curl --resolve no escapa). Las cuentas de papel están exentas. Todo reclamo y todo bloqueo van al audit y a Máquinas › Anomalías.'))),
      sl.enabled ? el('div', { class: 'small', style: 'margin-top:.2rem' }, T(`${nAct} IP(s) preso(s) agora`, `${nAct} IP(s) pinned now`, `${nAct} IP(s) fijado(s) ahora`), ' · ', el('a', { href: '#maquinas/anomalias' }, T('ver em Sessões & anomalias', 'see in Sessions & anomalies', 'ver en Sesiones y anomalías'))) : null,
      slMsg));
    const rx = el('input', { value: (g.from_login && g.from_login.regex) || '', placeholder: '^team([a-z]{6})[0-9]{3}$', style: 'width:16rem;font-family:var(--mono)' });
    const ex = el('input', { value: (g.from_login && g.from_login.expect) || '\\1', placeholder: '\\1', style: 'width:7rem;font-family:var(--mono)' });
    const someLogin = ((DATA && DATA.by_login) || []).map((r) => r.login).find((l) => !PRIV_RE.test(l)) || '';
    const chkIn = el('input', { value: someLogin, placeholder: T('login do time', 'team login', 'login del equipo'), style: 'width:11rem;font-family:var(--mono)' });
    const chkOut = el('span', { class: 'small' }, '—');
    const doCheck = async () => {
      const l = chkIn.value.trim(); if (!l) return;
      chkOut.textContent = '…';
      try {
        const r = await apiPost('/contest/admin/ua-gate?contest=' + enc(CONTEST), { action: 'check', login: l }, G);
        const c = r.check || {};
        chkOut.innerHTML = '';
        chkOut.append(c.gated
          ? el('span', {}, T('UA precisa conter ', 'UA must contain ', 'UA debe contener '), el('code', {}, c.expected),
            c.region ? el('span', { class: 'muted' }, ' · ' + T('sede ', 'site ', 'sede ') + c.region) : null)
          : el('span', { class: 'pill' }, T('isento (entra com qualquer navegador)', 'exempt (any browser gets in)', 'exento (entra con cualquier navegador)')));
      } catch (e) { chkOut.textContent = e.message || T('falha', 'failed', 'fallido'); }
    };
    box.append(el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap;align-items:flex-end;margin-top:.4rem' },
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('regex do login (com captura)', 'login regex (with capture)', 'regex del login (con captura)')), rx),
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('UA esperado', 'expected UA', 'UA esperado')), ex),
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('testar com o login', 'test with login', 'probar con el login')),
        el('div', { class: 'row', style: 'gap:.3rem' }, chkIn,
          el('button', { class: 'btn ghost', onclick: doCheck }, T('testar', 'test', 'probar')))),
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('resultado', 'result', 'resultado')), chkOut)));
    if (someLogin) doCheck();

    const regions = ((GATE && GATE.regions) || []).map((r) => r.name);
    const byRegion = listEditor(Object.entries(g.by_region || {}).map(([k, v]) => ({ k, v })), (v) => {
      const k = el('input', { value: v.k || '', placeholder: T('sede', 'site', 'sede'), list: 'ua-regions-dl', style: 'width:9rem' });
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
    const fb = el('input', { value: g.fallback || '', placeholder: T('(nenhum — sem regra, o time entra)', '(none — with no rule the team gets in)', '(ninguna — sin regla, el equipo entra)'), style: 'width:14rem;font-family:var(--mono)' });
    const grp = (label, hint, ed, btnLabel) => el('details', { class: 'fgroup' },
      el('summary', {}, label),
      el('div', { class: 'small muted', style: 'margin:.2rem 0 .4rem' }, hint),
      ed.wrap, el('button', { class: 'btn ghost small', style: 'margin-top:.3rem', onclick: () => ed.add({}) }, btnLabel));
    box.append(
      grp(T('Overrides por sede', 'Per-site overrides', 'Overrides por sede'),
        T('a sede tem imagem própria e o UA não segue a captura — vence a regra geral.',
          'the site has its own image and its UA does not follow the capture — beats the general rule.',
          'la sede tiene imagen propia y su UA no sigue la captura — vence la regla general.'),
        byRegion, T('+ sede', '+ site', '+ sede')),
      grp(T('Regras por regex de login', 'Login regex rules', 'Reglas regex de login'),
        T('para grupos que não seguem o padrão de nome (convidados, reservas).',
          'for groups that do not follow the naming pattern (guests, spares).',
          'para grupos que no siguen el patrón de nombre (invitados, reservas).'),
        byRegex, T('+ regra', '+ rule', '+ regla')),
      grp(T('Isentos (a margem)', 'Exempt (the margin)', 'Exentos (el margen)'),
        T('regex OU login literal: estes times entram de qualquer navegador. É aqui que entra o time cuja máquina falhou.',
          'regex OR literal login: these teams get in from any browser. This is where the team with a broken machine goes.',
          'regex O login literal: estos equipos entran desde cualquier navegador. Aquí es donde va el equipo con la máquina averiada.'),
        exempt, T('+ isento', '+ exempt', '+ exento')),
      el('datalist', { id: 'ua-regions-dl' }, ...regions.map((r) => el('option', { value: r }))),
      el('div', { class: 'field' }, el('label', { class: 'small' }, T('fallback (quem não casa nenhuma regra)', 'fallback (matching no rule)', 'fallback (que no coincide con ninguna regla)')), fb));
    // atalho: os UA realmente vistos nesta rodada viram fallback com um clique (era o gate antigo)
    const uas = (DATA && DATA.uas) || [];
    if (uas.length) {
      const ul = el('ul', { style: 'margin:.3rem 0 0 1.1rem' });
      uas.forEach((u) => ul.append(el('li', { class: 'small', style: 'overflow-wrap:anywhere;margin:.2rem 0' },
        el('code', {}, u), ' ',
        el('button', { class: 'btn ghost small', onclick: () => { fb.value = u; } }, T('usar como fallback', 'use as fallback', 'usar como fallback')))));
      box.append(el('details', { class: 'fgroup' },
        el('summary', {}, T(`Navegadores vistos nesta rodada (${uas.length})`, `Browsers seen in this round (${uas.length})`, `Navegadores vistos en esta ronda (${uas.length})`)),
        (GATE && GATE.legacy)
          ? el('div', { class: 'small muted' }, T('LOGIN_UA_SUBSTRING legado no conf: ', 'legacy LOGIN_UA_SUBSTRING in conf: ', 'LOGIN_UA_SUBSTRING legado en el conf: ') + GATE.legacy)
          : null,
        ul));
    }

    const save = async () => {
      try {
        await apiPost('/contest/admin/ua-gate?contest=' + enc(CONTEST), {
          action: 'set', mode: modeSel,
          from_login: rx.value.trim() ? { regex: rx.value.trim(), expect: ex.value.trim() || '\\1' } : null,
          by_region: Object.fromEntries(byRegion.get().map((o) => [o.k, o.v])),
          by_regex: byRegex.get(), exempt: exempt.get(), fallback: fb.value.trim(),
          single_session: single.checked,
        }, G);
        setMsg(T('✓ gate salvo. Quem já está logado continua — use "Deslogar UA divergente" em Máquinas › Anomalias.',
          '✓ gate saved. Already-logged-in users stay — use "Log out mismatched UA" in Machines › Anomalies.',
          '✓ gate guardado. Los usuarios ya conectados se quedan — usa "Desconectar UA divergente" en Máquinas › Anomalías.'));
        await load();
      } catch (e) { setMsg(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
    };
    box.append(el('div', { class: 'row', style: 'gap:.5rem;margin-top:.5rem' },
      el('button', { class: 'btn', onclick: save }, T('Salvar gate', 'Save gate', 'Guardar gate')),
      el('button', { class: 'btn ghost', onclick: load }, T('descartar', 'discard', 'descartar'))));
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
          + ((r.uas || []).length > 1 ? T(` (+${r.uas.length - 1})`, ` (+${r.uas.length - 1})`, ` (+${r.uas.length - 1})`) : '')),
        // GATE POR SEDE: o que a imagem da sede deste time deveria mandar × o que veio
        el('td', { class: 'small' + (r.ua_match === false ? ' flag-anom' : '') },
          r.ua_expected
            ? [el('code', {}, r.ua_expected), ' ',
               r.ua_match === false
                 ? el('span', { class: 'pill', style: 'background:#c0392b;color:#fff' }, T('fora do padrão', 'off-image', 'fuera de la imagen'))
                 : el('span', { class: 'pill ok' }, '✓')]
            : el('span', { class: 'muted' }, T('sem gate', 'no gate', 'sin gate'))),
        el('td', { class: 'small' }, fmt(r.first) + (r.logins > 1 ? T(` · ${r.logins} logins`, ` · ${r.logins} logins`, ` · ${r.logins} logins`) : '')),
        el('td', {}, r.changed ? el('span', { class: 'pill', style: 'background:#c0392b;color:#fff' },
          T('trocou de máquina', 'machine changed', 'cambió de máquina')) : (r.multi_ip ? el('span', { class: 'pill' }, T('vários IPs', 'several IPs', 'varios IPs')) : ''))));
    });
    return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {},
        el('th', {}, T('Time', 'Team', 'Equipo')), el('th', {}, T('Sede', 'Site', 'Sede')), el('th', {}, 'IP'),
        el('th', {}, 'User-Agent'), el('th', {}, T('UA esperado (sede)', 'expected UA (site)', 'UA esperado (sede)')),
        el('th', {}, T('1º login', 'first login', '1er login')), el('th', {}, ''))), tb));
  }

  function byIpTable() {
    const tb = el('tbody');
    (DATA.by_ip || []).filter((r) => !filter || r.ip.includes(filter)).forEach((r) => {
      const sedeInp = el('input', { placeholder: T('sede…', 'site…', 'sede…'), style: 'width:9rem' });
      tb.append(el('tr', {},
        el('td', {}, el('code', {}, r.ip)),
        el('td', { class: r.shared ? 'flag-anom' : '' }, (r.logins || []).join(', ')),
        el('td', {}, r.shared ? el('span', { class: 'pill' }, T('IP compartilhado', 'shared IP', 'IP compartido')) : ''),
        el('td', {}, el('div', { class: 'row', style: 'gap:.3rem' }, sedeInp,
          el('button', { class: 'btn ghost', onclick: () => {
            const v = sedeInp.value.trim();
            if (!v) { setMsg(T('digite o nome da sede', 'type the site name', 'escribe el nombre de la sede'), 'error-box'); return; }
            setRegion(r.logins || [], v);
          } }, T('aplicar sede', 'set site', 'aplicar sede'))))));
    });
    return el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
      el('thead', {}, el('tr', {}, el('th', {}, 'IP'), el('th', {}, T('Times', 'Teams', 'Equipos')),
        el('th', {}, ''), el('th', {}, T('Ação', 'Action', 'Acción')))), tb));
  }

  // ---- TRAVA DE SEDE POR IP: reivindicações e bloqueios (GET/POST /contest/admin/site-lock) ----
  // O toggle "ligar" mora no gateBox; aqui é a operação: quem está preso, quem foi bloqueado,
  // prender já os IPs vistos, soltar um IP. (Estava em Sessões & anomalias — 05/09.)
  function siteLockSection() {
    const sl = SLOCK; if (!sl) return null;
    const claims = sl.claims || [], blocks = sl.blocks || [];
    if (!sl.enabled && !claims.length && !blocks.length) return null;
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' }, el('h3', { style: 'margin:.1rem 0 .3rem' }, T('🔒 Trava de sede por IP — reivindicações e bloqueios', '🔒 Per-site IP lock — claims and blocks', '🔒 Bloqueo de sede por IP — reclamos y bloqueos')));
    box.append(el('p', { class: 'small muted' },
      sl.enabled
        ? T(`Ligada: cada login de competidor prende o IP de origem a este contest até o fim + ${sl.grace}s. Daquele IP, treino, índice e outros contests respondem 403 site_locked. Toda reivindicação e todo bloqueio ficam no audit.`,
          `On: each competitor login pins the source IP to this contest until the end + ${sl.grace}s. From that IP, training, index and other contests answer 403 site_locked. Every claim and every block is in the audit log.`,
          `Activa: cada login de competidor fija el IP de origen a esta competencia hasta el fin + ${sl.grace}s. Desde ese IP, entrenamiento, índice y otras competencias responden 403 site_locked. Todo reclamo y todo bloqueo están en el log de auditoría.`)
        : T('Desligada (ligue no gate acima). IPs presos anteriormente continuam até vencer.', 'Off (turn on in the gate above). Previously pinned IPs stay until they expire.', 'Apagada (actívala en el gate de arriba). Los IP fijados anteriormente se quedan hasta que venzan.')));
    const msg = el('span', { class: 'small' });
    const actions = el('div', { class: 'row', style: 'gap:.5rem;align-items:center;margin:.3rem 0' },
      sl.enabled ? el('button', { class: 'btn ghost', title: T('prende desde já os IPs de competidores vistos na janela da rodada (aquecimento incluso)', 'pins right away the competitor IPs seen in the round window (warm-up included)', 'fija de inmediato los IP de competidores vistos en la ventana de la ronda (calentamiento incluido)'),
        onclick: async () => {
          if (!confirm(T('Prender agora todos os IPs de competidores vistos nesta rodada?', 'Pin now every competitor IP seen in this round?', '¿Fijar ahora todos los IP de competidores vistos en esta ronda?'))) return;
          try { const r = await apiPost('/contest/admin/site-lock?contest=' + enc(CONTEST), { action: 'claim-seen' }, G); msg.textContent = T(`✓ ${r.claimed} IP(s) novo(s) preso(s)`, `✓ ${r.claimed} new IP(s) pinned`, `✓ ${r.claimed} IP(s) nuevo(s) fijado(s)`); await load(); }
          catch (e) { msg.textContent = e.message || T('falha', 'failed', 'fallido'); }
        } }, T('🔒 Prender IPs já vistos', '🔒 Pin IPs already seen', '🔒 Fijar IPs ya vistos')) : null,
      msg);
    const tb = el('tbody');
    claims.forEach((c) => tb.append(el('tr', { class: c.blocked ? 'flag-row-bad' : '' },
      el('td', {}, el('code', {}, c.ip), c.active ? '' : el('span', { class: 'small muted' }, ' ' + T('(vencida)', '(expired)', '(vencido)'))),
      el('td', { class: 'small' }, fmtClock(c.first) + ' → ' + fmtClock(c.last)),
      el('td', { class: 'n' }, String(c.logins)),
      el('td', { class: 'n' }, el('span', { class: c.blocked ? 'flag-anom' : '' }, String(c.blocked))),
      el('td', { class: 'small' }, c.blocked ? fmtClock(c.last_block) + (c.last_target && c.last_target !== '-' ? ' → ' + c.last_target : ' → ' + T('treino/índice', 'training/index', 'entrenamiento/índice')) : '—'),
      el('td', { class: 'small' }, fmtDate(c.until)),
      el('td', {}, el('button', { class: 'btn ghost danger small', onclick: async () => {
        if (!confirm(T(`Soltar ${c.ip}? Daquele IP o treino e outros contests voltam a responder.`, `Release ${c.ip}? From that IP training and other contests answer again.`, `¿Soltar ${c.ip}? Desde ese IP entrenamiento y otras competencias vuelven a responder.`))) return;
        try { await apiPost('/contest/admin/site-lock?contest=' + enc(CONTEST), { action: 'release', ip: c.ip }, G); await load(); } catch (e) { alert(e.message); }
      } }, T('soltar', 'release', 'soltar'))))));
    box.append(actions, el('div', { class: 'small muted' }, claims.length + T(' IP(s) preso(s).', ' pinned IP(s).', ' IP(s) fijado(s).')),
      el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
        el('th', {}, 'IP'), el('th', {}, T('Logins (1º → último)', 'Logins (first → last)', 'Logins (primero → último)')), el('th', { class: 'n' }, T('Logins', 'Logins', 'Logins')),
        el('th', { class: 'n' }, T('Bloqueios', 'Blocks', 'Bloqueos')), el('th', {}, T('Último bloqueio', 'Last block', 'Último bloqueo')), el('th', {}, T('Preso até', 'Pinned until', 'Fijado hasta')), el('th', {}, ''))), tb)));
    if (blocks.length) {
      const tb2 = el('tbody');
      blocks.slice(0, 100).forEach((b) => tb2.append(el('tr', { class: 'flag-row-bad' },
        el('td', { class: 'small' }, fmtDate(b.at)), el('td', {}, el('code', {}, b.ip)),
        el('td', {}, b.target && b.target !== '-' ? b.target : el('span', { class: 'muted' }, T('treino/índice', 'training/index', 'entrenamiento/índice'))),
        el('td', { class: 'small' }, el('code', {}, b.route)), el('td', {}, b.login && b.login !== '-' ? b.login : el('span', { class: 'muted' }, T('sem sessão', 'no session', 'sin sesión'))))));
      box.append(el('h4', {}, T(`Bloqueios registrados (${blocks.length}; 1 linha por IP e alvo a cada 5 min)`, `Recorded blocks (${blocks.length}; 1 line per IP and target every 5 min)`, `Bloqueos registrados (${blocks.length}; 1 línea por IP y destino cada 5 min)`)),
        el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' }, el('thead', {}, el('tr', {},
          el('th', {}, T('Quando', 'When', 'Cuándo')), el('th', {}, 'IP'), el('th', {}, T('Alvo', 'Target', 'Destino')), el('th', {}, T('Rota', 'Route', 'Ruta')), el('th', {}, T('Sessão', 'Session', 'Sesión')))), tb2)));
    }
    return box;
  }

  function render() {
    panel.innerHTML = '';
    // h2 PRIMEIRO (antes o gate vinha em cima e o título do painel ficava no meio da página)
    panel.append(el('h2', {}, T('💻 Máquinas dos times — gate & trava', '💻 Team machines — gate & lock', '💻 Máquinas de los equipos — gate y bloqueo')),
      el('p', { class: 'small muted' },
        T('De onde cada time logou nesta rodada (IP e navegador), do log de acessos do contest. Use o aquecimento para mapear a sala: depois, quem aparecer de outra máquina na prova fica marcado.',
          'Where each team logged in from during this round (IP and browser), from the contest access log. Use the warm-up to map the room: afterwards, anyone showing up from another machine during the contest gets flagged.',
          'De dónde se conectó cada equipo en esta ronda (IP y navegador), del log de accesos de la competencia. Usa el calentamiento para mapear la sala: después, quien aparezca desde otra máquina durante la competencia queda marcado.')));

    const sel = el('select', { onchange: (e) => { round = e.target.value; load(); } },
      ...ROUNDS.map((r) => el('option', { value: r.slug, selected: r.slug === DATA.round },
        (r.name || r.slug) + (r.state === 'active' ? T(' (no ar)', ' (live)', ' (activa)') : ''))));
    const f = el('input', { placeholder: T('filtrar time, login, IP ou navegador…', 'filter team, login, IP or browser…', 'filtrar equipo, login, IP o navegador…'),
      value: filter, style: 'min-width:16rem' });
    f.addEventListener('input', () => { filter = f.value; renderBody(); });
    const t = DATA.totals || {};
    panel.append(el('div', { class: 'row', style: 'gap:.6rem;align-items:center;flex-wrap:wrap;margin:.3rem 0' },
      el('span', { class: 'small' }, T('rodada:', 'round:', 'ronda:')), sel, f,
      el('button', { class: 'btn ghost', onclick: () => { view = (view === 'login' ? 'ip' : 'login'); renderBody(); } },
        T('↔ ver por IP / por time', '↔ view by IP / by team', '↔ ver por IP / por equipo')),
      el('button', { class: 'btn ghost', onclick: () => {
        const rows = [['login', T('time', 'team', 'equipo'), T('sede', 'site', 'sede'), 'ip', 'user_agent',
          T('ua_esperado', 'ua_expected', 'ua_esperado'), T('ua_bate', 'ua_match', 'ua_coincide'),
          'logins', T('primeiro', 'first', 'primero'), T('ultimo', 'last', 'ultimo'), T('trocou', 'changed', 'cambio')]];
        (DATA.by_login || []).forEach((r) => (r.pairs || []).forEach((p) => rows.push([
          r.login, r.name, r.region, p.ip, p.ua, r.ua_expected || '',
          r.ua_expected ? (r.ua_match === false ? 'nao' : 'sim') : '',
          p.n, fmt(p.first), fmt(p.last), r.changed ? 'sim' : ''])));
        downloadText('maquinas-' + CONTEST + '-' + (DATA.round || '') + '.csv', toCsv(rows), 'text/csv');
      } }, '⇣ CSV')));
    panel.append(el('div', { class: 'small muted' },
      T(`${t.logins || 0} conta(s) · ${t.ips || 0} IP(s) · ${t.changed || 0} trocaram de máquina · ${t.shared_ips || 0} IP(s) compartilhado(s) · ${t.ua_mismatch || 0} fora da imagem da sede`,
        `${t.logins || 0} account(s) · ${t.ips || 0} IP(s) · ${t.changed || 0} changed machine · ${t.shared_ips || 0} shared IP(s) · ${t.ua_mismatch || 0} off the site image`,
        `${t.logins || 0} cuenta(s) · ${t.ips || 0} IP(s) · ${t.changed || 0} cambiaron de máquina · ${t.shared_ips || 0} IP(s) compartido(s) · ${t.ua_mismatch || 0} fuera de la imagen de la sede`)),
      msg);
    const body = el('div', {});
    panel.append(body);
    function renderBody() { body.innerHTML = ''; body.append(view === 'ip' ? byIpTable() : byLoginTable()); }
    renderBody();
    panel.append(gateBox());
    const slb = siteLockSection(); if (slb) panel.append(slb);
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
      panel.append(el('h2', {}, T('💻 Máquinas dos times', '💻 Team machines', '💻 Máquinas de los equipos')),
        el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load', 'falló al cargar')));
    }
  }
  return { panel, load };
}
