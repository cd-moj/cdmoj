// contest/animeitor/api-section.js — 📡 a integração com a API do ANIMEITOR (o MOJ EMPURRA evento,
// placares/sedes, submissões e o relógio; ver docs/ANIMEITOR.md). Seção da mesa do telão, só p/ o
// `.animeitor` e o admin (a API corta o resto). Substitui o streaming por chave (webcast BOCA), que
// fica na página como legado.
//
// Três blocos: CONEXÃO (URL, a CHAVE — a do MOJ por padrão, invisível; ou uma própria, usuário + token
// write-only —, URL pública do MOJ p/ foto/música, nome do evento) · PLACARES E SEDES (a proposta do MOJ — geral, coortes, países; sedes = folhas de
// regions.json — editável: nome, medalhas, regex ou "automático") · OPERAÇÃO (publicar, mandar
// submissões, ligar/desligar o alimentador, CONFERIR se o Animeitor tem todas as submissões, estado ao
// vivo, links). A conferência (runs_secret, sede a sede) também roda antes de liberar o reveleitor.
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
  const hm = (e) => new Date(e * 1000).toLocaleTimeString();
  // o resultado da CONFERÊNCIA em uma frase (o mesmo texto no estado ao vivo, no botão e antes de liberar)
  const verifyText = (v) => {
    if (!v || !v.at) return [T('ainda não conferido', 'not checked yet'), 'muted'];
    const at = hm(v.at);
    if (v.state === 'not_started') return [T('a prova ainda não começou: o Animeitor só deixa conferir depois do início', 'the contest has not started: the Animeitor only allows checking after the start'), 'muted'];
    if (v.state === 'no_sites') return [T('nenhuma sede publicada cobre os times: a conferência é feita sede a sede (publique com as sedes)', 'no published site covers the teams: the check is done site by site (publish with the sites)'), 'error-box'];
    if (v.state === 'error') return [T(`a conferência falhou (${at}): `, `the check failed (${at}): `) + (v.error || ''), 'error-box'];
    const unc = v.uncovered ? T(` · ${v.uncovered} de times fora de qualquer sede não entram na conferência`, ` · ${v.uncovered} from teams outside every site are not checked`) : '';
    if (v.state === 'ok' && v.final) return ['✓ ' + T(`VALIDADO (${hm(v.final_at || v.at)}): a prova acabou e o Animeitor tem as ${v.checked} submissões`, `VALIDATED (${hm(v.final_at || v.at)}): the contest is over and the Animeitor has all ${v.checked} submissions`) + unc, ''];
    if (v.state === 'ok') return ['✓ ' + T(`conferido às ${at}: o Animeitor tem as ${v.checked} submissões`, `checked at ${at}: the Animeitor has all ${v.checked} submissions`)
      + (v.pending ? T(` (${v.pending} ainda em julgamento)`, ` (${v.pending} still being judged)`) : '') + unc, ''];
    return ['⚠ ' + T(`divergência às ${at}: ${v.missing} faltando, ${v.wrong} diferentes, ${v.extra} a mais no Animeitor — já reenviadas; o alimentador confere de novo`,
      `mismatch at ${at}: ${v.missing} missing, ${v.wrong} different, ${v.extra} extra on the Animeitor — already resent; the feeder checks again`), 'error-box'];
  };

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
    const own = S.cred_source === 'contest';
    const tok = el('input', { type: 'password', size: 22, autocomplete: 'new-password',
      placeholder: own ? T('(gravado — digite p/ trocar)', '(saved — type to replace)') : 'token', 'aria-label': 'token' });
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
    // a CHAVE: a do MOJ vale por padrão (e nunca aparece); a própria vence e pode ser apagada (volta p/ a do MOJ)
    const backToMoj = async () => {
      if (!confirm(T('Apagar a chave própria deste contest e voltar a usar a chave do MOJ?', 'Delete this contest\'s own key and go back to the MOJ key?'))) return;
      say('…'); try { await post({ action: 'config', user: '', token: '' }); await load(); say(T('Usando a chave do MOJ.', 'Using the MOJ key.')); } catch (e) { say(e.message || T('falha', 'failed'), 'error-box'); }
    };
    const credFields = el('span', { class: 'row', style: 'gap:.4rem' }, user, tok);
    let keyRow;
    if (S.cred_source === 'moj') {
      keyRow = el('div', { style: 'margin:.25rem 0' },
        el('div', { class: 'small' }, '🔑 ', el('b', {}, T('Chave do MOJ', 'MOJ key')), ' — ',
          T('o MOJ já tem uma chave neste servidor do Animeitor; não há nada a configurar.', 'MOJ already has a key on this Animeitor server; there is nothing to configure.')),
        el('details', { style: 'margin-top:.2rem' }, el('summary', { class: 'small' }, T('usar uma chave própria', 'use your own key')),
          row(T('Usuário e token:', 'User and token:'), credFields, T('vence a do MOJ; o token nunca volta para a tela', 'overrides the MOJ key; the token is never sent back to the page'))));
    } else if (own) {
      keyRow = el('div', {},
        row(T('Chave própria:', 'Own key:'), credFields, T('o token nunca volta para a tela', 'the token is never sent back to the page')),
        S.moj_cred ? el('div', { class: 'small', style: 'margin:.1rem 0 .3rem' }, el('button', { class: 'btn ghost', onclick: backToMoj }, T('apagar e usar a chave do MOJ', 'delete it and use the MOJ key'))) : '');
    } else {
      keyRow = el('div', {},
        S.moj_cred && S.url !== S.default_url ? el('p', { class: 'note' }, T(`A chave do MOJ só vale no servidor padrão (${S.default_url}). Para este servidor, grave uma chave própria — ou volte ao servidor padrão.`,
          `The MOJ key only works on the default server (${S.default_url}). For this server, save your own key — or go back to the default server.`)) : '',
        row(T('Usuário e token:', 'User and token:'), credFields, T('o token nunca volta para a tela', 'the token is never sent back to the page')));
    }
    return el('div', {},
      el('h3', {}, T('Conexão', 'Connection')),
      row(T('Servidor do Animeitor:', 'Animeitor server:'), url, T('só https', 'https only')),
      keyRow,
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
        el('button', { class: 'btn ghost', disabled: !S.configured, onclick: () => busy(async () => {
          say(T('Conferindo sede a sede…', 'Checking site by site…'));
          const r = await verifyNow();
          const [t, cls] = verifyText(r.verify);
          const b = r.before ? T(` (antes: ${r.before.missing} faltando, ${r.before.wrong} diferentes, ${r.before.extra} a mais — reenviadas)`, ` (before: ${r.before.missing} missing, ${r.before.wrong} different, ${r.before.extra} extra — resent)`) : '';
          say(t + b, cls === 'muted' ? '' : cls); await refresh();
        }) }, T('🔎 conferir agora', '🔎 check now')),
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
    if (S.managed && S.managed.event) {
      const [vt, vc] = verifyText(S.verify);
      statusBox.append(el('div', { class: vc === 'error-box' ? 'error-box' : (vc === 'muted' ? 'muted' : ''), style: 'margin-top:.3rem', id: 'anVerify' }, T('Conferência: ', 'Check: ') + vt));
    }
    if (dead) statusBox.append(el('div', { class: 'error-box', style: 'margin-top:.3rem' },
      T('O processo alimentador não está rodando no servidor do MOJ: o relógio do telão está PARADO. Avise o administrador do servidor (serviço animeitor-feed).',
        'The feeder process is not running on the MOJ server: the big-screen clock is STOPPED. Tell the server administrator (animeitor-feed service).')));
    if (st.last_error) statusBox.append(el('div', { class: 'error-box', style: 'margin-top:.3rem' },
      T('Último erro', 'Last error') + ' (' + st.last_error.where + (st.last_error.http ? ', HTTP ' + st.last_error.http : '') + ', ' + new Date(st.last_error.at * 1000).toLocaleTimeString() + '): ' + (st.last_error.message || '')));
  }
  async function refresh(withLinks) {
    const s = await apiGet(A + (withLinks ? '&links=1' : ''), G);
    ['status', 'clock', 'enabled', 'now', 'managed', 'configured', 'feeder_alive_at', 'reveal', 'verify'].forEach((k) => { S[k] = s[k]; });
    if (s.links) { S.links = s.links; drawLinks(); }
    drawStatus(); drawOpsBtn(); arm();
  }
  function drawLinks() {
    linksBox.innerHTML = '';
    // o interruptor de liberar p/ as sedes fica SEMPRE à vista (é decisão de cerimônia, não detalhe dos links)
    linksBox.append(el('h3', {}, T('Links do telão', 'Big-screen links')), revealSwitch());
    const L = S.links; if (!L) { linksBox.append(el('button', { class: 'btn ghost', disabled: !S.configured, onclick: () => refresh(true).catch((e) => say(e.message, 'error-box')) }, T('mostrar os links do telão', 'show the big-screen links'))); return; }
    const copy = (u) => el('button', { class: 'btn ghost', onclick: async () => { try { await navigator.clipboard.writeText(u); } catch { prompt(T('Copie:', 'Copy:'), u); } } }, T('copiar', 'copy'));
    const tbl = (rows) => el('table', { class: 'moj' }, el('tbody', {}, ...rows));
    linksBox.append(
      tbl((L.public || []).map((x) => el('tr', {}, el('td', {}, x.contest), el('td', {}, el('a', { href: x.url, target: '_blank', rel: 'noopener' }, x.url)), el('td', {}, copy(x.url))))),
      el('p', { class: 'note' }, '⚠ ', T('Os links de REVELAÇÃO mostram as respostas depois do congelamento. Cada sede tem o seu. Trate como senha: entregue só ao responsável da sede.',
        'The REVEAL links show the answers after the freeze. Each site has its own. Treat them as passwords: give each one only to the person in charge of that site.')),
      el('details', {}, el('summary', {}, T(`${(L.revelation || []).length} links de revelação`, `${(L.revelation || []).length} reveal links`)),
        tbl((L.revelation || []).map((x) => el('tr', {}, el('td', {}, x.contest), el('td', {}, x.site), el('td', { class: 'small' }, el('code', {}, x.url.replace(/secret=[^&]+/, 'secret=…'))), el('td', {}, copy(x.url)))))));
    // ZERO links: o link de revelação do Animeitor é POR SEDE — placar publicado sem sede não gera link, e
    // liberar o reveleitor não tem o que liberar (XIV Maratona UnB, 25/09/2026, prova de sede única).
    if (!(L.revelation || []).length) {
      linksBox.append(el('p', { class: 'error-box' }, T('Nenhum link de revelação: os placares publicados não têm SEDE, e o link de revelação é por sede. Numa prova de sede única, abra "Placares e sedes", use "+ sede" no placar Geral (nome, ex.: Geral; códigos: .*) e publique de novo.',
        'No reveal links: the published scoreboards have no SITE, and reveal links are per site. In a single-site contest, open "Scoreboards and sites", use "+ site" on the Geral scoreboard (name, e.g. Geral; codes: .*) and publish again.')));
    }
  }
  // o interruptor ÚNICO: liberar/recolher os links do reveleitor p/ as sedes (.cstaff/.staff veem só os da sede deles)
  function revealSwitch() {
    const rv = S.reveal || {}, on = !!rv.released;
    return el('div', { class: 'row', style: 'gap:.6rem;align-items:center;flex-wrap:wrap;margin:.4rem 0' },
      el('button', { class: on ? 'btn ghost danger' : 'btn', id: 'anRevealBtn', onclick: async () => {
        // antes de liberar, CONFERE: o reveleitor revela o que o Animeitor tem — e o operador precisa saber se é tudo
        let vt = '';
        if (!on) {
          say(T('Conferindo sede a sede antes de liberar…', 'Checking site by site before releasing…'));
          try { const r = await verifyNow(); vt = verifyText(r.verify)[0]; } catch (e) { vt = '⚠ ' + T('a conferência falhou: ', 'the check failed: ') + (e.message || ''); }
          say('');
        }
        if (!on && !confirm(T('Conferência: ', 'Check: ') + vt + '\n\n' + T('Liberar os links de revelação para as sedes? Cada chefe de sede e cada staff passa a ver os links da sede dele (em todos os placares em que ela aparece), com o resultado da conferência. Quem não tem sede definida não vê nenhum.',
          'Release the reveal links to the sites? Each site chief and each staff member will see the links of their own site (in every scoreboard that includes it), with the check result. Accounts with no site defined see none.'))) return;
        say('…');
        try { await post({ action: on ? 'reveal-recall' : 'reveal-release' }); say(''); await refresh(); drawLinks(); }
        catch (e) { say(e.message || T('falha', 'failed'), 'error-box'); }
      } }, on ? T('recolher os links das sedes', 'take the links back from the sites') : T('🎬 liberar os links de revelação para as sedes', '🎬 release the reveal links to the sites')),
      el('span', { class: 'small' + (on ? '' : ' muted') }, on
        ? T('LIBERADO para as sedes', 'RELEASED to the sites') + (rv.at ? ' · ' + new Date(rv.at * 1000).toLocaleTimeString() : '') + (rv.by ? ' · ' + rv.by : '')
        : T('as sedes ainda não veem nenhum link', 'the sites do not see any link yet')));
  }

  async function verifyNow() { const r = await post({ action: 'verify' }); S.verify = r.verify; return r; }

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
