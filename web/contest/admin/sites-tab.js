// contest/admin/sites-tab.js — "Evento › Sedes & escolas" (módulo `sedes`): as SEDES do contest em TRÊS MODOS
// (relato de 28/09/2026: "o regions.json é complicado — um modo simples, um médio e o avançado"):
//   Simples       — lista de sedes + "logins que começam com" + atribuir times colando a lista (ou 1 a 1);
//   Intermediário — grupos › sedes, regras começa/contém/termina/lista;
//   Avançado      — a árvore inteira (subregiões, recortes, regex livre — o editor de sempre).
// A verdade é a ÁRVORE (sites-model.js); os modos são vistas dela e um modo só abre se a árvore couber
// (senão o botão diz por quê). A PRÉVIA roda aqui mesmo, com o gêmeo JS da regra única de sedes
// (web/shared/regions-match.js › rgAssign) sobre o mapa do servidor (GET /contest/admin/regions?map=1) +
// as atribuições pendentes — é o MESMO resultado que o servidor calcula (smoke-regions-match.gjs.sh).
// Salvar = UM POST /contest/admin/regions {tree, assign, mode, expect_sig}: 409 se outra aba/CLI mudou.
// Países e escolas (teams-meta) e a ⏱ prorrogação por sede seguem aqui embaixo, como antes.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { makeRegionsEditor, makeTeamsEditor } from '/shared/contest-config/index.js';
import { regexErrText } from '/shared/contest-config/regions.js';
import { rgAssign, rgNorm } from '/shared/regions-match.js';
import { T } from '/shared/i18n.js';
import { timeOverridesPanel } from './settings-tab.js';
import * as SM from './sites-model.js';

const enc = encodeURIComponent;
const MODES = () => [
  ['simple', T('Simples', 'Simple', 'Simple'), T('uma lista de sedes; times por "começa com" ou colando a lista', 'a list of sites; teams by "starts with" or by pasting the list', 'una lista de sedes; equipos por "empieza con" o pegando la lista')],
  ['rules', T('Intermediário', 'Intermediate', 'Intermedio'), T('grupos › sedes, com regras começa/contém/termina/lista', 'groups › sites, with starts/contains/ends/list rules', 'grupos › sedes, con reglas empieza/contiene/termina/lista')],
  ['tree', T('Avançado', 'Advanced', 'Avanzado'), T('a árvore inteira: subregiões, recortes e regex', 'the whole tree: sub-regions, cuts and regex', 'el árbol completo: subregiones, recortes y regex')],
];
function fitText(code) {
  return ({
    has_view: T('a árvore tem recortes (view)', 'the tree has cuts (view)', 'el árbol tiene recortes (view)'),
    has_subregions: T('a árvore tem subregiões', 'the tree has sub-regions', 'el árbol tiene subregiones'),
    too_deep: T('a árvore tem mais de dois níveis', 'the tree has more than two levels', 'el árbol tiene más de dos niveles'),
    group_regex: T('um grupo tem regex própria', 'a group has its own regex', 'un grupo tiene regex propia'),
    regex_free: T('alguma sede usa uma regex que não é uma regra simples', 'some site uses a regex that is not a simple rule', 'alguna sede usa una regex que no es una regla simple'),
    rules_not_prefix: T('alguma sede usa regra que não é "começa com"', 'some site uses a rule that is not "starts with"', 'alguna sede usa una regla que no es "empieza con"'),
    not_list: T('o regions.json não é uma lista de sedes', 'regions.json is not a list of sites', 'el regions.json no es una lista de sedes'),
  })[code] || code;
}
const RULE_LABEL = () => ({ starts: T('começa com', 'starts with', 'empieza con'), contains: T('contém', 'contains', 'contiene'),
  ends: T('termina com', 'ends with', 'termina con'), list: T('é um destes (lista)', 'is one of (list)', 'es uno de (lista)') });

export function makeSitesTab(CONTEST, opts = {}) {
  const G = { contest: CONTEST, auth: true };
  const go = typeof opts.go === 'function' ? opts.go : null;
  const has = typeof opts.has === 'function' ? opts.has : () => true;
  const panel = el('div', { class: 'section' });
  let tree = [], origTree = '[]', sig = '', mode = 'tree', savedMode = '';
  let users = [];                         // [{login, explicit}] — a população do mapa do servidor
  let explicit = new Map();               // login → sede GRAVADA hoje (flag x/o do mapa)
  let pending = new Map();                // login → sede proposta ("" = tirar)
  let moves = [];                         // renomeações desta edição: {from, to, n}
  let renames = [];                       // TODA sede renomeada (o servidor leva o escopo do staff, o gate e o telão junto)
  const view = el('div', {}), prev = el('div', {}), modeBar = el('div', { class: 'row', style: 'gap:.4rem;flex-wrap:wrap;margin:.4rem 0' });
  const msg = el('div', { class: 'small', style: 'margin:.4rem 0' });

  // ---------- prévia (rgAssign = a regra do servidor) ----------
  function preview() {
    const us = users.map((u) => ({ login: u.login, region: pending.has(u.login) ? pending.get(u.login) : u.explicit }));
    const res = rgAssign(tree, us);
    const cnt = new Map();
    res.rows.forEach((r) => r.nodes.forEach((i) => cnt.set(i, (cnt.get(i) || 0) + 1)));
    const by = (f) => res.rows.filter((r) => r.flag === f).map((r) => r.login);
    // casam em DUAS sedes (folhas não-recorte cuja regex casa) — a 1ª em pré-ordem venceu; vale conferir
    const leaves = res.nodes.filter((nd) => !nd.view && nd.leaf && nd.regex && !nd.orphan).map((nd) => new RegExp(nd.regex, 'i'));
    const two = res.rows.filter((r) => r.flag !== 'x' && r.flag !== 'o' && leaves.filter((re) => re.test(r.login)).length > 1).map((r) => r.login);
    return { res, cnt, none: by('-'), stopped: by('p'), orphans: res.nodes.filter((nd) => nd.orphan), two };
  }
  function renderPreview() {
    const p = preview(); prev.innerHTML = '';
    const n = users.length, withSite = n - p.none.length;
    const lst = (arr) => el('div', { class: 'small', style: 'max-height:9rem;overflow:auto' }, arr.slice(0, 200).join(', ') + (arr.length > 200 ? ' …' : ''));
    const det = (title, arr, cls) => (arr.length ? el('details', { class: 'small', style: 'margin:.2rem 0' },
      el('summary', { class: cls || '' }, title + ' (' + arr.length + ')'), lst(arr)) : '');
    prev.append(el('h3', { style: 'margin:1rem 0 .3rem' }, T('👀 Prévia (o que o placar, as etiquetas e o escopo do staff vão ver)', '👀 Preview (what the scoreboard, badges and staff scope will see)', '👀 Vista previa (lo que verán el marcador, las etiquetas y el alcance del staff)')),
      el('p', { class: 'small' }, withSite + T(' de ', ' of ', ' de ') + n + T(' times com sede', ' teams with a site', ' equipos con sede')));
    const rows = p.res.nodes.filter((nd) => nd.name).map((nd) => el('tr', {},
      el('td', {}, ' '.repeat(nd.depth * 3) + nd.name + (nd.view ? T(' (recorte)', ' (cut)', ' (recorte)') : '') + (nd.orphan ? T(' ⚠ fora da árvore', ' ⚠ outside the tree', ' ⚠ fuera del árbol') : '')),
      el('td', { style: 'text-align:right;font-variant-numeric:tabular-nums' }, String(p.cnt.get(nd.i) || 0))));
    if (rows.length) prev.append(el('div', { class: 'chart-wrap', style: 'max-height:18rem;overflow:auto' }, el('table', { class: 'moj' }, el('tbody', {}, ...rows))));
    prev.append(
      det(T('Sem sede', 'No site', 'Sin sede'), p.none),
      det(T('Pararam num grupo/país (a regex casou o grupo, nenhuma sede dele)', 'Stopped at a group/country (the regex matched the group, none of its sites)', 'Se quedaron en un grupo/país (la regex coincidió con el grupo, ninguna de sus sedes)'), p.stopped),
      det(T('Casam em duas sedes (valeu a primeira da lista)', 'Match two sites (the first in the list won)', 'Coinciden con dos sedes (valió la primera de la lista)'), p.two),
      p.orphans.length ? el('p', { class: 'small notice' }, T('Sede gravada em time que não existe na árvore: ', 'Site stored on a team that does not exist in the tree: ', 'Sede grabada en un equipo que no existe en el árbol: ')
        + p.orphans.map((o) => '«' + o.name + '»').join(', ') + T(' — crie a sede com esse nome ou atribua outra.', ' — create a site with that name or assign another one.', ' — crea una sede con ese nombre o asigna otra.')) : '');
    const changes = [];
    if (JSON.stringify(tree) !== origTree) changes.push(T('a árvore de sedes', 'the site tree', 'el árbol de sedes'));
    if (pending.size) changes.push(pending.size + T(' atribuição(ões) de time', ' team assignment(s)', ' asignación(es) de equipo'));
    moves.forEach((m) => changes.push('«' + m.from + '» → «' + m.to + '»: ' + m.n + T(' time(s) gravados mudam de nome junto', ' stored team(s) are renamed along', ' equipo(s) grabados cambian de nombre también')));
    if (changes.length) prev.append(el('div', { class: 'notice small', style: 'margin:.4rem 0' }, el('b', {}, T('A salvar: ', 'To save: ', 'Por guardar: ')), changes.join(' · ')));
  }
  // toda mudança refaz a prévia E os botões de modo: uma edição no JSON do Avançado pode fazer a árvore deixar de
  // caber no Simples/Intermediário — o botão tem de desabilitar na hora (senão a volta perderia a regex)
  const changed = () => { renderPreview(); drawModeButtons(); };

  // ---------- Simples ----------
  function viewSimple() {
    const rows = SM.toSimple(tree).map((s) => ({ ...s, prefixes: s.prefixes.join(', '), orig: s.name }));
    const box = el('div', {});
    const sync = () => { tree = SM.fromSimple(rows.map((r) => ({ name: r.name, prefixes: r.prefixes }))); changed(); };
    const draw = () => {
      box.innerHTML = '';
      const tb = el('tbody');
      rows.forEach((r, i) => {
        const nm = el('input', { value: r.name, placeholder: T('nome da sede', 'site name', 'nombre de la sede'), style: 'width:100%' });
        const pf = el('input', { value: r.prefixes, placeholder: T('ex.: teambrdf, ctba', 'e.g.: teambrdf, ctba', 'ej.: teambrdf, ctba'), style: 'width:100%' });
        nm.addEventListener('input', () => { r.name = nm.value; sync(); });
        // renomear: os times gravados com o nome velho acompanham (e a prévia mostra quantos)
        nm.addEventListener('change', () => {
          const to = nm.value.trim();
          if (r.orig && to && to !== r.orig) { const mv = SM.renameAssignments(explicit, pending, r.orig, to); if (mv.length) moves.push({ from: r.orig, to, n: mv.length }); renames.push({ from: r.orig, to }); r.orig = to; }
          sync();
        });
        pf.addEventListener('input', () => { r.prefixes = pf.value; sync(); });
        tb.append(el('tr', {}, el('td', {}, nm), el('td', {}, pf),
          el('td', {}, el('button', { class: 'btn ghost', type: 'button', title: T('remover sede', 'remove site', 'quitar sede'), onclick: () => { rows.splice(i, 1); draw(); sync(); } }, '✕'))));
      });
      box.append(el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Sede', 'Site', 'Sede')), el('th', {}, T('Logins que começam com (vírgula separa)', 'Logins that start with (comma-separated)', 'Usuarios que empiezan con (separados por coma)')), el('th', {}, ''))), tb)),
        el('button', { class: 'btn ghost', type: 'button', style: 'margin:.3rem 0', onclick: () => { rows.push({ name: '', prefixes: '', orig: '' }); draw(); } }, T('+ sede', '+ site', '+ sede')));
    };
    draw();
    view.append(box, assignBox(() => SM.toSimple(tree).map((s) => s.name)));
  }

  // atribuir a sede GRAVADA (vence a regex): colar logins, ou um a um nos times sem sede
  function assignBox(siteNames) {
    const wrap = el('div', { style: 'margin-top:.8rem' });
    const draw = () => {
      wrap.innerHTML = '';
      const names = siteNames().filter(Boolean);
      const mkSel = (val) => { const s = el('select', {}, el('option', { value: '' }, T('— sem sede gravada —', '— no stored site —', '— sin sede grabada —')), ...names.map((n) => el('option', { value: n }, n))); s.value = val || ''; return s; };
      const ta = el('textarea', { rows: '3', style: 'width:100%', placeholder: T('logins, um por linha (ou separados por vírgula)', 'logins, one per line (or comma-separated)', 'usuarios, uno por línea (o separados por coma)') });
      const sel = mkSel(''), out = el('span', { class: 'small' });
      const known = new Set(users.map((u) => u.login));
      const go1 = el('button', { class: 'btn', type: 'button', onclick: () => {
        // não barra aqui quem não está no mapa: membro de time inscrito não tem pasta, e o servidor grava a sede
        // no TIME dele; o que não existir volta em "não atribuídos" ao salvar
        const ls = ta.value.split(/[\s,;]+/).map((x) => x.trim()).filter(Boolean);
        const unk = ls.filter((l) => !known.has(l)); ls.forEach((l) => pending.set(l, sel.value));
        out.textContent = ls.length + T(' login(s) atribuído(s) — salve para gravar', ' login(s) assigned — save to store', ' usuario(s) asignado(s) — guarda para grabar')
          + (unk.length ? T('; sem pasta no contest (membro de time vai p/ o time; o resto o servidor recusa ao salvar): ', '; no folder in the contest (a team member goes to the team; the server refuses the rest on save): ', '; sin carpeta en la competencia (un miembro de equipo va al equipo; el servidor rechaza el resto al guardar): ') + unk.slice(0, 20).join(', ') : '');
        ta.value = ''; changed(); drawNone();
      } }, T('Atribuir', 'Assign', 'Asignar'));
      const noneBox = el('div', {});
      const drawNone = () => {
        noneBox.innerHTML = '';
        const none = preview().none;
        if (!none.length) return;
        const shown = none.slice(0, 60);
        noneBox.append(el('p', { class: 'small muted', style: 'margin:.5rem 0 .2rem' }, none.length + T(' time(s) sem sede', ' team(s) without a site', ' equipo(s) sin sede') + (none.length > 60 ? T(' — mostrando 60', ' — showing 60', ' — mostrando 60') : '') + ':'),
          el('div', { class: 'row', style: 'flex-wrap:wrap;gap:.3rem .8rem' }, ...shown.map((l) => { const s = mkSel(pending.get(l) || ''); s.addEventListener('change', () => { pending.set(l, s.value); changed(); }); return el('label', { class: 'small' }, l + ' ', s); })));
      };
      wrap.append(el('h4', { style: 'margin:.3rem 0' }, T('Atribuir times a uma sede', 'Assign teams to a site', 'Asignar equipos a una sede')),
        el('p', { class: 'small muted', style: 'margin:0 0 .3rem' }, T('A sede GRAVADA no time vence o "começa com". Time inscrito guarda a sede na inscrição (não some quando o time muda).', 'The site STORED on the team wins over "starts with". A registered team keeps the site in its registration (it does not vanish when the team changes).', 'La sede GRABADA en el equipo gana sobre "empieza con". Un equipo inscrito guarda la sede en su inscripción (no desaparece cuando el equipo cambia).')),
        ta, el('div', { class: 'row', style: 'gap:.4rem;margin:.3rem 0' }, el('span', { class: 'small' }, T('sede:', 'site:', 'sede:')), sel, go1, out), noneBox,
        el('p', { class: 'small muted', style: 'margin:.5rem 0 0' }, T('Pelo IP da máquina da prova: ', 'By the IP of the contest machine: ', 'Por la IP de la máquina de la competencia: '),
          go && has('maquinas') ? el('button', { class: 'btn ghost', type: 'button', onclick: () => go('maquinas', 'gate') }, T('Máquinas › Gate →', 'Machines › Gate →', 'Máquinas › Gate →'))
            : el('span', {}, T('Máquinas › Gate (módulo máquinas).', 'Machines › Gate (machines module).', 'Máquinas › Gate (módulo máquinas).'))));
      drawNone();
    };
    draw();
    return wrap;
  }

  // ---------- Intermediário ----------
  function viewRules() {
    const model = SM.toRules(tree).map((x) => (x.group ? { ...x, orig: x.name, sites: x.sites.map((s) => ({ ...s, orig: s.name })) } : { ...x, orig: x.name }));
    const box = el('div', {});
    const sync = () => { tree = SM.fromRules(model); changed(); };
    const RL = RULE_LABEL();
    const siteEditor = (s, onRemove) => {
      const nm = el('input', { value: s.name, placeholder: T('nome da sede', 'site name', 'nombre de la sede'), style: 'width:14rem' });
      nm.addEventListener('input', () => { s.name = nm.value; sync(); });
      nm.addEventListener('change', () => { const to = nm.value.trim();
        if (s.orig && to && to !== s.orig) { const mv = SM.renameAssignments(explicit, pending, s.orig, to); if (mv.length) moves.push({ from: s.orig, to, n: mv.length }); renames.push({ from: s.orig, to }); s.orig = to; }
        sync(); });
      const rl = el('div', { style: 'margin:.2rem 0 .2rem 1rem' });
      const drawRules = () => {
        rl.innerHTML = '';
        s.rules.forEach((r, j) => {
          const t = el('select', {}, ...SM.RULE_TYPES.map((k) => el('option', { value: k }, RL[k]))); t.value = r.t;
          const v = el('input', { value: (r.v || []).join(', '), style: 'width:18rem', placeholder: T('valores, vírgula separa', 'values, comma-separated', 'valores, separados por coma') });
          const err = el('span', { class: 'small', style: 'color:var(--err, #b00)' });
          const chk = () => { const e = SM.ruleError(r); err.textContent = e ? '⚠ ' + regexErrText(e) : ''; };
          t.addEventListener('change', () => { r.t = t.value; chk(); sync(); });
          v.addEventListener('input', () => { r.v = v.value.split(',').map((x) => x.trim()).filter(Boolean); chk(); sync(); });
          chk();
          rl.append(el('div', { class: 'row', style: 'gap:.3rem;margin:.15rem 0' }, t, v,
            el('button', { class: 'btn ghost', type: 'button', onclick: () => { s.rules.splice(j, 1); drawRules(); sync(); } }, '✕'), err));
        });
        rl.append(el('button', { class: 'btn ghost', type: 'button', style: 'padding:.05rem .4rem', onclick: () => { s.rules.push({ t: 'starts', v: [] }); drawRules(); } }, T('+ regra', '+ rule', '+ regla')));
      };
      drawRules();
      return el('div', { style: 'border-left:3px solid var(--line);padding-left:.5rem;margin:.4rem 0' },
        el('div', { class: 'row', style: 'gap:.3rem' }, nm, el('button', { class: 'btn ghost', type: 'button', title: T('remover sede', 'remove site', 'quitar sede'), onclick: onRemove }, '✕')), rl);
    };
    const draw = () => {
      box.innerHTML = '';
      model.forEach((x, i) => {
        if (!x.group) { box.append(siteEditor(x, () => { model.splice(i, 1); draw(); sync(); })); return; }
        const gn = el('input', { value: x.name, placeholder: T('nome do grupo (país, região)', 'group name (country, region)', 'nombre del grupo (país, región)'), style: 'width:14rem;font-weight:600' });
        gn.addEventListener('input', () => { x.name = gn.value; sync(); });
        const inner = el('div', { style: 'margin-left:1rem' }, ...x.sites.map((s, j) => siteEditor(s, () => { x.sites.splice(j, 1); draw(); sync(); })),
          el('button', { class: 'btn ghost', type: 'button', onclick: () => { x.sites.push({ name: '', rules: [], orig: '' }); draw(); } }, T('+ sede no grupo', '+ site in the group', '+ sede en el grupo')));
        box.append(el('div', { style: 'margin:.6rem 0' }, el('div', { class: 'row', style: 'gap:.3rem' }, el('span', {}, '📁'), gn,
          el('button', { class: 'btn ghost', type: 'button', title: T('remover grupo', 'remove group', 'quitar grupo'), onclick: () => { model.splice(i, 1); draw(); sync(); } }, '✕')), inner));
      });
      box.append(el('div', { class: 'row', style: 'gap:.4rem;margin:.4rem 0' },
        el('button', { class: 'btn ghost', type: 'button', onclick: () => { model.push({ name: '', group: false, rules: [], orig: '' }); draw(); } }, T('+ sede', '+ site', '+ sede')),
        el('button', { class: 'btn ghost', type: 'button', onclick: () => { model.push({ name: '', group: true, sites: [], orig: '' }); draw(); } }, T('+ grupo', '+ group', '+ grupo'))));
    };
    draw();
    const leaves = () => SM.toRules(tree).flatMap((x) => (x.group ? x.sites.map((s) => s.name) : [x.name]));
    view.append(box, assignBox(leaves));
  }

  // ---------- Avançado ----------
  let advEd = null;
  function viewTree() {
    advEd = makeRegionsEditor({ initial: tree });
    const upd = () => { const v = advEd.getValue(); if (Array.isArray(v)) { tree = v; changed(); } };
    advEd.el.addEventListener('input', upd); advEd.el.addEventListener('change', upd); advEd.el.addEventListener('click', () => setTimeout(upd, 0));
    const leaves = () => rgAssign(tree, []).nodes.filter((nd) => !nd.view && nd.name).map((nd) => nd.name);
    view.append(el('p', { class: 'small muted' }, T('Cada sede é um nome + uma regex no login (sem diferenciar maiúsculas; a regex mais funda que casa vence; a sede gravada no time vence a regex). "view": true marca um recorte (supersede, femininos) — ele agrupa times que já estão nas sedes e nunca é a sede de ninguém.',
      'Each site is a name + a regex on the login (case-insensitive; the deepest matching regex wins; the site stored on the team wins over the regex). "view": true marks a cut (super-site, women) — it groups teams that are already in the sites and is never anyone\'s site.',
      'Cada sede es un nombre + una regex sobre el usuario (sin distinguir mayúsculas; gana la regex más profunda que coincide; la sede grabada en el equipo gana sobre la regex). "view": true marca un recorte (supersede, femeninos) — agrupa equipos que ya están en las sedes y nunca es la sede de nadie.')),
      advEd.el, assignBox(leaves));
  }

  function drawModeButtons() {
    modeBar.innerHTML = '';
    MODES().forEach(([k, label, sub]) => {
      const why = k === 'simple' ? SM.fitSimple(tree) : (k === 'rules' ? SM.fitRules(tree) : '');
      const b = el('button', { class: 'btn' + (k === mode ? '' : ' ghost'), type: 'button', title: why ? T('Não cabe neste modo: ', 'Does not fit this mode: ', 'No cabe en este modo: ') + fitText(why) : sub,
        onclick: () => { if (why || k === mode) return; mode = k; drawMode(); } }, label);
      if (why) b.disabled = true;
      modeBar.append(b);
    });
  }
  function drawMode() {
    view.innerHTML = ''; advEd = null;
    drawModeButtons();
    if (mode === 'simple') viewSimple(); else if (mode === 'rules') viewRules(); else viewTree();
    renderPreview();
  }

  async function save(btn) {
    // regex fora do subconjunto seguro nunca vai (o servidor recusaria igual — 422 regions_invalid)
    if (advEd) { const bad = advEd.validate(); if (bad) { msg.className = 'small error-box'; msg.textContent = bad; return; } }
    const bad = rgAssign(tree, []).nodes.filter((nd) => nd.err);
    if (bad.length) { msg.className = 'small error-box'; msg.textContent = bad.map((nd) => nd.name + ': ' + regexErrText(nd.err)).join(' · '); return; }
    btn.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…', 'Guardando…');
    const body = { tree, mode, expect_sig: sig, assign: [...pending].map(([login, region]) => ({ login, region })), renames };
    try {
      const r = await apiPost('/contest/admin/regions?contest=' + enc(CONTEST), body, G);
      const f = r.failed || [], orf = r.orphan_refs || [];
      await load();
      // referência a sede que não existe mais (escopo do staff, gate de UA, sede do telão): avisar onde
      const WH = { staff: T('escopo do staff', 'staff scope', 'alcance del staff'), ua_gate: T('gate de navegador', 'browser gate', 'gate de navegador'), animeitor: T('telão (Animeitor)', 'big screen (Animeitor)', 'pantalla (Animeitor)') };
      msg.className = orf.length ? 'small error-box' : 'small';
      msg.textContent = T('✓ sedes salvas', '✓ sites saved', '✓ sedes guardadas')
        + (r.refs_renamed ? T(` — ${r.refs_renamed} configuração(ões) acompanharam o nome novo`, ` — ${r.refs_renamed} setting(s) followed the new name`, ` — ${r.refs_renamed} configuración(es) siguieron el nombre nuevo`) : '')
        + (f.length ? T(' — não atribuídos: ', ' — not assigned: ', ' — no asignados: ') + f.map((x) => x.login + ' (' + x.code + ')').join(', ') : '')
        + (orf.length ? T(' — ATENÇÃO, ainda apontam p/ sede que não existe: ', ' — WARNING, still pointing to a site that does not exist: ', ' — ATENCIÓN, todavía apuntan a una sede que no existe: ')
          + orf.map((o) => (WH[o.where] || o.where) + ' «' + o.name + '»' + (o.login ? ' (' + o.login + ')' : '')).join(', ') : '');
    } catch (e) {
      btn.disabled = false;
      msg.className = 'small error-box';
      if (e.code === 'regions_changed') msg.textContent = T('As sedes mudaram em outra aba ou pela CLI desde que você abriu. Recarregue e refaça.', 'The sites changed in another tab or through the CLI since you opened them. Reload and redo.', 'Las sedes cambiaron en otra pestaña o por la CLI desde que las abriste. Recarga y rehaz.');
      else if (e.code === 'regions_invalid' && e.data && Array.isArray(e.data.nodes) && e.data.nodes.length) msg.textContent = e.data.nodes.map((n) => n.path + ': ' + regexErrText(n.err)).join(' · ');
      else msg.textContent = e.message || T('falha', 'failed', 'fallido');
    }
  }

  async function load() {
    panel.innerHTML = '';
    panel.append(el('h2', {}, T('🏫 Sedes & escolas', '🏫 Sites & schools', '🏫 Sedes y escuelas')));
    let rg, mp, cfg;
    try {
      [rg, mp, cfg] = await Promise.all([
        apiGet('/contest/admin/regions?contest=' + enc(CONTEST), G),
        apiGet('/contest/admin/regions?contest=' + enc(CONTEST) + '&map=1', G),
        apiGet('/contest/admin/config?contest=' + enc(CONTEST), G),
      ]);
    } catch (e) { panel.append(el('div', { class: 'error-box' }, T('Falha: ', 'Failed: ', 'Error: ') + (e.message || T('erro', 'error', 'error')))); return; }
    tree = Array.isArray(rg.tree) ? rg.tree : []; origTree = JSON.stringify(tree); sig = rg.sig || ''; savedMode = rg.mode || '';
    users = (mp.map || []).map((u) => ({ login: u.login, explicit: (u.flag === 'x' || u.flag === 'o') ? (u.site || '') : '' }));
    explicit = new Map(users.filter((u) => u.explicit).map((u) => [u.login, u.explicit]));
    pending = new Map(); moves = []; renames = [];
    // o modo guardado, se a árvore ainda couber nele; senão o mais simples que couber (e dizemos)
    const fits = (m) => (m === 'simple' ? !SM.fitSimple(tree) : m === 'rules' ? !SM.fitRules(tree) : m === 'tree');
    mode = savedMode && fits(savedMode) ? savedMode : SM.simplestMode(tree);
    const note = savedMode && !fits(savedMode) ? el('p', { class: 'small notice' }, T('A árvore não cabe mais no modo guardado — abrindo no ', 'The tree no longer fits the stored mode — opening in ', 'El árbol ya no cabe en el modo guardado — abriendo en ')
      + MODES().find((x) => x[0] === mode)[1] + '.') : '';
    const saveBtn = el('button', { class: 'btn' }, T('Salvar sedes', 'Save sites', 'Guardar sedes'));
    saveBtn.addEventListener('click', () => save(saveBtn));
    panel.append(
      el('p', { class: 'small muted' }, T('A sede alimenta o filtro do placar, o escopo do staff (region:<nome> cobre o nó e o que está abaixo), as etiquetas, o gate de navegador por sede, a estatística e o telão. Escolha o modo que der conta do seu contest — dá para subir de modo a qualquer momento.',
        'The site feeds the scoreboard filter, the staff scope (region:<name> covers the node and what is below it), the badges, the per-site browser gate, the statistics and the big screen. Pick the mode that fits your contest — you can move up a mode at any time.',
        'La sede alimenta el filtro del marcador, el alcance del staff (region:<nombre> cubre el nodo y lo que está debajo), las etiquetas, el gate de navegador por sede, las estadísticas y la pantalla. Elige el modo que sirva para tu competencia — se puede subir de modo en cualquier momento.')),
      note, modeBar, view, prev, el('div', { class: 'row', style: 'margin-top:.6rem' }, saveBtn), msg);
    drawMode();
    // países e escolas (regex → bandeira/universidade) — salvar próprio, como antes
    const logins = users.map((u) => u.login);
    const teamsEd = await makeTeamsEditor({ initial: cfg.teams_meta || [], logins });
    const tmsg = el('span', { class: 'small' });
    const tsave = el('button', { class: 'btn ghost' }, T('Salvar países e escolas', 'Save countries and schools', 'Guardar países y escuelas'));
    tsave.addEventListener('click', async () => {
      tsave.disabled = true; tmsg.textContent = T('Salvando…', 'Saving…', 'Guardando…');
      try { await apiPost('/contest/admin/config?contest=' + enc(CONTEST), { teams_meta: teamsEd.getValue() }, G); tmsg.textContent = T('✓ salvo', '✓ saved', '✓ guardado'); }
      catch (e) { tmsg.textContent = e.message || T('falha', 'failed', 'fallido'); }
      tsave.disabled = false;
    });
    panel.append(el('h3', { style: 'margin:1.4rem 0 .2rem' }, T('🏳️ Países e escolas (por regex no login)', '🏳️ Countries and schools (by login regex)', '🏳️ Países y escuelas (por regex de login)')),
      el('p', { class: 'small muted', style: 'margin:0 0 .3rem' }, T('Preenche bandeira/universidade dos times que casarem — conveniência de carga; o valor por time pode ser editado em 👥 Times.',
        'Fills flag/university for matching teams — a bulk convenience; the per-team value can be edited in 👥 Teams.',
        'Completa bandera/universidad de los equipos que coincidan — una conveniencia masiva; el valor por equipo se puede editar en 👥 Equipos.')),
      teamsEd.el, el('div', { class: 'row', style: 'margin-top:.4rem;gap:.5rem' }, tsave, tmsg));
    panel.append(await timeOverridesPanel(CONTEST, G));
  }
  return { panel, load };
}
