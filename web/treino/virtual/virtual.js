// treino/virtual/virtual.js — PARTICIPAÇÃO VIRTUAL: refazer um contest encerrado contra o placar
// oficial, no tempo de quem participa. COM A RUN LARGADA a página tem a cara do contest (10/11/2026; relato: "não achei
// os tempos limites"; desenho aprovado pelo Ribas em .claude/prototipos/2026-11-10/virtual): abas Prova (avisos,
// arquivos da prova, sanfona com TL + enunciado + editor) · Placar (com o FREEZE relativo) · Clarifications & avisos (as
// PÚBLICAS no tempo relativo — o servidor corta) · Minhas submissões · Ajuda. Três telas na MESMA página:
//   largada  — regras de honra, duração, "começar agora"/agendar, regra de desistência
//   arena    — relógio, problemas (enunciado da rota pública /treino/problem), envio, submissões,
//              placar com os times oficiais como "fantasmas" + virtuais anteriores + você
//   replay   — sem run (ou depois dela): o placar com um controle de tempo, p/ assistir à prova
// O placar é montado AQUI (shared/virtual-board.js) a partir do feed; a verdade sobre a MINHA run
// vem do servidor (/treino/virtual/run). Atualização EM LUGAR: o relógio anda a cada segundo, o
// placar só é refeito quando uma run nova "acontece" ou o meu estado muda.
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { status, fileToBase64, textToBase64 } from '/shared/auth.js';
import { el, verdictClass, isPending, fmtCountdown } from '/shared/ui.js';
import { T, uiLocale } from '/shared/i18n.js';
import { indexFeed, runsUpTo, boardAt, myRow, sliceVirtualPlaces, pickVirtuals } from '/shared/virtual-board.js';
import { renderICPC } from '/contest/score/score-icpc.js';
import * as F from '/contest/score/score-filters.js';   // a MESMA lógica de filtro do placar oficial
import { flagName, flagNamesReady } from '/shared/flags.js';
import { pickStmtLang, makeStmtLangChips, setChipsActive, rememberStmtLang, stmtHtmlLang } from '/shared/statement-langs.js';
import { decorateSamples } from '/shared/statement-samples.js';
import { langById, DEFAULT_SUBMIT_LANGUAGES, extCanon } from '/shared/languages.js';
import { makeSubmitFlow, attachSubmitButton, lastSubKey } from '/shared/submit-ux.js';
import { createEditor } from '/shared/editor.js';
import { skeletonFor, isSkeleton, docOnLangChange } from '/shared/editor-skeleton.js';
import { tlParts } from '/shared/tl-chips.js';   // chips de TL: a MESMA regra do contest e do treino

const CID = new URLSearchParams(location.search).get('c') || '';
const enc = encodeURIComponent;
const A = { contest: 'treino', auth: true };
const $ = (id) => document.getElementById(id);
const logged = () => !!getToken('treino');

let info = null, me = null, feed = null, idx = null, virtuals = [], balloons = {}, problems = null, who = null, whoName = '';
let skew = 0;                 // relógio do servidor − o daqui (ms)
let lastSig = '', replayT = Infinity, playing = null;
let lastPaint = 0, lastMine = '';
// ---- filtros do placar: os MESMOS do placar oficial (coorte, bandeira, universidade, sede, busca)
// + "Virtuais" (todos | só o meu | nenhum). Estado lembrado por contest no navegador.
let regions = [], teamsMeta = [], teamsDir = {};
let vRops = [];     // opções de sede (com os logins de cada nó) — montadas no renderFilters, do placar final inteiro
const FKEY = 'moj_virtual_flt_' + CID;
let flt = { view: '', country: '', school: '', region: null, q: '', virt: 'all' };
try { flt = { ...flt, ...(JSON.parse(localStorage.getItem(FKEY) || '{}')) }; } catch { /* storage indisponível */ }
const saveFlt = () => { try { localStorage.setItem(FKEY, JSON.stringify(flt)); } catch { /* idem */ } };
// ---- "MEUS ESCOLHIDOS": virtuais que aparecem SEMPRE (amigos p/ se comparar). UMA lista por CONTA
// (/treino/virtual/friends — acompanha a pessoa em qualquer máquina); sem login, fica no navegador.
const LKEY = 'moj_virtual_friends';
let friends = new Set();
const localFriends = () => { try { const a = JSON.parse(localStorage.getItem(LKEY) || '[]'); return Array.isArray(a) ? a.filter((x) => typeof x === 'string') : []; } catch { return []; } };
async function loadFriends() {
  const loc = localFriends();
  if (!logged()) { friends = new Set(loc); return; }
  try {
    let d = await apiGet('/treino/virtual/friends', A);
    if (loc.length) {                       // escolheu sem login e depois entrou: mescla UMA vez
      try { d = await apiPost('/treino/virtual/friends', { add: loc }, A); localStorage.removeItem(LKEY); } catch { /* fica p/ a próxima */ }
    }
    friends = new Set(d.logins || []);
  } catch { friends = new Set(loc); }
}
async function setFriend(login, on) {
  if (!login) return;
  if (on) friends.add(login); else friends.delete(login);
  paintBoard(true); paintFriendsUI();       // resposta na hora; o servidor confirma em seguida
  if (!logged()) { try { localStorage.setItem(LKEY, JSON.stringify([...friends])); } catch { /* storage indisponível */ } return; }
  try { const d = await apiPost('/treino/virtual/friends', on ? { add: [login] } : { remove: [login] }, A); friends = new Set(d.logins || []); }
  catch (e) { if (on) friends.delete(login); else friends.add(login); alert(e.message); }
  paintBoard(true); paintFriendsUI();
}
function mineChanged(vs) { const m = vs.find((v) => v.you); const k = m ? JSON.stringify((m.runs || []).map((r) => [r[1], r[2]])) : ''; const ch = k !== lastMine; lastMine = k; return ch; }
const srvNow = () => (Date.now() + skew) / 1000;

// o relógio da virtual é o MESMO cronômetro da prova (shared/ui.js): dias a partir de 24 h — o agendamento vai
// até 7 dias e um contest de meses pode ser refeito; a cópia local somava as horas ("1447:04:14")
const hms = fmtCountdown;
const mmss = (s) => Math.floor(s / 60) + ':' + String(Math.floor(s % 60)).padStart(2, '0');
function b64utf8(b64) { try { const bin = atob(b64 || ''); return new TextDecoder('utf-8').decode(Uint8Array.from(bin, (c) => c.charCodeAt(0))); } catch { return ''; } }
function setMe(m) { me = m; if (m && m.now) skew = m.now * 1000 - Date.now(); }

// ---------------------------------------------------------------- cabeçalho (relógio + situação)
let clockEl = null, statEl = null, actEl = null, headState = '';
function buildHead() {
  const st = me ? me.state : 'anon';
  if (headState === st && clockEl) return;
  headState = st;
  clockEl = el('div', { class: 'vr-clock' }); statEl = el('div', { class: 'vr-stat' }); actEl = el('div', { class: 'row' });
  const box = $('vhead'); box.innerHTML = '';
  box.append(el('div', { class: 'vr-head' },
    el('div', {}, el('div', { class: 'small muted' }, T('Participação virtual', 'Virtual participation', 'Participación virtual')), el('h1', {}, info.title)),
    el('div', { class: 'spacer' }), clockEl), statEl, actEl);
  if (st === 'running') {
    actEl.append(el('button', { class: 'btn ghost', onclick: finish }, T('Encerrar agora', 'Finish now', 'Terminar ahora')));
  }
}
function paintHead() {
  buildHead();
  const st = me ? me.state : 'anon';
  if (st === 'running') {
    const left = me.end - srvNow();
    clockEl.textContent = hms(left); clockEl.classList.toggle('low', left < 600);
    if (left <= 0) refreshRun();
  } else if (st === 'scheduled') clockEl.textContent = T('começa em ', 'starts in ', 'empieza en ') + hms(me.start - srvNow());
  else if (st === 'judging') clockEl.textContent = T('aguardando os últimos veredictos…', 'waiting for the last verdicts…', 'esperando los últimos veredictos…');
  else clockEl.textContent = T('duração ', 'duration ', 'duración ') + hms(info.duration);
  if (st === 'scheduled' && me.start - srvNow() <= 0) refreshRun();
  // botão Desistir aparece/some conforme a regra (≤ 15 min OU 0 AC) — o servidor é quem decide
  const want = st === 'running' && me.can_discard;
  const has = actEl.querySelector('[data-k=discard]');
  if (want && !has) actEl.append(el('button', { class: 'btn ghost danger', 'data-k': 'discard', onclick: discard,
    title: T('Descarta esta participação sem gravar no placar', 'Drops this participation without recording it', 'Descarta esta participación sin registrarla') },
    T('Desistir (não grava)', 'Give up (not recorded)', 'Desistir (no se registra)') + ' · ' + T('restam ', 'left: ', 'quedan: ') + me.discards_left));
  if (!want && has) has.remove();
}
function paintStat(parsed) {
  if (!statEl) return;
  const r = parsed ? myRow(parsed) : null;
  statEl.innerHTML = '';
  if (!r) return;
  statEl.append(
    el('span', {}, T('posição ', 'place ', 'posición '), el('b', {}, String(r.gplace)), el('span', { class: 'muted small' }, ' / ' + parsed.teams.filter((x) => !x.guest).length)),
    el('span', {}, T('resolvidos ', 'solved ', 'resueltos '), el('b', {}, r.total)),
    el('span', {}, T('penalidade ', 'penalty ', 'penalidad '), el('b', {}, r.penalty)),
    me && me.pending ? el('span', { class: 'muted' }, T('julgando: ', 'judging: ', 'evaluando: ') + me.pending) : '');
}

// ---------------------------------------------------------------- largada
function renderStart() {
  const box = $('vstart'); box.innerHTML = ''; box.classList.remove('hidden');
  const h = Math.floor(info.duration / 3600), m = Math.round(info.duration % 3600 / 60);
  box.append(el('h2', {}, T('Refazer esta prova', 'Redo this contest', 'Rehacer esta competencia')),
    el('p', {}, T(`${info.problems_count} problemas · ${h} h ${m} min · regras ICPC, penalidade de ${info.penalty_minutes} min por erro.`,
      `${info.problems_count} problems · ${h} h ${m} min · ICPC rules, ${info.penalty_minutes} min penalty per wrong try.`,
      `${info.problems_count} problemas · ${h} h ${m} min · reglas ICPC, penalidad de ${info.penalty_minutes} min por intento fallido.`)),
    el('p', {}, T('Você compete contra o placar oficial: os times aparecem resolvendo os problemas no mesmo minuto em que resolveram na prova de verdade. No fim, a sua linha fica gravada no placar virtual, marcada como virtual.',
      'You compete against the official scoreboard: the teams solve the problems at the same minute they did in the real contest. At the end your row is recorded on the virtual scoreboard, marked as virtual.',
      'Compites contra el marcador oficial: los equipos aparecen resolviendo los problemas en el mismo minuto en que los resolvieron en la competencia real. Al final, tu fila queda registrada en el marcador virtual, marcada como virtual.')));
  if (!logged()) { box.append(el('p', {}, el('a', { class: 'btn', href: '/treino/?next=' + enc(location.pathname + location.search) }, T('Entrar no Treino Livre para participar', 'Log into Free Training to take part', 'Inicia sesión en el Entrenamiento libre para participar')))); return; }
  if (me.state === 'forbidden') { box.append(el('p', { class: 'muted' }, T('Contas de papel (admin, juiz, staff…) não participam. Use a sua conta pessoal.', 'Role accounts (admin, judge, staff…) do not take part. Use your personal account.', 'Las cuentas de rol (admin, juez, staff…) no participan. Usa tu cuenta personal.'))); return; }
  const fin = me.discards >= info.rules.max_discards;
  const mins = Math.round(info.rules.grace_s / 60);
  box.append(el('ul', { class: 'vr-rules' },
    el('li', {}, T('Cada conta faz a participação virtual de uma prova UMA vez.', 'Each account takes the virtual participation of a contest ONCE.', 'Cada cuenta hace la participación virtual de una competencia UNA sola vez.')),
    el('li', {}, T('Não participe se já viu os problemas ou as soluções, e não consulte editorial, código de outras pessoas nem ajuda durante a prova.', 'Do not take part if you have already seen the problems or solutions, and do not use the editorial, other people\'s code or help during the contest.', 'No participes si ya viste los problemas o las soluciones, y no consultes el editorial, el código de otras personas ni ayuda durante la competencia.')),
    el('li', {}, T('Faça a prova inteira: não use o virtual para resolver um problema só — para isso existe o Treino Livre.', 'Do the whole contest: do not use virtual to solve a single problem — Free Training is for that.', 'Haz la competencia completa: no uses el virtual para resolver un solo problema — para eso está el Entrenamiento libre.')),
    el('li', {}, fin
      ? el('b', {}, T('Esta é a sua largada DEFINITIVA: não há mais como desistir — o resultado será gravado.', 'This is your FINAL start: you cannot give up any more — the result will be recorded.', 'Este es tu inicio DEFINITIVO: ya no puedes desistir — el resultado se registrará.'))
      : T(`Você pode DESISTIR sem gravar nada nos primeiros ${mins} minutos, ou enquanto não tiver nenhum problema aceito. Desistir devolve a tentativa — no máximo ${info.rules.max_discards} vezes (restam ${me.discards_left}); depois disso a largada é definitiva. Terminar o tempo sem nenhum aceito conta como desistência.`,
          `You may GIVE UP without recording anything in the first ${mins} minutes, or while you have no accepted problem. Giving up returns the attempt — at most ${info.rules.max_discards} times (${me.discards_left} left); after that the start is final. Running out of time with nothing accepted counts as giving up.`,
          `Puedes DESISTIR sin registrar nada en los primeros ${mins} minutos, o mientras no tengas ningún problema aceptado. Desistir devuelve el intento — como máximo ${info.rules.max_discards} veces (quedan ${me.discards_left}); después de eso el inicio es definitivo. Terminar el tiempo sin ningún aceptado cuenta como desistir.`)),
    me.official ? el('li', { class: 'muted' }, T('Você competiu nesta prova oficialmente — a sua linha virtual sai marcada com isso.', 'You competed in this contest officially — your virtual row is marked accordingly.', 'Competiste en esta competencia oficialmente — tu fila virtual queda marcada así.')) : ''));
  const acc = el('input', { type: 'checkbox', id: 'vacc' });
  const at = el('input', { type: 'datetime-local' });
  const err = el('div', { class: 'small', style: 'color:#c0392b' });
  const go = async (when) => {
    err.textContent = '';
    if (!acc.checked) { err.textContent = T('Marque que leu e aceita as regras.', 'Tick that you have read and accept the rules.', 'Marca que leíste y aceptas las reglas.'); return; }
    const body = { contest: CID, action: 'start', accept: true };
    if (when) { const ep = Math.floor(new Date(at.value).getTime() / 1000); if (!ep) { err.textContent = T('Escolha data e hora.', 'Pick a date and time.', 'Elige una fecha y hora.'); return; } body.at = ep; }
    else if (!confirm(T('Começar AGORA? O relógio parte imediatamente.', 'Start NOW? The clock starts immediately.', '¿Empezar AHORA? El reloj arranca de inmediato.'))) return;
    try { const d = await apiPost('/treino/virtual/run', body, A); setMe(d.me); await enter(); } catch (e) { err.textContent = e.message; }
  };
  box.append(el('p', {}, el('label', {}, acc, ' ', T('Li e aceito as regras acima.', 'I have read and accept the rules above.', 'Leí y acepto las reglas de arriba.'))),
    el('div', { class: 'row', style: 'gap:.6rem;flex-wrap:wrap;align-items:center' },
      el('button', { class: 'btn', onclick: () => go(false) }, T('Começar agora', 'Start now', 'Empezar ahora')),
      el('span', { class: 'muted' }, T('ou agendar para', 'or schedule for', 'o programar para')), at,
      el('button', { class: 'btn ghost', onclick: () => go(true) }, T('Agendar', 'Schedule', 'Programar'))), err);
}
function renderScheduled() {
  const box = $('vstart'); box.innerHTML = ''; box.classList.remove('hidden');
  box.append(el('h2', {}, T('Participação agendada', 'Participation scheduled', 'Participación programada')),
    el('p', {}, T('Começa em ', 'Starts at ', 'Empieza el ') + new Date(me.start * 1000).toLocaleString(uiLocale()) + T('. Deixe esta página aberta ou volte na hora.', '. Keep this page open or come back on time.', '. Deja esta página abierta o vuelve a tiempo.')),
    el('button', { class: 'btn ghost', onclick: async () => {
      if (!confirm(T('Cancelar o agendamento?', 'Cancel the schedule?', '¿Cancelar la programación?'))) return;
      try { const d = await apiPost('/treino/virtual/run', { contest: CID, action: 'cancel' }, A); setMe(d.me); await enter(); } catch (e) { alert(e.message); }
    } }, T('Cancelar agendamento', 'Cancel schedule', 'Cancelar programación')));
}

async function discard() {
  if (!confirm(T('Desistir desta participação? Nada será gravado no placar e você poderá largar de novo (restam ' + me.discards_left + ' desistências). As submissões continuam no seu histórico do treino.',
    'Give up this participation? Nothing is recorded and you may start again (' + me.discards_left + ' give-ups left). The submissions stay in your training history.',
    '¿Abandonar esta participación? No se registra nada en el marcador y podrás empezar de nuevo (te quedan ' + me.discards_left + ' abandonos). Los envíos siguen en tu historial de entrenamiento.'))) return;
  try { const d = await apiPost('/treino/virtual/run', { contest: CID, action: 'discard' }, A); setMe(d.me); await enter(); } catch (e) { alert(e.message); }
}
async function finish() {
  const zero = !me.solved && !me.final;
  if (!confirm(zero
    ? T('Encerrar agora sem nenhum problema aceito conta como DESISTÊNCIA (nada é gravado). Encerrar?', 'Finishing now with nothing accepted counts as GIVING UP (nothing is recorded). Finish?', 'Terminar ahora sin nada aceptado cuenta como DESISTIR (no se registra nada). ¿Terminar?')
    : T('Encerrar a participação agora? O resultado será gravado e não dá para voltar.', 'Finish the participation now? The result is recorded and cannot be undone.', '¿Terminar la participación ahora? El resultado se registra y no se puede deshacer.'))) return;
  try { const d = await apiPost('/treino/virtual/run', { contest: CID, action: 'finish' }, A); setMe(d.me); await enter(); } catch (e) { alert(e.message); }
}

// ---------------------------------------------------------------- arena: problemas (TL + enunciado + editor)
const probBox = {};          // id -> {det, mark}
function renderProblems() {
  const box = $('vprobs'); if (box.dataset.built) { markProblems(); return; }
  box.dataset.built = '1'; box.innerHTML = '';
  problems.forEach((p) => {
    const mark = el('span', {});
    const body = el('div', { class: 'vr-pbody' });
    const det = el('details', { class: 'vr-prob' }, el('summary', {}, el('span', { class: 'lt' }, p.letter), p.name, ' ', mark), body);
    det.addEventListener('toggle', () => { if (det.open && !body.dataset.loaded) loadStatement(p, body); });
    probBox[p.id] = { det, mark };
    box.append(det);
  });
  markProblems();
}
function markProblems() {
  if (!me || !problems) return;
  problems.forEach((p, pi) => {
    const rs = (me.runs || []).filter((r) => r[1] === pi);
    const m = probBox[p.id] && probBox[p.id].mark; if (!m) return;
    const ac = rs.some((r) => r[2] === 'Y'), bad = rs.filter((r) => r[2] === 'N').length, pend = rs.some((r) => r[2] === '?');
    m.className = ac ? 'ok' : (bad ? 'no' : 'muted');
    m.textContent = ac ? '✓' : (pend ? '…' : (bad ? '✗ ' + bad : ''));
  });
}
// as linguagens da PROVA (o servidor já resolveu a whitelist do contest/problema); vazio = as normais
const probLangs = (p) => ((p.languages && p.languages.length) ? p.languages.map(langById) : DEFAULT_SUBMIT_LANGUAGES);
async function loadStatement(p, body) {
  body.dataset.loaded = '1'; body.innerHTML = '';
  // TEMPO-LIMITE por linguagem — o que JULGA a submissão virtual (o do treino, /treino/virtual/problems)
  const tlp = tlParts(p, (p.languages && p.languages.length) ? probLangs(p) : null);
  if (tlp.length) body.append(el('div', { class: 'tl-block' }, ...tlp));
  const stmtCol = el('div', {}, el('span', { class: 'muted small' }, T('carregando o enunciado…', 'loading the statement…', 'cargando el enunciado…')));
  const edCol = el('div', {});
  body.append(el('div', { class: 'vr-cols' }, stmtCol, edCol));
  edCol.append(submitBox(p));
  let pj;
  try { pj = await apiGet('/treino/problem?id=' + enc(p.id), A); } catch (e) { stmtCol.replaceChildren(el('p', { class: 'muted' }, e.message)); delete body.dataset.loaded; return; }
  const langs = Array.isArray(pj.statement_langs) && pj.statement_langs.length ? pj.statement_langs : ['pt'];
  const stmt = el('div', { class: 'statement-content' });
  const show = (lang) => {
    const tr = (lang !== 'pt' && pj.statements && pj.statements[lang]) || null;
    const html = b64utf8((tr && tr.html_b64) || pj.statement_html_b64 || '');
    const doc = new DOMParser().parseFromString(html, 'text/html');
    stmt.innerHTML = doc.body ? doc.body.innerHTML : html; stmt.lang = stmtHtmlLang(lang);
    decorateSamples(stmt);
  };
  let cur = pickStmtLang(langs, 'pt');
  stmtCol.replaceChildren();
  if (langs.length > 1) {
    const chips = makeStmtLangChips(langs, cur, (l) => { cur = l; rememberStmtLang(l); setChipsActive(chips, l); show(l); });
    stmtCol.append(chips);
  }
  show(cur);
  stmtCol.append(stmt);
}
// ENVIO: editor embutido (como no contest e no treino) + arquivo. Vai ao /submit do treino com `virtual:<cid>` —
// o servidor exige a run rodando, o problema da prova e a linguagem do contest.
function submitBox(p) {
  if (!me || me.state !== 'running') return el('p', { class: 'muted small' }, T('A participação terminou: o envio está fechado.', 'The participation has ended: submitting is closed.', 'La participación terminó: el envío está cerrado.'));
  const langs = probLangs(p);
  const cfg = { functionLangs: p.function_langs || [] };
  let cur = langs[0].id, editor = null;
  const sel = el('select', {}, ...langs.map((l) => el('option', { value: l.id }, l.label)));
  const mount = el('div');
  const box = el('div', { class: 'editor-box', style: 'height:420px' }, mount);
  const exts = [...new Set(langs.flatMap((l) => (l.exts && l.exts.length) ? l.exts : [l.id]))].map((x) => '.' + x);
  const file = el('input', { type: 'file', class: 'hidden', accept: exts.join(',') });
  const fname = el('span', { class: 'muted small' });
  file.addEventListener('change', () => { fname.textContent = file.files[0] ? file.files[0].name : ''; });
  const steps = el('span', { class: 'submit-steps' });
  const btn = el('button', { class: 'btn', type: 'button' }, T('Enviar', 'Submit', 'Enviar') + ' ' + p.letter);
  (async () => {
    editor = await createEditor(mount, { doc: skeletonFor(cur, cfg), cm: langById(cur).cm, tab: 'indent' });
    sel.addEventListener('change', async () => {
      const txt = docOnLangChange(editor ? editor.getValue() : '', sel.value, cfg); cur = sel.value; mount.innerHTML = '';
      editor = await createEditor(mount, { doc: txt, cm: langById(cur).cm, tab: 'indent' });
    });
  })();
  const flow = makeSubmitFlow({ key: lastSubKey('virtual:' + CID, who || '', p.id),
    send: (payload) => apiPost('/submit?contest=treino', { problem_id: p.id, virtual: CID, ...payload }, A) });
  attachSubmitButton(flow, btn, steps, {
    label: () => T('Enviar', 'Submit', 'Enviar') + ' ' + p.letter,
    describe: (r) => langById(r.prep.lang).label,
    hint: () => T('acompanhe em Minhas submissões', 'follow it in My submissions', 'síguelo en Mis envíos'),
    prepare: async () => {
      const f = file.files && file.files[0];
      if (f) {
        const fext = f.name.includes('.') ? f.name.split('.').pop() : '';
        if (p.languages && p.languages.length && !p.languages.map(extCanon).includes(extCanon(fext))) {
          throw new Error(T(`Esta prova só aceita: ${p.languages.join(', ')} — o arquivo .${fext || '?'} não pode ser enviado.`,
            `This contest only accepts: ${p.languages.join(', ')} — the .${fext || '?'} file cannot be submitted.`,
            `Esta competencia solo acepta: ${p.languages.join(', ')} — el archivo .${fext || '?'} no se puede enviar.`));
        }
        return { payload: { filename: f.name, code_b64: await fileToBase64(f), source: 'file' }, lang: extCanon(fext) };
      }
      const txt = editor ? editor.getValue() : '';
      if (!txt.trim()) throw new Error(T('Escreva o seu código no editor ou escolha um arquivo.', 'Write your code in the editor or choose a file.', 'Escribe tu código en el editor o elige un archivo.'));
      if (isSkeleton(txt, cfg)) throw new Error(T('Você ainda não alterou o código inicial: escreva a sua solução.', 'You have not changed the starter code yet: write your solution.', 'Todavía no cambiaste el código inicial: escribe tu solución.'));
      return { payload: { filename: 'solution.' + cur, code_b64: textToBase64(txt), source: 'web' }, lang: cur };
    },
    onSent: async () => { file.value = ''; fname.textContent = ''; await refreshRun(); },
  });
  return el('div', { class: 'editor-wrap' },
    el('div', { class: 'editor-bar' }, el('label', { class: 'small' }, T('Linguagem: ', 'Language: ', 'Lenguaje: ')), sel,
      el('a', { class: 'small', href: '/treino/ajuda/', target: '_blank', rel: 'noopener' }, T('📖 Como enviar', '📖 How to submit', '📖 Cómo enviar'))),
    box,
    el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap;margin-top:.4rem' }, btn,
      el('button', { class: 'btn ghost', type: 'button', onclick: () => file.click() }, T('ou enviar arquivo…', 'or submit a file…', 'o enviar archivo…')), file, fname, steps));
}
function renderSubs() {
  const box = $('vsubs'); const runs = (me && me.runs) || [];
  const sig = JSON.stringify(runs); if (box.dataset.sig === sig) return; box.dataset.sig = sig;
  box.innerHTML = '';
  if (!runs.length) { box.append(el('span', { class: 'muted small' }, T('Nenhuma submissão ainda.', 'No submissions yet.', 'Aún no hay envíos.'))); return; }
  box.append(el('table', { class: 'moj' },
    el('thead', {}, el('tr', {}, el('th', { class: 'n' }, T('tempo', 'time', 'tiempo')), el('th', {}, T('problema', 'problem', 'problema')), el('th', {}, T('linguagem', 'language', 'lenguaje')), el('th', {}, T('veredicto', 'verdict', 'veredicto')))),
    el('tbody', {}, ...runs.slice().reverse().map((r) => el('tr', {},
      el('td', { class: 'n' }, mmss(r[0])), el('td', {}, problems && problems[r[1]] ? problems[r[1]].letter : String(r[1])),
      el('td', {}, (r[5] || '').toLowerCase()),
      el('td', {}, el('span', { class: 'verdict ' + verdictClass(r[3] || '') }, isPending(r[3] || '') ? T('julgando…', 'judging…', 'evaluando…') : (r[3] || ''))))))));
}

// ---------------------------------------------------------------- placar
function curT() {
  if (me && me.state === 'running') return Math.min(srvNow() - me.start, info.duration);
  if (me && me.state === 'scheduled') return 0;
  return replayT;
}
// Pintura pedida pela PESSOA (arrastar a barra do replay): sempre acontece, no máximo UMA por quadro
// (requestAnimationFrame) — arrastando, as posições intermediárias são puladas e a ÚLTIMA é pintada.
// O teto de 5 s do paintBoard é só p/ o relógio da run ao vivo: aplicado à barra, ele descartava a
// posição onde a pessoa soltou, e o placar só "andava" na interação SEGUINTE, mostrando a anterior
// (relato do Roberto Sales, 19/09/2026: "na segunda interação carregava o conteúdo da primeira").
let paintQueued = false;
function paintSoon() {
  if (paintQueued) return;
  paintQueued = true;
  (window.requestAnimationFrame || ((f) => setTimeout(f, 16)))(() => { paintQueued = false; paintBoard(false, true); });
}
function paintBoard(force, user) {
  if (!feed) return;
  const t = curT();
  const live = me && (me.state === 'running' || me.state === 'judging');
  // "Virtuais:" todos | só o meu | nenhum — a linha de uma run AO VIVO aparece sempre
  const vs = pickVirtuals(virtuals.filter((v) => !(live && v.you)), flt.virt, friends);
  if (live) vs.push({ login: who || T('você', 'you', 'tú'), name: whoName || who || T('você', 'you', 'tú'), runs: me.runs || [], you: true });
  const sig = JSON.stringify(flt) + '|' + [...friends].sort().join(',') + '|' + runsUpTo(idx, t) + '|' + vs.map((v) => v.login + ':' + (v.runs || []).filter((r) => r[0] <= t).map((r) => r[1] + r[2]).join('')).join(',') + '|' + (t === Infinity);
  if (!force && sig === lastSig) return;
  // placar de 2000 times = tabela de 2000 linhas: o MOTOR custa ~8 ms, o DOM é que pesa. No pico de
  // uma prova grande "acontece" uma run por segundo — redesenha no máximo a cada 5 s (o relógio e a
  // minha situação seguem ao segundo; mudança MINHA força o redesenho).
  const nowMs = Date.now();
  if (!force && !user && playing === null && nowMs - lastPaint < 5000 && !mineChanged(vs)) return;
  lastPaint = nowMs; lastSig = sig;
  // FREEZE relativo (feed.freeze_rel, o freeze preservado pelo "Encerrar evento"): com a run rodando ou esperando o último
  // veredicto (judging) — só a run FINALIZADA abre o placar (a regra do servidor, vr_clock)
  const fz = (me && (me.state === 'running' || me.state === 'judging') && Number.isFinite(feed.freeze_rel)) ? feed.freeze_rel : null;
  const parsed = boardAt(feed, idx, vs, t, balloons, { teamOk: viewFn(), freeze: fz });
  paintFreeze(parsed.frozenAt);
  F.applyTeamsDir(parsed, teamsDir, CID); F.applyTeamsMeta(parsed, teamsMeta);   // sede, brasão, bandeira por regra
  const keep = keepFn();
  if (keep) sliceVirtualPlaces(parsed, keep);      // a virtual acompanha a renumeração do recorte
  const table = renderICPC(parsed, { style: 'icon', regionFn: keep, teamExtra: pinButton });
  const cnt = $('fCount');
  if (cnt) { const sh = Number(table.dataset.shown || 0), tot = Number(table.dataset.total || 0);
    cnt.textContent = (sh === tot && !keep) ? T(`${tot} linhas`, `${tot} rows`, `${tot} filas`) : T(`Mostrando ${sh} de ${tot}`, `Showing ${sh} of ${tot}`, `Mostrando ${sh} de ${tot}`) + (keep ? T(' · ★ = 1º do recorte', ' · ★ = 1st in selection', ' · ★ = 1º del recorte') : ''); }
  const box = $('vboard'); const y = window.scrollY;
  box.replaceChildren(el('div', { class: 'board-wrap' }, table));
  window.scrollTo(0, y);
  paintStat(parsed);
}
function paintFreeze(at) {
  const box = $('vfreeze'); if (!box) return;
  if (at === null || at === undefined) { box.classList.add('hidden'); box.innerHTML = ''; return; }
  const sig = String(at); if (box.dataset.sig === sig && !box.classList.contains('hidden')) return; box.dataset.sig = sig;
  box.replaceChildren('❄️ ', el('b', {}, T('Placar congelado aos ', 'Scoreboard frozen at ', 'Marcador congelado a los ') + hms(at) + T(', como na prova.', ', as in the contest.', ', como en la competencia.')), ' ',
    T('Os outros não mostram o que fizeram depois disso (n/-? = tentativas escondidas); as suas submissões continuam aparecendo. Descongela quando a sua participação terminar.',
      'The others do not show what they did after that (n/-? = hidden attempts); your submissions keep showing. It unfreezes when your participation ends.',
      'Los demás no muestran lo que hicieron después (n/-? = intentos ocultos); tus envíos siguen apareciendo. Se descongela cuando termina tu participación.'));
  box.classList.remove('hidden');
}
// COORTE recorta no MOTOR (posição e ★ saem como no placar próprio da visão); o resto é recorte de LINHA
function viewFn() {
  if (!flt.view) return null;
  if (flt.view === '!guests') return (tm) => !tm[5];
  return (tm) => (tm[6] || '') === flt.view;
}
// predicado de linha: bandeira/universidade/sede (score-filters) + busca. A MINHA linha fica sempre.
// Os outros virtuais obedecem ao que TÊM (bandeira/universidade/busca) e IGNORAM a sede: virtual não
// fez a prova em sede nenhuma, e quem filtra uma sede quer justamente se comparar com ela — os
// virtuais seguem na tela (decisão do Ribas, 2026-09-18; quem não os quer usa "Virtuais: nenhum").
function keepFn() {
  // a sede guardada ({name, regex}) resolvida p/ a opção da árvore (com os logins do nó — regra única de sedes)
  const reg = flt.region ? (F.regionResolve(vRops, flt.region) || flt.region) : null;
  const rf = F.rowFilter({ region: reg, country: flt.country, school: flt.school });
  const rfv = F.rowFilter({ region: null, country: flt.country, school: flt.school });   // p/ linha virtual: sem a sede
  const q = (flt.q || '').trim().toLowerCase();
  if (!rf && !q) return null;
  const hit = (t) => !q || [t.username, t.teamName, t.univShort, t.univFull].some((x) => String(x || '').toLowerCase().includes(q));
  // ESCOLHIDO (📌) fica na tela em QUALQUER filtro de linha, como a minha própria linha
  return (t) => t.you || t.pinned || ((t.virtual ? (!rfv || rfv(t)) : (!rf || rf(t))) && hit(t));
}
// 📌 na linha virtual (gancho teamExtra do renderizador): alterna o login nos escolhidos
function pinButton(t) {
  if (!t.virtual || t.you || !t.vlogin) return null;
  const on = friends.has(t.vlogin);
  return el('button', { class: 'pinbtn', type: 'button', 'aria-pressed': on ? 'true' : 'false',
    title: on ? T('Tirar dos meus escolhidos', 'Remove from my picks', 'Quitar de mis elegidos') : T('Fixar: mostrar sempre esta pessoa no placar virtual', 'Pin: always show this person on the virtual scoreboard', 'Fijar: mostrar siempre a esta persona en el marcador virtual'),
    onclick: (ev) => { ev.preventDefault(); ev.stopPropagation(); setFriend(t.vlogin, !on); } }, '📌');
}
// botão "📌 Escolhidos (N)" + caixa de gestão — atualizados EM LUGAR (a barra não é reconstruída)
let friendsQ = '';
function paintFriendsUI() {
  const btn = $('fFriends'); if (btn) btn.textContent = '📌 ' + T('Escolhidos', 'Picks', 'Elegidos') + ' (' + friends.size + ')';
  const box = $('vfriends'); if (!box || box.classList.contains('hidden')) return;
  const list = box.querySelector('[data-k=list]'); if (!list) return;
  const q = friendsQ.trim().toLowerCase();
  const here = virtuals.filter((v) => !v.you && (!q || (v.login + ' ' + (v.name || '')).toLowerCase().includes(q)));
  const hereSet = new Set(virtuals.map((v) => v.login));
  const away = [...friends].filter((l) => !hereSet.has(l) && (!q || l.toLowerCase().includes(q))).sort();
  list.replaceChildren(
    ...here.map((v) => el('label', { class: 'vr-fr' },
      el('input', { type: 'checkbox', checked: friends.has(v.login) ? '' : null, onchange: (e) => setFriend(v.login, e.target.checked) }),
      ' ', v.name || v.login, ' ', el('span', { class: 'muted small' }, v.login + ' · ' + v.solved + ' / ' + v.penalty))),
    ...(here.length ? [] : [el('p', { class: 'muted small' }, q ? T('Ninguém com esse nome fez o virtual desta prova.', 'Nobody with that name did this contest\'s virtual.', 'Nadie con ese nombre hizo el virtual de esta competencia.') : T('Ninguém mais terminou o virtual desta prova ainda.', 'Nobody else has finished this contest\'s virtual yet.', 'Todavía nadie más terminó el virtual de esta competencia.'))]),
    ...(away.length ? [el('div', { class: 'muted small', style: 'margin-top:.5rem' }, T('Escolhidos que não fizeram o virtual DESTA prova:', 'Picks who have not done THIS contest\'s virtual:', 'Elegidos que no hicieron el virtual de ESTA competencia:')),
      el('div', { class: 'row', style: 'flex-wrap:wrap;gap:.3rem' }, ...away.map((l) => el('span', { class: 'pill' }, l, ' ',
        el('button', { class: 'pinbtn', type: 'button', 'aria-pressed': 'true', title: T('tirar', 'remove', 'quitar'), onclick: () => setFriend(l, false) }, '✕'))))] : []));
  // caixa marcada via atributo não reflete estado em nó novo: acerta a propriedade
  list.querySelectorAll('input[type=checkbox]').forEach((c, i) => { c.checked = friends.has(here[i].login); });
}
function buildFriendsBox() {
  const box = $('vfriends'); if (!box || box.dataset.built) return; box.dataset.built = '1'; box.innerHTML = '';
  const q = el('input', { class: 'filter', type: 'search', placeholder: T('buscar por nome ou login…', 'search by name or login…', 'buscar por nombre o usuario…') });
  q.addEventListener('input', () => { friendsQ = q.value; paintFriendsUI(); });
  const add = el('input', { class: 'filter', type: 'text', placeholder: T('adicionar pelo login…', 'add by login…', 'agregar por usuario…'), style: 'width:12rem' });
  const addBtn = el('button', { type: 'button', class: 'btn ghost small', onclick: () => {
    const l = add.value.trim(); if (!/^[A-Za-z0-9._@+-]{1,64}$/.test(l)) { add.focus(); return; }
    add.value = ''; setFriend(l, true);
  } }, T('adicionar', 'add', 'agregar'));
  add.addEventListener('keydown', (e) => { if (e.key === 'Enter') addBtn.click(); });
  box.append(el('p', { class: 'small muted', style: 'margin:0 0 .5rem' }, T(
    'Quem você escolher aparece SEMPRE no placar virtual, em qualquer filtro — para se comparar com os amigos. A lista é da sua conta e vale para todas as provas' + (logged() ? '.' : ' (sem entrar na conta, ela fica só neste navegador).'),
    'Whoever you pick ALWAYS shows on the virtual scoreboard, under any filter — to compare yourself with friends. The list belongs to your account and applies to every contest' + (logged() ? '.' : ' (without logging in it stays in this browser only).'),
    'Quien elijas aparece SIEMPRE en el marcador virtual, con cualquier filtro — para compararte con tus amigos. La lista es de tu cuenta y vale para todas las competencias' + (logged() ? '.' : ' (sin iniciar sesión, queda solo en este navegador).'))),
    el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;margin-bottom:.5rem' }, q, add, addBtn),
    el('div', { 'data-k': 'list', class: 'vr-frlist' }));
}
function renderFilters() {
  const bar = $('vfilters'); if (!bar || !feed) return; bar.classList.remove('hidden');
  if (bar.dataset.built) return; bar.dataset.built = '1'; bar.innerHTML = '';
  const lab = (txt, ctl) => el('label', {}, txt, ctl);
  const on = (sel, fn) => sel.addEventListener('change', () => { fn(sel.value); saveFlt(); paintBoard(true); });
  // opções vêm do placar FINAL inteiro, já enriquecido (mesma fonte dos filtros do placar oficial)
  const full = boardAt(feed, idx, virtuals, Infinity, balloons);
  F.applyTeamsDir(full, teamsDir, CID); F.applyTeamsMeta(full, teamsMeta);
  const views = feed.views || [], hasGuests = feed.teams.some((tm) => tm[5]);
  if (views.length > 1 || hasGuests) {
    const sel = el('select', { id: 'fView' }, el('option', { value: '' }, T('Geral (todos)', 'Overall (everyone)', 'General (todos)')),
      ...(views.length > 1 ? views.map((v) => el('option', { value: v.id }, v.name || v.id))
        : [el('option', { value: '!guests' }, T('Oficial (sem convidados)', 'Official (no guests)', 'Oficial (sin invitados)'))]));
    if (![...sel.options].some((o) => o.value === flt.view)) flt.view = '';
    sel.value = flt.view; on(sel, (v) => { flt.view = v; }); bar.append(lab(T('Placar:', 'Board:', 'Marcador:'), sel));
  } else flt.view = '';
  const flags = [...new Set(full.teams.map((t) => String(t._country || '').toLowerCase()).filter(Boolean))];
  if (flags.length) {
    const byC = new Map();
    flags.forEach((c) => { const cc = c.split('-')[0]; if (!byC.has(cc)) byC.set(cc, []); if (c !== cc) byC.get(cc).push(c); });
    const sel = el('select', { id: 'fFlag' }, el('option', { value: '' }, T('todas', 'all', 'todas')));
    [...byC.keys()].sort((a, b) => flagName(a).localeCompare(flagName(b))).forEach((cc) => {
      sel.append(el('option', { value: cc }, flagName(cc)));
      byC.get(cc).sort((a, b) => flagName(a).localeCompare(flagName(b))).forEach((stt) => sel.append(el('option', { value: stt }, '\u00a0\u00a0' + flagName(stt))));
    });
    if (![...sel.options].some((o) => o.value === flt.country)) flt.country = '';
    sel.value = flt.country; on(sel, (v) => { flt.country = v; }); bar.append(lab(T('Bandeira:', 'Flag:', 'Bandera:'), sel));
  } else flt.country = '';
  const schools = [...new Set(full.teams.map((t) => t._school).filter(Boolean))].sort();
  if (schools.length) {
    const sel = el('select', { id: 'fUniv' }, el('option', { value: '' }, T('todas', 'all', 'todas')), ...schools.map((x) => el('option', { value: x }, x)));
    if (!schools.includes(flt.school)) flt.school = '';
    sel.value = flt.school; on(sel, (v) => { flt.school = v; }); bar.append(lab(T('Universidade:', 'University:', 'Universidad:'), sel));
  } else flt.school = '';
  const rops = F.regionOptions(regions, full.teams);
  vRops = rops;
  if (rops.length) {
    const sel = el('select', { id: 'fRegion' }, el('option', { value: '' }, T('todas', 'all', 'todas')),
      ...rops.map((r, i) => el('option', { value: String(i) }, '\u00a0'.repeat(r.depth * 2) + (r.name || r.regex))));
    const cur = flt.region ? rops.indexOf(F.regionResolve(rops, flt.region)) : -1;
    if (cur < 0) flt.region = null;
    sel.value = cur >= 0 ? String(cur) : '';
    on(sel, (v) => { flt.region = v === '' ? null : { name: rops[Number(v)].name, regex: rops[Number(v)].regex }; });
    bar.append(lab(T('Sede:', 'Site:', 'Sede:'), sel));
  } else flt.region = null;
  const vsel = el('select', { id: 'fVirt' }, el('option', { value: 'all' }, T('todos', 'all', 'todos')),
    el('option', { value: 'friends' }, T('só os escolhidos', 'only my picks', 'solo mis elegidos')),
    el('option', { value: 'mine' }, T('só o meu', 'only mine', 'solo el mío')), el('option', { value: 'none' }, T('nenhum', 'none', 'ninguno')));
  if (!['all', 'friends', 'mine', 'none'].includes(flt.virt)) flt.virt = 'all';
  vsel.value = flt.virt; on(vsel, (v) => { flt.virt = v; }); bar.append(lab(T('Virtuais:', 'Virtuals:', 'Virtuales:'), vsel));
  bar.append(el('button', { id: 'fFriends', type: 'button', title: T('Escolher quem aparece sempre no placar virtual', 'Choose who always shows on the virtual scoreboard', 'Elegir quién aparece siempre en el marcador virtual'),
    onclick: () => { const b = $('vfriends'); b.classList.toggle('hidden'); if (!b.classList.contains('hidden')) { buildFriendsBox(); paintFriendsUI(); } } }, '📌'));
  const q = el('input', { id: 'fQ', class: 'filter', type: 'search', placeholder: T('buscar time, universidade, login…', 'search team, university, login…', 'buscar equipo, universidad, usuario…') });
  q.value = flt.q || ''; q.addEventListener('input', () => { flt.q = q.value; saveFlt(); paintBoard(true); });
  bar.append(q, el('button', { id: 'fClear', type: 'button', onclick: () => {
    flt = { view: '', country: '', school: '', region: null, q: '', virt: 'all' }; saveFlt(); bar.dataset.built = ''; renderFilters(); paintBoard(true);
  } }, T('limpar filtros', 'clear filters', 'limpiar filtros')), el('span', { class: 'fcount', id: 'fCount' }, ''));
  paintFriendsUI();
}
function renderReplay() {
  const box = $('vreplay'); box.classList.remove('hidden'); if (box.dataset.built) return; box.dataset.built = '1';
  const dur = info.duration;
  const rng = el('input', { type: 'range', min: '0', max: String(dur), step: '60', value: String(dur) });
  const lab = el('b', { style: 'font-variant-numeric:tabular-nums;min-width:5.5em' }, T('final', 'final', 'final'));
  const play = el('button', { class: 'btn ghost' }, '▶ ' + T('Replay', 'Replay', 'Replay'));
  const set = (v) => { replayT = v >= dur ? Infinity : v; rng.value = String(Math.min(v, dur)); lab.textContent = v >= dur ? T('final', 'final', 'final') : hms(v); paintSoon(); };
  rng.addEventListener('input', () => { stop(); set(Number(rng.value)); });
  rng.addEventListener('change', () => set(Number(rng.value)));   // soltou a barra: garante a posição final
  const stop = () => { if (playing) { clearInterval(playing); playing = null; play.textContent = '▶ ' + T('Replay', 'Replay', 'Replay'); } };
  play.addEventListener('click', () => {
    if (playing) { stop(); return; }
    if (Number(rng.value) >= dur) set(0);
    play.textContent = '⏸ ' + T('Pausar', 'Pause', 'Pausar');
    playing = setInterval(() => { const v = Number(rng.value) + 60; if (v >= dur) { set(dur); stop(); } else set(v); }, 250);   // 1 min de prova a cada 250 ms
  });
  box.append(play, rng, lab, el('span', { class: 'muted small' }, T('arraste para ver o placar em qualquer minuto da prova', 'drag to see the scoreboard at any minute of the contest', 'arrastra para ver el marcador en cualquier minuto de la competencia')));
}

// ---------------------------------------------------------------- abas (cara de contest, com a run largada)
const TABS = [['prova', () => T('Prova', 'Contest', 'Competencia')], ['placar', () => T('Placar', 'Scoreboard', 'Marcador')],
  ['clar', () => T('Clarifications & avisos', 'Clarifications & notices', 'Aclaraciones y avisos')],
  ['subs', () => T('Minhas submissões', 'My submissions', 'Mis envíos')], ['ajuda', () => T('Ajuda', 'Help', 'Ayuda')]];
let tab = 'prova';
const tabsOn = () => !!(me && ['running', 'judging', 'finished'].includes(me.state));
function buildTabs() {
  const nav = $('vtabs');
  if (!tabsOn()) { nav.classList.add('hidden'); nav.innerHTML = ''; showTab(null); return; }
  nav.classList.remove('hidden');
  if (!nav.dataset.built) {
    nav.dataset.built = '1'; nav.innerHTML = '';
    TABS.forEach(([k, lbl]) => nav.append(el('button', { type: 'button', role: 'tab', 'data-k': k, onclick: () => { location.hash = k; showTab(k); } }, lbl())));
  }
  const h = (location.hash || '').slice(1);
  showTab(TABS.some(([k]) => k === h) ? h : tab);
}
// sem abas (largada, agendada, replay): a página de sempre — arena escondida, placar à mostra
function showTab(k) {
  tab = k || 'prova';
  document.querySelectorAll('#varena > [data-tab]').forEach((d) => d.classList.toggle('hidden', !k || d.dataset.tab !== k));
  $('vboardsec').classList.toggle('hidden', !!k && k !== 'placar');
  $('vtabs').querySelectorAll('button').forEach((b) => { b.classList.toggle('on', b.dataset.k === k); b.setAttribute('aria-selected', b.dataset.k === k ? 'true' : 'false'); });
  if (k === 'clar') markClarSeen();
  if (k === 'placar') paintBoard(true);
}

// ---------------------------------------------------------------- avisos & clarifications (tempo relativo)
// O SERVIDOR corta pelo relógio da run (/treino/virtual/clarifications): aqui só se desenha o que chegou. "Novo" =
// id ainda não visto NESTE navegador; a aba ganha o contador (o mesmo aviso do contest: contador, sem som).
const SKEY = 'moj_vclar_seen_' + CID;
let clarItems = [], clarSig = '';
let seen = new Set();
try { seen = new Set(JSON.parse(localStorage.getItem(SKEY) || '[]')); } catch { /* storage indisponível */ }
const saveSeen = () => { try { localStorage.setItem(SKEY, JSON.stringify([...seen])); } catch { /* idem */ } };
const relTxt = (it) => (it.kind === 'news' && it.rel === 0) ? T('antes da prova', 'before the contest', 'antes de la competencia')
  : (it.rel > info.duration ? T('depois da prova', 'after the contest', 'después de la competencia')
    : (it.kind === 'clar' ? T('respondida aos ', 'answered at ', 'respondida a los ') : T('aos ', 'at ', 'a los ')) + hms(it.rel));
async function loadClar() {
  if (!tabsOn() || loadClar.busy) return; loadClar.busy = true;
  try {
    const d = await apiGet('/treino/virtual/clarifications?contest=' + enc(CID), A);
    clarItems = d.items || [];
    const sig = JSON.stringify(clarItems.map((x) => x.kind + x.id));
    if (sig !== clarSig) { clarSig = sig; renderClar(); renderNews(); }
    paintClarCount();
  } catch { /* rede: tenta no próximo ciclo */ } finally { loadClar.busy = false; }
}
function itemBox(it) {
  const isNew = !seen.has(it.kind + ':' + it.id);
  const tag = it.kind === 'clar' ? (it.problem === 'general' ? T('Geral', 'General', 'General') : it.problem)
    : (it.kind === 'notice' ? T('Aviso', 'Notice', 'Aviso') : T('Notícia', 'News', 'Noticia'));
  const kids = [el('div', { class: 'hd' }, el('span', { class: 'pill' }, tag), el('span', { class: 'vr-rel' }, relTxt(it)),
    isNew ? el('span', { class: 'pill' }, T('nova', 'new', 'nueva')) : '')];
  if (it.kind === 'clar') {
    if (it.question) kids.push(el('p', {}, el('b', {}, T('Pergunta: ', 'Question: ', 'Pregunta: ')), it.question));
    kids.push(el('p', {}, el('b', {}, T('Resposta: ', 'Answer: ', 'Respuesta: ')), it.answer));
  } else if (it.kind === 'notice') {
    if (it.question) kids.push(el('p', {}, el('b', {}, it.question)));
    kids.push(el('p', {}, it.answer));
  } else {
    kids.push(el('p', {}, el('b', {}, it.title)));
    if (it.text) kids.push(el('p', {}, it.text));
    if (it.file) kids.push(el('p', {}, el('a', { href: '#', onclick: (e) => { e.preventDefault(); downloadFile('/treino/virtual/news-file?contest=' + enc(CID) + '&id=' + enc(it.id), it.file.name); } }, '📎 ' + it.file.name)));
  }
  return el('div', { class: 'vr-item' + (isNew ? ' new' : '') }, ...kids);
}
function renderClar() {
  const box = $('vclar'); box.innerHTML = '';
  if (!clarItems.length) { box.append(el('p', { class: 'muted small' }, T('Nada por enquanto.', 'Nothing yet.', 'Nada por ahora.'))); return; }
  const opts = ['', 'general', ...problems.map((p) => p.letter)];
  const f = el('select', {}, ...opts.map((o) => el('option', { value: o }, o === '' ? T('Todos', 'All', 'Todos') : (o === 'general' ? T('Geral e avisos', 'General and notices', 'General y avisos') : o))));
  const list = el('div', {});
  const paint = () => list.replaceChildren(...clarItems.filter((it) => !f.value || (f.value === 'general' ? (it.kind !== 'clar' || it.problem === 'general') : (it.kind === 'clar' && it.problem === f.value))).map(itemBox));
  f.addEventListener('change', paint);
  box.append(el('div', { class: 'row', style: 'gap:.5rem;margin-bottom:.4rem' }, el('label', { class: 'small' }, T('Problema: ', 'Problem: ', 'Problema: ')), f), list);
  paint();
}
// avisos e notícias também no topo da aba Prova (como a seção "Informações & Notícias" do contest)
function renderNews() {
  const ns = clarItems.filter((it) => it.kind !== 'clar');
  $('vnewssec').classList.toggle('hidden', !ns.length);
  $('vnews').replaceChildren(...ns.map(itemBox));
}
function paintClarCount() {
  const n = clarItems.filter((it) => !seen.has(it.kind + ':' + it.id)).length;
  const b = $('vtabs').querySelector('[data-k=clar]'); if (!b) return;
  let c = b.querySelector('.cnt');
  if (n && tab !== 'clar') { if (!c) { c = el('span', { class: 'cnt' }); b.append(c); } c.textContent = String(n); }
  else if (c) c.remove();
  if (tab === 'clar' && n) markClarSeen();
}
function markClarSeen() {
  if (!clarItems.length) return;
  const before = seen.size; clarItems.forEach((it) => seen.add(it.kind + ':' + it.id));
  if (seen.size !== before) { saveSeen(); setTimeout(() => { renderClar(); renderNews(); }, 4000); }   // o "nova" fica uns segundos
  const c = $('vtabs').querySelector('[data-k=clar] .cnt'); if (c) c.remove();
}

// ---------------------------------------------------------------- arquivos da prova
const DOC_LABEL = { contest: () => T('📘 Caderno de problemas', '📘 Problem set', '📘 Cuaderno de problemas'),
  'info-sheet': () => T('🖥️ Ambiente de julgamento', '🖥️ Judging environment', '🖥️ Entorno de evaluación'),
  times: () => T('⏱️ Tempos-limite', '⏱️ Time limits', '⏱️ Límites de tiempo'),
  editorial: () => T('💡 Editorial (soluções comentadas)', '💡 Editorial (solutions explained)', '💡 Editorial (soluciones comentadas)') };
async function loadDocs() {
  if (!tabsOn()) return;
  let d; try { d = await apiGet('/treino/virtual/docs?contest=' + enc(CID), A); } catch { return; }
  const rows = [];
  (d.docs || []).forEach((x) => {
    const lbl = (DOC_LABEL[x.type] || (() => x.type))();
    if (x.locked) { rows.push(el('div', { class: 'doc-line muted' }, '🔒 ', el('b', {}, lbl), ' — ', T('libera quando a sua participação terminar', 'unlocks when your participation ends', 'se libera cuando termine tu participación'))); return; }
    rows.push(el('div', { class: 'doc-line' }, el('b', {}, lbl), ...x.langs.map((l) => el('a', { class: 'tag pill', href: '#',
      onclick: (e) => { e.preventDefault(); openPdf('/treino/virtual/doc?contest=' + enc(CID) + '&type=' + enc(x.type) + '&lang=' + enc(l)); } }, l.toUpperCase()))));
  });
  (d.links || []).forEach((x) => rows.push(el('div', { class: 'doc-line' }, '🔗 ', el('a', { href: x.url, target: '_blank', rel: 'noopener noreferrer' }, x.label))));
  $('vdocssec').classList.toggle('hidden', !rows.length);
  $('vdocs').replaceChildren(...rows);
}
// PDF autenticado numa aba nova (aberta NO CLIQUE: depois do await o navegador bloquearia o pop-up)
async function openPdf(path) {
  const w = window.open('', '_blank');
  try {
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken('treino') } });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const url = URL.createObjectURL(new Blob([await r.blob()], { type: 'application/pdf' }));
    if (w && !w.closed) w.location.replace(url); else window.open(url, '_blank');
  } catch { if (w && !w.closed) w.close(); alert(T('Não foi possível abrir o arquivo.', 'Could not open the file.', 'No se pudo abrir el archivo.')); }
}
async function downloadFile(path, name) {
  try {
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + getToken('treino') } });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const a = el('a', { href: URL.createObjectURL(await r.blob()), download: name }); document.body.append(a); a.click(); a.remove();
  } catch { alert(T('Falha ao baixar.', 'Download failed.', 'Error al descargar.')); }
}

// ---------------------------------------------------------------- ajuda
function renderHelp() {
  const box = $('vhelp'); if (box.dataset.built) return; box.dataset.built = '1';
  box.append(el('h2', {}, T('Como funciona a participação virtual', 'How the virtual participation works', 'Cómo funciona la participación virtual')),
    el('ul', { class: 'vr-rules' },
      el('li', {}, T('O relógio é o da SUA prova: os times oficiais aparecem no placar resolvendo cada problema no mesmo minuto em que resolveram na prova de verdade.', 'The clock is YOUR contest\'s: the official teams appear on the scoreboard solving each problem at the same minute as in the real contest.', 'El reloj es el de TU competencia: los equipos oficiales aparecen en el marcador resolviendo cada problema en el mismo minuto que en la competencia real.')),
      el('li', {}, T('O tempo-limite de cada problema aparece ao abrir o problema, por linguagem — é o que julga a sua submissão.', 'Each problem\'s time limit shows when you open the problem, per language — it is what judges your submission.', 'El límite de tiempo de cada problema aparece al abrirlo, por lenguaje — es el que evalúa tu envío.')),
      el('li', {}, T('Avisos e clarifications públicas chegam no mesmo minuto em que saíram na prova. Ninguém responde perguntas no virtual.', 'Notices and public clarifications arrive at the same minute as in the contest. Nobody answers questions in a virtual participation.', 'Los avisos y las aclaraciones públicas llegan en el mismo minuto que en la competencia. Nadie responde preguntas en el virtual.')),
      el('li', {}, T('O placar congela no mesmo minuto em que congelou na prova (as suas submissões continuam visíveis) e abre quando a sua participação termina; o editorial também.', 'The scoreboard freezes at the same minute it froze in the contest (your submissions stay visible) and opens when your participation ends; so does the editorial.', 'El marcador se congela en el mismo minuto que en la competencia (tus envíos siguen visibles) y se abre cuando termina tu participación; el editorial también.'))),
    el('p', {}, el('a', { href: '/treino/ajuda/', target: '_blank', rel: 'noopener' }, T('📖 Como enviar: entrada e saída e o código inicial de cada linguagem', '📖 How to submit: input and output and each language\'s starter code', '📖 Cómo enviar: entrada y salida y el código inicial de cada lenguaje'))));
}

// ---------------------------------------------------------------- ciclo
async function refreshRun() {
  if (!logged() || refreshRun.busy) return; refreshRun.busy = true;
  try {
    const before = me ? me.state : '';
    const d = await apiGet('/treino/virtual/run?contest=' + enc(CID), A); setMe(d.me);
    if (me.state !== before) { await enter(); return; }
    markProblems(); renderSubs(); paintBoard();
  } catch { /* rede: tenta no próximo tick */ } finally { refreshRun.busy = false; }
}
async function loadBoard() {
  try { const b = await apiGet('/treino/virtual/board?contest=' + enc(CID), logged() ? A : {}); virtuals = b.virtuals || []; } catch { virtuals = []; }
}
async function enter() {
  const st = me ? me.state : 'anon';
  headState = ''; lastSig = '';
  $('vstart').classList.add('hidden'); $('varena').classList.add('hidden'); $('vreplay').classList.add('hidden');
  $('vboardsec').classList.remove('hidden');
  await Promise.all([loadBoard(), loadFriends()]);
  if (st === 'running' || st === 'judging' || st === 'finished') {
    if (!problems) { try { problems = (await apiGet('/treino/virtual/problems?contest=' + enc(CID), A)).problems; } catch { problems = []; } }
    // a sanfona é refeita na troca de estado (o envio fecha quando a run termina)
    if ($('vprobs').dataset.state !== st) { $('vprobs').dataset.state = st; $('vprobs').dataset.built = ''; }
    $('varena').classList.remove('hidden'); renderProblems(); renderSubs(); renderHelp();
    loadClar(); loadDocs();                      // o que o relógio da run já liberou (o editorial, só no fim)
  }
  if (st === 'scheduled') renderScheduled();
  else if (st === 'none' || st === 'discarded' || st === 'forbidden' || st === 'anon') renderStart();
  if (st !== 'running' && st !== 'scheduled') { replayT = Infinity; renderReplay(); }
  $('vboardtitle').textContent = st === 'running' ? T('Placar no seu tempo de prova', 'Scoreboard at your contest time', 'Marcador en tu tiempo de competencia') : T('Placar — oficial + participações virtuais', 'Scoreboard — official + virtual participations', 'Marcador — oficial + participaciones virtuales');
  $('vfilters').dataset.built = ''; renderFilters();
  buildTabs();
  paintHead(); paintBoard(true);
}

async function boot() {
  if (!CID) { $('vhead').textContent = T('Contest não informado.', 'No contest given.', 'No se indicó ninguna competencia.'); return; }
  try {
    [feed] = await Promise.all([apiGet('/treino/virtual/feed?contest=' + enc(CID), {})]);
  } catch (e) {
    $('vhead').innerHTML = ''; $('vhead').append(el('h2', {}, T('Participação virtual indisponível', 'Virtual participation unavailable', 'Participación virtual no disponible')),
      el('p', { class: 'muted' }, T('Este contest não oferece participação virtual (ou ainda não terminou).', 'This contest does not offer virtual participation (or has not ended yet).', 'Esta competencia no ofrece participación virtual (o todavía no terminó).')));
    return;
  }
  idx = indexFeed(feed);
  info = { title: feed.title, duration: feed.duration, penalty_minutes: feed.penalty_minutes, problems_count: feed.problems.length, rules: { grace_s: 900, max_discards: 2 } };
  // dados dos filtros: as MESMAS rotas públicas que o placar oficial usa (contest elegível nunca é secreto)
  Promise.all([
    flagNamesReady().catch(() => null),   // nomes das bandeiras p/ o seletor (senão sai o código cru)
    apiGet('/contest/regions?contest=' + enc(CID), {}).catch(() => null),
    apiGet('/contest/teams-meta?contest=' + enc(CID), {}).catch(() => null),
    apiGet('/contest/teams?contest=' + enc(CID), {}).catch(() => null),
  ]).then(([, rg, tm, td]) => {
    regions = rg ? (Array.isArray(rg) ? rg : (rg.regions || [])) : [];
    teamsMeta = tm ? (tm.rules || (Array.isArray(tm) ? tm : [])) : [];
    teamsDir = (td && td.teams) || {};
    if ($('vfilters')) { $('vfilters').dataset.built = ''; renderFilters(); paintBoard(true); }
  });
  apiGet('/contest/balloons?contest=' + enc(CID), {}).then((b) => { balloons = (b && (b.balloons || b)) || {}; paintBoard(true); }).catch(() => {});
  if (logged()) {
    try { const d = await apiGet('/treino/virtual/info?contest=' + enc(CID), A); info = d; setMe(d.me); } catch { me = null; }
    try { const s = await status('treino'); who = (s && s.login) || null; whoName = (s && s.name) || ''; } catch { who = null; }
  }
  await enter();
  setInterval(() => { paintHead(); if (me && me.state === 'running') paintBoard(); }, 1000);
  setInterval(() => { if (me && ['running', 'judging', 'scheduled'].includes(me.state) && !document.hidden) refreshRun(); }, 10000);
  // avisos/clarifications chegam no tempo relativo: o servidor corta, aqui só se pergunta de tempos em tempos
  setInterval(() => { if (me && me.state === 'running' && !document.hidden) loadClar(); }, 20000);
  window.addEventListener('hashchange', () => { if (tabsOn()) buildTabs(); });
  document.addEventListener('moj:lang', () => { headState = ''; $('vprobs').dataset.built = ''; $('vtabs').dataset.built = ''; $('vhelp').dataset.built = ''; $('vhelp').innerHTML = ''; clarSig = ''; $('vreplay').dataset.built = ''; $('vreplay').innerHTML = ''; $('vfilters').dataset.built = ''; $('vfriends').dataset.built = ''; $('vsubs').dataset.sig = ''; enter(); });
}
boot();
