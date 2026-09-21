// contest/animeitor/api-section.js — 📡 a integração com a API do ANIMEITOR (o MOJ EMPURRA evento,
// placares/sedes, submissões e o relógio; ver docs/ANIMEITOR.md). Seção da mesa do telão, só p/ o
// `.animeitor` e o admin (a API corta o resto). Substitui o streaming por chave (webcast BOCA), que
// fica na página como legado.
//
// Três blocos: CONEXÃO (URL, usuário, token write-only, URL pública do MOJ p/ foto/música, nome do
// evento) · PLACARES E SEDES (a proposta do MOJ — geral, coortes, países; sedes = folhas de
// regions.json — editável: nome, medalhas, regex ou "automático") · OPERAÇÃO (publicar, mandar
// submissões, ligar/desligar o alimentador, estado ao vivo, links).
// ⚠ O estado ao vivo atualiza EM LUGAR (só a caixa dele, a cada 3 s com o alimentador ligado): a
// tabela que o operador está editando nunca é reconstruída por timer.
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;

export function makeApiSection(CONTEST, G) {
  const A = '/contest/animeitor/api?contest=' + enc(CONTEST);
  const root = el('div', { class: 'section', id: 'anApi' });
  const statusBox = el('div', { class: 'small', style: 'margin:.5rem 0' });
  const linksBox = el('div', {});
  const msgBox = el('div', { class: 'small', style: 'margin:.4rem 0' });
  let S = null;          // estado do GET
  let EDIT = null;       // cópia de trabalho dos placares
  let DIRTY = false;
  let timer = null;

  const say = (txt, cls) => { msgBox.className = 'small ' + (cls || ''); msgBox.textContent = txt || ''; };
  const post = (body) => apiPost(A, body, G);
  const srcName = (s) => ({ view: T('visão do placar', 'scoreboard view'), region: T('região', 'region'), manual: T('manual', 'manual') }[(s || {}).kind] || '—');
  const clone = (x) => JSON.parse(JSON.stringify(x));
  const fromProposal = (p) => ((p && p.contests) || []).map((c) => ({ name: c.name, source: c.source, codes: null, ouro: 1, prata: 2, bronze: 3, style: null,
    sites: (c.sites || []).map((s) => ({ name: s.name, source: s.source, codes: null })) }));
  const propOf = (src) => ((S.proposal && S.proposal.contests) || []).find((c) => JSON.stringify(c.source) === JSON.stringify(src));

  async function load() {
    S = await apiGet(A + '&proposal=1', G);
    EDIT = S.contests ? clone(S.contests) : fromProposal(S.proposal);
    DIRTY = false;
    render();
  }

  // ---- conexão ----------------------------------------------------------------------------
  function connCard() {
    const url = el('input', { type: 'text', value: S.url || '', size: 34, 'aria-label': 'URL' });
    const user = el('input', { type: 'text', value: S.user || '', size: 14, autocomplete: 'off', 'aria-label': T('usuário', 'user') });
    const tok = el('input', { type: 'password', size: 22, autocomplete: 'new-password',
      placeholder: S.has_cred ? T('(gravado — digite p/ trocar)', '(saved — type to replace)') : 'token', 'aria-label': 'token' });
    const ev = el('input', { type: 'text', value: S.event || CONTEST, size: 24, 'aria-label': T('evento', 'event') });
    // a foto/música do time são buscadas pelo TELÃO direto no MOJ: precisa da URL pública, que não é a
    // do subdomínio do contest
    const guess = S.moj_base_url || String(location.origin || '').replace('//' + CONTEST + '.', '//');
    const base = el('input', { type: 'text', value: guess, size: 30, 'aria-label': T('URL pública do MOJ', 'MOJ public URL') });
    const save = async (test) => {
      say('…');
      try {
        const body = { action: 'config', url: url.value.trim(), event: ev.value.trim(), moj_base_url: base.value.trim() };
        if (tok.value || user.value !== (S.user || '')) { body.user = user.value.trim(); body.token = tok.value; }
        await post(body);
        if (test) {
          const r = await post({ action: 'test' });
          say(r.event_exists
            ? (r.managed ? T('Conexão ok. O evento já existe e é deste contest.', 'Connection ok. The event exists and belongs to this contest.')
              : T('Conexão ok. ⚠ Já existe um evento com esse nome que NÃO foi criado por este contest.', 'Connection ok. ⚠ An event with this name already exists and was NOT created by this contest.'))
            : T('Conexão ok. O evento ainda não existe lá: publique para criar.', 'Connection ok. The event does not exist there yet: publish to create it.'));
        } else say(T('Gravado.', 'Saved.'));
        const keep = msgBox.textContent; await load(); say(keep);
      } catch (e) { say(e.message || T('falha', 'failed'), 'error-box'); }
    };
    const row = (lbl, inp, hint) => el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap;margin:.25rem 0' },
      el('label', { class: 'small', style: 'min-width:11rem' }, lbl), inp, hint ? el('span', { class: 'small muted' }, hint) : '');
    return el('div', {},
      el('h3', {}, T('Conexão', 'Connection')),
      row(T('Servidor do Animeitor:', 'Animeitor server:'), url, T('só https', 'https only')),
      row(T('Usuário e token:', 'User and token:'), el('span', { class: 'row', style: 'gap:.4rem' }, user, tok), T('o token nunca volta para a tela', 'the token is never sent back to the page')),
      row(T('Nome do evento lá:', 'Event name there:'), ev, S.secret_contest ? T('⚠ contest secreto: este NOME fica público na página inicial do Animeitor', '⚠ secret contest: this NAME is public on the Animeitor landing page') : ''),
      row(T('URL pública do MOJ:', 'MOJ public URL:'), base, T('de onde o telão busca a foto e a música de cada time', 'where the big screen fetches each team photo and music')),
      el('div', { class: 'row', style: 'gap:.5rem;margin:.4rem 0' },
        el('button', { class: 'btn', onclick: () => save(true) }, T('gravar e testar', 'save and test')),
        el('button', { class: 'btn ghost', onclick: () => save(false) }, T('só gravar', 'save only'))));
  }

  // ---- placares e sedes ---------------------------------------------------------------------
  const touch = () => { DIRTY = true; dirtyNote.textContent = T('alterações não salvas', 'unsaved changes'); };
  const dirtyNote = el('span', { class: 'small', style: 'color:var(--warn,#b9770e)' });
  const codesCell = (obj, isSite, parentSrc) => {
    const auto = el('input', { type: 'checkbox', checked: obj.codes == null, disabled: (obj.source || {}).kind === 'manual' });
    const ta = el('textarea', { rows: 1, cols: 28, style: 'font-family:monospace;font-size:.8rem', placeholder: T('um regex de login por linha', 'one login regex per line') },
      (obj.codes || []).join('\n'));
    ta.style.display = obj.codes == null ? 'none' : '';
    auto.addEventListener('change', () => {
      if (auto.checked) { obj.codes = null; ta.style.display = 'none'; }
      else {
        const p = isSite ? ((propOf(parentSrc) || { sites: [] }).sites || []).find((s) => JSON.stringify(s.source) === JSON.stringify(obj.source)) : propOf(obj.source);
        obj.codes = (p && p.codes) ? p.codes.slice() : []; ta.value = obj.codes.join('\n'); ta.style.display = '';
      }
      touch();
    });
    ta.addEventListener('input', () => { obj.codes = ta.value.split('\n').map((x) => x.trim()).filter(Boolean); touch(); });
    return el('div', {}, el('label', { class: 'small' }, auto, ' ' + T('automático', 'automatic')), ta);
  };
  const num = (obj, k) => { const i = el('input', { type: 'number', min: 0, value: obj[k], style: 'width:4rem' }); i.addEventListener('input', () => { obj[k] = Math.max(0, parseInt(i.value, 10) || 0); touch(); }); return i; };
  const nameInp = (obj) => { const i = el('input', { type: 'text', value: obj.name, size: 18 }); i.addEventListener('input', () => { obj.name = i.value; touch(); }); return i; };

  function boardsCard() {
    const tb = el('tbody');
    EDIT.forEach((c, ci) => {
      const p = propOf(c.source);
      const sitesBox = el('div', { style: 'margin-top:.3rem' });
      const drawSites = () => {
        sitesBox.innerHTML = '';
        c.sites.forEach((s, si) => sitesBox.append(el('div', { class: 'row', style: 'gap:.4rem;align-items:flex-start;margin:.15rem 0' },
          nameInp(s), codesCell(s, true, c.source),
          el('button', { class: 'btn ghost', title: T('remover sede', 'remove site'), onclick: () => { c.sites.splice(si, 1); touch(); drawSites(); } }, '×'))));
        sitesBox.append(el('button', { class: 'btn ghost', onclick: () => { c.sites.push({ name: '', source: { kind: 'manual', id: '' }, codes: [] }); touch(); drawSites(); } }, T('+ sede', '+ site')));
      };
      drawSites();
      tb.append(el('tr', {},
        el('td', {}, nameInp(c), el('div', { class: 'small muted' }, srcName(c.source) + (p ? ' · ' + T(`${p.n} times`, `${p.n} teams`) : ''))),
        el('td', {}, codesCell(c, false)),
        el('td', { class: 'n' }, num(c, 'ouro')), el('td', { class: 'n' }, num(c, 'prata')), el('td', { class: 'n' }, num(c, 'bronze')),
        el('td', {}, el('details', {}, el('summary', { class: 'small' }, T(`${c.sites.length} sedes`, `${c.sites.length} sites`)), sitesBox)),
        el('td', {}, el('button', { class: 'btn ghost danger', title: T('remover placar', 'remove scoreboard'), onclick: () => { EDIT.splice(ci, 1); touch(); redrawBoards(); } }, '×'))));
    });
    const saveBoards = async () => {
      say('…');
      try { await post({ action: 'save', contests: EDIT }); DIRTY = false; dirtyNote.textContent = ''; say(T('Placares salvos. Publique para levar ao telão.', 'Scoreboards saved. Publish to send them to the big screen.')); return true; }
      catch (e) { say(e.message || T('falha', 'failed'), 'error-box'); return false; }
    };
    boardsHost.saveBoards = saveBoards;
    return el('div', {},
      el('h3', {}, T('Placares e sedes', 'Scoreboards and sites')),
      el('p', { class: 'note' }, T('Cada placar é uma tela do telão. O MOJ propõe o geral, um por coorte e um por país, com as sedes de cada um. "Automático" usa o recorte do próprio MOJ e acompanha time novo a cada publicação. Ouro, prata e bronze são a última colocação que recebe cada medalha.',
        'Each scoreboard is one big-screen view. MOJ proposes the general one, one per cohort and one per country, with their sites. "Automatic" uses the MOJ selection and follows new teams at each publish. Gold, silver and bronze are the last place that gets each medal.')),
      el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Placar', 'Scoreboard')), el('th', {}, T('Times (regex de login)', 'Teams (login regex)')),
          el('th', { class: 'n' }, T('Ouro', 'Gold')), el('th', { class: 'n' }, T('Prata', 'Silver')), el('th', { class: 'n' }, T('Bronze', 'Bronze')),
          el('th', {}, T('Sedes', 'Sites')), el('th', {}, ''))), tb)),
      el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap;margin:.4rem 0' },
        el('button', { class: 'btn ghost', onclick: () => { EDIT.push({ name: '', source: { kind: 'manual', id: '' }, codes: [], ouro: 1, prata: 2, bronze: 3, style: null, sites: [] }); touch(); redrawBoards(); } }, T('+ placar manual', '+ manual scoreboard')),
        el('button', { class: 'btn ghost', onclick: () => { if (!confirm(T('Descartar a revisão e voltar à proposta do MOJ?', 'Discard the review and go back to the MOJ proposal?'))) return; EDIT = fromProposal(S.proposal); touch(); redrawBoards(); } }, T('voltar à proposta', 'back to the proposal')),
        el('button', { class: 'btn', onclick: saveBoards }, T('salvar placares', 'save scoreboards')), dirtyNote));
  }
  const boardsHost = el('div', {});
  const redrawBoards = () => { boardsHost.innerHTML = ''; boardsHost.append(boardsCard()); };

  // ---- operação ---------------------------------------------------------------------------
  function opsCard() {
    const busy = async (fn) => { say('…'); try { await fn(); } catch (e) { say(e.message || T('falha', 'failed'), 'error-box'); } };
    const publish = (adopt) => busy(async () => {
      if (DIRTY && !(await boardsHost.saveBoards())) return;
      let r;
      try { r = await post({ action: 'publish', adopt: !!adopt }); }
      catch (e) {
        if (e.code === 'event_exists' && confirm((e.message || '') + '\n\n' + T('Assumir este evento? Só faça isso se ele for mesmo deste contest.', 'Take over this event? Only do it if it really belongs to this contest.'))) return publish(true);
        throw e;
      }
      const res = r.result || {}, cs = res.contests || [];
      const bad = cs.filter((c) => c.action === 'error' || (c.sites || []).some((s) => s.action === 'error'));
      say(res.ok ? T(`Publicado: evento ${res.event.action}, ${cs.length} placares.`, `Published: event ${res.event.action}, ${cs.length} scoreboards.`)
        : T('Publicado com recusas: ', 'Published with refusals: ') + bad.map((c) => c.name + (c.error ? ' — ' + c.error : '')).join(' · '), res.ok ? '' : 'error-box');
      await refresh(true);
    });
    return el('div', {},
      el('h3', {}, T('Operação', 'Operation')),
      el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
        el('button', { class: 'btn', disabled: !S.configured, onclick: () => publish(false) }, T('📡 publicar no telão', '📡 publish to the big screen')),
        el('button', { class: 'btn ghost', disabled: !S.configured, onclick: () => busy(async () => { const r = await post({ action: 'push-runs' }); say(T(`Submissões: ${r.runs.sent} enviadas (${r.runs.added} novas, ${r.runs.updated} corrigidas).`, `Submissions: ${r.runs.sent} sent (${r.runs.added} new, ${r.runs.updated} corrected).`) + (r.runs.error ? ' ' + r.runs.error : ''), r.runs.error ? 'error-box' : ''); await refresh(); }) }, T('mandar submissões agora', 'send submissions now')),
        el('button', { class: 'btn ghost', disabled: !S.configured, id: 'anFeedBtn', onclick: () => busy(async () => { await post({ action: S.enabled ? 'stop' : 'start' }); say(''); await refresh(); drawOpsBtn(); }) }, ''),
        el('button', { class: 'btn ghost danger', disabled: !S.configured, onclick: () => busy(async () => {
          const ev = S.event; const typed = prompt(T(`Isto APAGA o evento "${ev}" no servidor do Animeitor, com placares, sedes e submissões. Digite o nome do evento para confirmar:`, `This DELETES the event "${ev}" on the Animeitor server, with scoreboards, sites and submissions. Type the event name to confirm:`));
          if (typed == null) { say(''); return; }
          await post({ action: 'reset', confirm: typed }); say(T('Evento apagado lá.', 'Event deleted there.')); await load();
        }) }, T('apagar o evento lá', 'delete the event there'))));
  }
  const drawOpsBtn = () => { const b = root.querySelector('#anFeedBtn'); if (b) b.textContent = S.enabled ? T('⏹ parar o alimentador', '⏹ stop the feeder') : T('▶ ligar o alimentador (relógio e submissões)', '▶ start the feeder (clock and submissions)'); };

  // ---- estado ao vivo (EM LUGAR) e links ----------------------------------------------------
  const hms = (t) => { const n = Math.abs(t), s = (t < 0 ? '−' : '') + [Math.floor(n / 3600), Math.floor(n / 60) % 60, n % 60].map((x) => String(x).padStart(2, '0')).join(':'); return s; };
  function drawStatus() {
    const st = S.status || {}, ck = S.clock, parts = [];
    parts.push(S.enabled ? T('alimentador LIGADO', 'feeder ON') : T('alimentador desligado', 'feeder off'));
    const dead = S.enabled && (S.now - (S.feeder_alive_at || 0) > 15);
    if (st.published_at) parts.push(T('publicado às ', 'published at ') + new Date(st.published_at * 1000).toLocaleTimeString());
    if (ck) parts.push(T('relógio enviado: ', 'clock sent: ') + hms(ck.time_seconds) + (S.now - ck.at > 5 && S.enabled ? T(` (há ${S.now - ck.at} s — o alimentador está rodando?)`, ` (${S.now - ck.at} s ago — is the feeder running?)`) : '') + (ck.http && ck.http !== '200' ? ' ⚠ HTTP ' + ck.http : ''));
    if (st.runs) parts.push(T(`submissões: ${st.runs.total} no MOJ, ${st.runs.added || 0} criadas e ${st.runs.updated || 0} corrigidas lá`, `submissions: ${st.runs.total} in MOJ, ${st.runs.added || 0} created and ${st.runs.updated || 0} corrected there`) + (st.runs.ignored ? T(` · ${st.runs.ignored} recusadas (time fora do evento: publique de novo)`, ` · ${st.runs.ignored} refused (team not in the event: publish again)`) : ''));
    statusBox.innerHTML = '';
    statusBox.append(el('div', {}, parts.join(' · ')));
    if (dead) statusBox.append(el('div', { class: 'error-box', style: 'margin-top:.3rem' },
      T('O processo alimentador não está rodando no servidor do MOJ: o relógio do telão está PARADO. Avise o administrador do servidor (serviço animeitor-feed).',
        'The feeder process is not running on the MOJ server: the big-screen clock is STOPPED. Tell the server administrator (animeitor-feed service).')));
    if (st.last_error) statusBox.append(el('div', { class: 'error-box', style: 'margin-top:.3rem' },
      T('Último erro', 'Last error') + ' (' + st.last_error.where + (st.last_error.http ? ', HTTP ' + st.last_error.http : '') + ', ' + new Date(st.last_error.at * 1000).toLocaleTimeString() + '): ' + (st.last_error.message || '')));
  }
  async function refresh(withLinks) {
    const s = await apiGet(A + (withLinks ? '&links=1' : ''), G);
    ['status', 'clock', 'enabled', 'now', 'managed', 'configured', 'feeder_alive_at'].forEach((k) => { S[k] = s[k]; });
    if (s.links) { S.links = s.links; drawLinks(); }
    drawStatus(); drawOpsBtn(); arm();
  }
  function drawLinks() {
    linksBox.innerHTML = '';
    const L = S.links; if (!L) { linksBox.append(el('button', { class: 'btn ghost', disabled: !S.configured, onclick: () => refresh(true).catch((e) => say(e.message, 'error-box')) }, T('mostrar os links do telão', 'show the big-screen links'))); return; }
    const copy = (u) => el('button', { class: 'btn ghost', onclick: async () => { try { await navigator.clipboard.writeText(u); } catch { prompt(T('Copie:', 'Copy:'), u); } } }, T('copiar', 'copy'));
    const tbl = (rows) => el('table', { class: 'moj' }, el('tbody', {}, ...rows));
    linksBox.append(el('h3', {}, T('Links do telão', 'Big-screen links')),
      tbl((L.public || []).map((x) => el('tr', {}, el('td', {}, x.contest), el('td', {}, el('a', { href: x.url, target: '_blank', rel: 'noopener' }, x.url)), el('td', {}, copy(x.url))))),
      el('p', { class: 'note' }, '⚠ ', T('Os links de REVELAÇÃO mostram as respostas depois do congelamento. Cada sede tem o seu. Trate como senha: entregue só ao responsável da sede.',
        'The REVEAL links show the answers after the freeze. Each site has its own. Treat them as passwords: give each one only to the person in charge of that site.')),
      el('details', {}, el('summary', {}, T(`${(L.revelation || []).length} links de revelação`, `${(L.revelation || []).length} reveal links`)),
        tbl((L.revelation || []).map((x) => el('tr', {}, el('td', {}, x.contest), el('td', {}, x.site), el('td', { class: 'small' }, el('code', {}, x.url.replace(/secret=[^&]+/, 'secret=…'))), el('td', {}, copy(x.url)))))));
  }
  function arm() {
    if (timer) { clearInterval(timer); timer = null; }
    if (S && S.enabled) timer = setInterval(() => (document.hidden ? null : refresh().catch(() => {})), 3000);
  }

  function render() {
    root.innerHTML = '';
    root.append(el('h2', {}, T('📡 Animeitor (telão)', '📡 Animeitor (big screen)')),
      el('p', { class: 'note' }, T('O MOJ envia ao servidor do Animeitor o evento (problemas e times), os placares e sedes, as submissões e o relógio da prova. As respostas vão sempre reais: quem congela o placar público e conduz a revelação é o Animeitor.',
        'MOJ sends the Animeitor server the event (problems and teams), the scoreboards and sites, the submissions and the contest clock. Answers are always the real ones: the Animeitor freezes the public scoreboard and runs the reveal.')),
      connCard(), boardsHost, opsCard(), msgBox, statusBox, linksBox);
    redrawBoards(); drawStatus(); drawOpsBtn(); drawLinks(); arm();
  }

  return { node: root, load };
}
