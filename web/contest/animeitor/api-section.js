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
import { T, uiLocale } from '/shared/i18n.js';

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
  const srcName = (s) => ({ view: T('visão do placar', 'scoreboard view', 'vista del marcador'), region: T('região', 'region', 'región'), manual: T('manual', 'manual', 'manual') }[(s || {}).kind] || '—');
  const clone = (x) => JSON.parse(JSON.stringify(x));
  const fromProposal = (p) => ((p && p.contests) || []).map((c) => ({ name: c.name, source: c.source, codes: null, ouro: 1, prata: 2, bronze: 3, style: null,
    sites: (c.sites || []).map((s) => ({ name: s.name, source: s.source, codes: null })) }));
  const propOf = (src) => ((S.proposal && S.proposal.contests) || []).find((c) => JSON.stringify(c.source) === JSON.stringify(src));
  const hm = (e) => new Date(e * 1000).toLocaleTimeString(uiLocale());
  // o resultado da CONFERÊNCIA em uma frase (o mesmo texto no estado ao vivo, no botão e antes de liberar)
  const verifyText = (v) => {
    if (!v || !v.at) return [T('ainda não conferido', 'not checked yet', 'todavía no verificado'), 'muted'];
    const at = hm(v.at);
    if (v.state === 'not_started') return [T('a prova ainda não começou: o Animeitor só deixa conferir depois do início', 'the contest has not started: the Animeitor only allows checking after the start', 'la competencia todavía no empezó: el Animeitor solo permite verificar después del inicio'), 'muted'];
    if (v.state === 'no_sites') return [T('nenhuma sede publicada cobre os times: a conferência é feita sede a sede (publique com as sedes)', 'no published site covers the teams: the check is done site by site (publish with the sites)', 'ninguna sede publicada cubre a los equipos: la verificación se hace sede por sede (publica con las sedes)'), 'error-box'];
    if (v.state === 'error') return [T(`a conferência falhou (${at}): `, `the check failed (${at}): `, `la verificación falló (${at}): `) + (v.error || ''), 'error-box'];
    const unc = v.uncovered ? T(` · ${v.uncovered} de times fora de qualquer sede não entram na conferência`, ` · ${v.uncovered} from teams outside every site are not checked`, ` · ${v.uncovered} de equipos fuera de cualquier sede no entran en la verificación`) : '';
    if (v.state === 'ok' && v.final) return ['✓ ' + T(`VALIDADO (${hm(v.final_at || v.at)}): a prova acabou e o Animeitor tem as ${v.checked} submissões`, `VALIDATED (${hm(v.final_at || v.at)}): the contest is over and the Animeitor has all ${v.checked} submissions`, `VALIDADO (${hm(v.final_at || v.at)}): la competencia terminó y el Animeitor tiene los ${v.checked} envíos`) + unc, ''];
    if (v.state === 'ok') return ['✓ ' + T(`conferido às ${at}: o Animeitor tem as ${v.checked} submissões`, `checked at ${at}: the Animeitor has all ${v.checked} submissions`, `verificado a las ${at}: el Animeitor tiene los ${v.checked} envíos`)
      + (v.pending ? T(` (${v.pending} ainda em julgamento)`, ` (${v.pending} still being judged)`, ` (${v.pending} todavía en evaluación)`) : '') + unc, ''];
    return ['⚠ ' + T(`divergência às ${at}: ${v.missing} faltando, ${v.wrong} diferentes, ${v.extra} a mais no Animeitor — já reenviadas; o alimentador confere de novo`,
      `mismatch at ${at}: ${v.missing} missing, ${v.wrong} different, ${v.extra} extra on the Animeitor — already resent; the feeder checks again`,
      `discrepancia a las ${at}: ${v.missing} faltantes, ${v.wrong} diferentes, ${v.extra} de más en el Animeitor — ya reenviadas; el alimentador verifica de nuevo`), 'error-box'];
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
    const user = el('input', { type: 'text', value: S.user || '', size: 14, autocomplete: 'off', 'aria-label': T('usuário', 'user', 'usuario') });
    const own = S.cred_source === 'contest';
    const tok = el('input', { type: 'password', size: 22, autocomplete: 'new-password',
      placeholder: own ? T('(gravado — digite p/ trocar)', '(saved — type to replace)', '(guardado — escribe para reemplazar)') : 'token', 'aria-label': 'token' });
    const ev = el('input', { type: 'text', value: S.event || CONTEST, size: 24, 'aria-label': T('evento', 'event', 'evento') });
    // a foto/música do time são buscadas pelo TELÃO direto no MOJ: precisa da URL pública, que não é a
    // do subdomínio do contest
    const guess = S.moj_base_url || String(location.origin || '').replace('//' + CONTEST + '.', '//');
    const base = el('input', { type: 'text', value: guess, size: 30, 'aria-label': T('URL pública do MOJ', 'MOJ public URL', 'URL pública del MOJ') });
    const save = async (test) => {
      say('…');
      try {
        const body = { action: 'config', url: url.value.trim(), event: ev.value.trim(), moj_base_url: base.value.trim() };
        if (tok.value || user.value !== (S.user || '')) { body.user = user.value.trim(); body.token = tok.value; }
        await post(body);
        if (test) {
          const r = await post({ action: 'test' });
          say(r.event_exists
            ? (r.managed ? T('Conexão ok. O evento já existe e é deste contest.', 'Connection ok. The event exists and belongs to this contest.', 'Conexión ok. El evento ya existe y es de esta competencia.')
              : T('Conexão ok. ⚠ Já existe um evento com esse nome que NÃO foi criado por este contest.', 'Connection ok. ⚠ An event with this name already exists and was NOT created by this contest.', 'Conexión ok. ⚠ Ya existe un evento con ese nombre que NO fue creado por esta competencia.'))
            : T('Conexão ok. O evento ainda não existe lá: publique para criar.', 'Connection ok. The event does not exist there yet: publish to create it.', 'Conexión ok. El evento todavía no existe allá: publica para crearlo.'));
        } else say(T('Gravado.', 'Saved.', 'Guardado.'));
        const keep = msgBox.textContent; await load(); say(keep);
      } catch (e) { say(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
    };
    const row = (lbl, inp, hint) => el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap;margin:.25rem 0' },
      el('label', { class: 'small', style: 'min-width:11rem' }, lbl), inp, hint ? el('span', { class: 'small muted' }, hint) : '');
    // a CHAVE: a do MOJ vale por padrão (e nunca aparece); a própria vence e pode ser apagada (volta p/ a do MOJ)
    const backToMoj = async () => {
      if (!confirm(T('Apagar a chave própria deste contest e voltar a usar a chave do MOJ?', 'Delete this contest\'s own key and go back to the MOJ key?', '¿Eliminar la clave propia de esta competencia y volver a usar la clave del MOJ?'))) return;
      say('…'); try { await post({ action: 'config', user: '', token: '' }); await load(); say(T('Usando a chave do MOJ.', 'Using the MOJ key.', 'Usando la clave del MOJ.')); } catch (e) { say(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
    };
    const credFields = el('span', { class: 'row', style: 'gap:.4rem' }, user, tok);
    let keyRow;
    if (S.cred_source === 'moj') {
      keyRow = el('div', { style: 'margin:.25rem 0' },
        el('div', { class: 'small' }, '🔑 ', el('b', {}, T('Chave do MOJ', 'MOJ key', 'Clave del MOJ')), ' — ',
          T('o MOJ já tem uma chave neste servidor do Animeitor; não há nada a configurar.', 'MOJ already has a key on this Animeitor server; there is nothing to configure.', 'el MOJ ya tiene una clave en este servidor del Animeitor; no hay nada que configurar.')),
        el('details', { style: 'margin-top:.2rem' }, el('summary', { class: 'small' }, T('usar uma chave própria', 'use your own key', 'usar una clave propia')),
          row(T('Usuário e token:', 'User and token:', 'Usuario y token:'), credFields, T('vence a do MOJ; o token nunca volta para a tela', 'overrides the MOJ key; the token is never sent back to the page', 'prevalece sobre la del MOJ; el token nunca vuelve a la pantalla'))));
    } else if (own) {
      keyRow = el('div', {},
        row(T('Chave própria:', 'Own key:', 'Clave propia:'), credFields, T('o token nunca volta para a tela', 'the token is never sent back to the page', 'el token nunca vuelve a la pantalla')),
        S.moj_cred ? el('div', { class: 'small', style: 'margin:.1rem 0 .3rem' }, el('button', { class: 'btn ghost', onclick: backToMoj }, T('apagar e usar a chave do MOJ', 'delete it and use the MOJ key', 'eliminarla y usar la clave del MOJ'))) : '');
    } else {
      keyRow = el('div', {},
        S.moj_cred && S.url !== S.default_url ? el('p', { class: 'note' }, T(`A chave do MOJ só vale no servidor padrão (${S.default_url}). Para este servidor, grave uma chave própria — ou volte ao servidor padrão.`,
          `The MOJ key only works on the default server (${S.default_url}). For this server, save your own key — or go back to the default server.`,
          `La clave del MOJ solo funciona en el servidor predeterminado (${S.default_url}). Para este servidor, guarda una clave propia — o vuelve al servidor predeterminado.`)) : '',
        row(T('Usuário e token:', 'User and token:', 'Usuario y token:'), credFields, T('o token nunca volta para a tela', 'the token is never sent back to the page', 'el token nunca vuelve a la pantalla')));
    }
    return el('div', {},
      el('h3', {}, T('Conexão', 'Connection', 'Conexión')),
      row(T('Servidor do Animeitor:', 'Animeitor server:', 'Servidor del Animeitor:'), url, T('só https', 'https only', 'solo https')),
      keyRow,
      // com a chave do MOJ o evento NOVO nasce `moj-<nome>` (regra do Animeitor p/ a chave compartilhada): o
      // servidor põe o prefixo e a tela mostra o nome efetivo; evento que já existe segue com o nome dele
      row(T('Nome do evento lá:', 'Event name there:', 'Nombre del evento allá:'), ev, [
        S.cred_source === 'moj' ? T('com a chave do MOJ, evento novo começa com moj- (o MOJ põe o prefixo)', 'with the MOJ key, a new event starts with moj- (MOJ adds the prefix)', 'con la clave del MOJ, un evento nuevo empieza con moj- (el MOJ agrega el prefijo)') : '',
        S.secret_contest ? T('⚠ contest secreto: este NOME fica público na página inicial do Animeitor', '⚠ secret contest: this NAME is public on the Animeitor landing page', '⚠ competencia secreta: este NOMBRE queda público en la página inicial del Animeitor') : '',
      ].filter(Boolean).join(' · ')),
      row(T('URL pública do MOJ:', 'MOJ public URL:', 'URL pública del MOJ:'), base, T('de onde o telão busca a foto e a música de cada time', 'where the big screen fetches each team photo and music', 'de donde la pantalla obtiene la foto y la música de cada equipo')),
      el('div', { class: 'row', style: 'gap:.5rem;margin:.4rem 0' },
        el('button', { class: 'btn', onclick: () => save(true) }, T('gravar e testar', 'save and test', 'guardar y probar')),
        el('button', { class: 'btn ghost', onclick: () => save(false) }, T('só gravar', 'save only', 'solo guardar'))));
  }

  // ---- placares e sedes ---------------------------------------------------------------------
  const touch = () => { DIRTY = true; dirtyNote.textContent = T('alterações não salvas', 'unsaved changes', 'cambios sin guardar'); };
  const dirtyNote = el('span', { class: 'small', style: 'color:var(--warn,#b9770e)' });
  const codesCell = (obj, isSite, parentSrc) => {
    const auto = el('input', { type: 'checkbox', checked: obj.codes == null, disabled: (obj.source || {}).kind === 'manual' });
    const ta = el('textarea', { rows: 1, cols: 28, style: 'font-family:monospace;font-size:.8rem', placeholder: T('um regex de login por linha', 'one login regex per line', 'un regex de usuario por línea') },
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
    return el('div', {}, el('label', { class: 'small' }, auto, ' ' + T('automático', 'automatic', 'automático')), ta);
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
          (s.source || {}).kind === 'whole' ? el('span', { class: 'small muted', style: 'align-self:center' },
            T('todos os times · link só da organização', 'all teams · link for the organization only', 'todos los equipos · enlace solo de la organización')) : null,
          el('button', { class: 'btn ghost', title: T('remover sede', 'remove site', 'quitar sede'), onclick: () => { c.sites.splice(si, 1); touch(); drawSites(); } }, '×'))));
        sitesBox.append(el('button', { class: 'btn ghost', onclick: () => { c.sites.push({ name: '', source: { kind: 'manual', id: '' }, codes: [] }); touch(); drawSites(); } }, T('+ sede', '+ site', '+ sede')));
        // placar GERAL (visão pública/todos) sem a sede de TODOS os times = reveleitor sem resultado geral (TCP 2026)
        const src = c.source || {};
        if (src.kind === 'view' && (src.id === 'public' || src.id === 'all') && !c.sites.some((s) => (s.source || {}).kind === 'whole')) {
          sitesBox.append(' ', el('button', { class: 'btn', onclick: () => {
            const nm = c.sites.some((s) => (s.name || '').toLowerCase() === 'geral') ? 'Geral (todos)' : 'Geral';
            c.sites.unshift({ name: nm, source: { kind: 'whole', id: src.id }, codes: null }); touch(); drawSites();
          } }, T('+ sede Geral (todos os times)', '+ Overall site (all teams)', '+ sede General (todos los equipos)')));
        }
      };
      drawSites();
      tb.append(el('tr', {},
        el('td', {}, nameInp(c), el('div', { class: 'small muted' }, srcName(c.source) + (p ? ' · ' + T(`${p.n} times`, `${p.n} teams`, `${p.n} equipos`) : ''))),
        el('td', {}, codesCell(c, false)),
        el('td', { class: 'n' }, num(c, 'ouro')), el('td', { class: 'n' }, num(c, 'prata')), el('td', { class: 'n' }, num(c, 'bronze')),
        el('td', {}, el('details', {}, el('summary', { class: 'small' }, T(`${c.sites.length} sedes`, `${c.sites.length} sites`, `${c.sites.length} sedes`)), sitesBox)),
        el('td', {}, el('button', { class: 'btn ghost danger', title: T('remover placar', 'remove scoreboard', 'quitar marcador'), onclick: () => { EDIT.splice(ci, 1); touch(); redrawBoards(); } }, '×'))));
    });
    const saveBoards = async () => {
      say('…');
      try { await post({ action: 'save', contests: EDIT }); DIRTY = false; dirtyNote.textContent = ''; say(T('Placares salvos. Publique para levar ao telão.', 'Scoreboards saved. Publish to send them to the big screen.', 'Marcadores guardados. Publica para llevarlos a la pantalla.')); return true; }
      catch (e) { say(e.message || T('falha', 'failed', 'fallido'), 'error-box'); return false; }
    };
    boardsHost.saveBoards = saveBoards;
    return el('div', {},
      el('h3', {}, T('Placares e sedes', 'Scoreboards and sites', 'Marcadores y sedes')),
      el('p', { class: 'note' }, T('Cada placar é uma tela do telão. O MOJ propõe o geral, um por coorte e um por país, com as sedes de cada um. "Automático" usa o recorte do próprio MOJ e acompanha time novo a cada publicação. Ouro, prata e bronze são a última colocação que recebe cada medalha.',
        'Each scoreboard is one big-screen view. MOJ proposes the general one, one per cohort and one per country, with their sites. "Automatic" uses the MOJ selection and follows new teams at each publish. Gold, silver and bronze are the last place that gets each medal.',
        'Cada marcador es una vista de la pantalla. El MOJ propone el general, uno por cohorte y uno por país, con las sedes de cada uno. "Automático" usa el recorte del propio MOJ y sigue a los equipos nuevos en cada publicación. Oro, plata y bronce son el último puesto que recibe cada medalla.')),
      el('div', { class: 'chart-wrap' }, el('table', { class: 'moj' },
        el('thead', {}, el('tr', {}, el('th', {}, T('Placar', 'Scoreboard', 'Marcador')), el('th', {}, T('Times (regex de login)', 'Teams (login regex)', 'Equipos (regex de usuario)')),
          el('th', { class: 'n' }, T('Ouro', 'Gold', 'Oro')), el('th', { class: 'n' }, T('Prata', 'Silver', 'Plata')), el('th', { class: 'n' }, T('Bronze', 'Bronze', 'Bronce')),
          el('th', {}, T('Sedes', 'Sites', 'Sedes')), el('th', {}, ''))), tb)),
      el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap;margin:.4rem 0' },
        el('button', { class: 'btn ghost', onclick: () => { EDIT.push({ name: '', source: { kind: 'manual', id: '' }, codes: [], ouro: 1, prata: 2, bronze: 3, style: null, sites: [] }); touch(); redrawBoards(); } }, T('+ placar manual', '+ manual scoreboard', '+ marcador manual')),
        el('button', { class: 'btn ghost', onclick: () => { if (!confirm(T('Descartar a revisão e voltar à proposta do MOJ?', 'Discard the review and go back to the MOJ proposal?', '¿Descartar la revisión y volver a la propuesta del MOJ?'))) return; EDIT = fromProposal(S.proposal); touch(); redrawBoards(); } }, T('voltar à proposta', 'back to the proposal', 'volver a la propuesta')),
        el('button', { class: 'btn', onclick: saveBoards }, T('salvar placares', 'save scoreboards', 'guardar marcadores')), dirtyNote));
  }
  const boardsHost = el('div', {});
  const redrawBoards = () => { boardsHost.innerHTML = ''; boardsHost.append(boardsCard()); };

  // ---- operação ---------------------------------------------------------------------------
  function opsCard() {
    const busy = async (fn) => { say('…'); try { await fn(); } catch (e) { say(e.message || T('falha', 'failed', 'fallido'), 'error-box'); } };
    const publish = (adopt) => busy(async () => {
      if (DIRTY && !(await boardsHost.saveBoards())) return;
      let r;
      try { r = await post({ action: 'publish', adopt: !!adopt }); }
      catch (e) {
        if (e.code === 'event_exists' && confirm((e.message || '') + '\n\n' + T('Assumir este evento? Só faça isso se ele for mesmo deste contest.', 'Take over this event? Only do it if it really belongs to this contest.', '¿Asumir este evento? Hazlo solo si realmente pertenece a esta competencia.'))) return publish(true);
        throw e;
      }
      const res = r.result || {}, cs = res.contests || [];
      const bad = cs.filter((c) => c.action === 'error' || (c.sites || []).some((s) => s.action === 'error'));
      say(res.ok ? T(`Publicado: evento ${res.event.action}, ${cs.length} placares.`, `Published: event ${res.event.action}, ${cs.length} scoreboards.`, `Publicado: evento ${res.event.action}, ${cs.length} marcadores.`)
        : T('Publicado com recusas: ', 'Published with refusals: ', 'Publicado con rechazos: ') + bad.map((c) => c.name + (c.error ? ' — ' + c.error : '')).join(' · '), res.ok ? '' : 'error-box');
      await refresh(true);
    });
    return el('div', {},
      el('h3', {}, T('Operação', 'Operation', 'Operación')),
      el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
        el('button', { class: 'btn', disabled: !S.configured, onclick: () => publish(false) }, T('📡 publicar no telão', '📡 publish to the big screen', '📡 publicar en la pantalla')),
        el('button', { class: 'btn ghost', disabled: !S.configured, onclick: () => busy(async () => { const r = await post({ action: 'push-runs' }); say(T(`Submissões: ${r.runs.sent} enviadas (${r.runs.added} novas, ${r.runs.updated} corrigidas).`, `Submissions: ${r.runs.sent} sent (${r.runs.added} new, ${r.runs.updated} corrected).`, `Envíos: ${r.runs.sent} enviados (${r.runs.added} nuevos, ${r.runs.updated} corregidos).`) + (r.runs.error ? ' ' + r.runs.error : ''), r.runs.error ? 'error-box' : ''); await refresh(); }) }, T('mandar submissões agora', 'send submissions now', 'enviar soluciones ahora')),
        el('button', { class: 'btn ghost', disabled: !S.configured, onclick: () => busy(async () => {
          say(T('Conferindo sede a sede…', 'Checking site by site…', 'Verificando sede por sede…'));
          const r = await verifyNow();
          const [t, cls] = verifyText(r.verify);
          const b = r.before ? T(` (antes: ${r.before.missing} faltando, ${r.before.wrong} diferentes, ${r.before.extra} a mais — reenviadas)`, ` (before: ${r.before.missing} missing, ${r.before.wrong} different, ${r.before.extra} extra — resent)`, ` (antes: ${r.before.missing} faltantes, ${r.before.wrong} diferentes, ${r.before.extra} de más — reenviados)`) : '';
          say(t + b, cls === 'muted' ? '' : cls); await refresh();
        }) }, T('🔎 conferir agora', '🔎 check now', '🔎 verificar ahora')),
        el('button', { class: 'btn ghost', disabled: !S.configured, id: 'anFeedBtn', onclick: () => busy(async () => { await post({ action: S.enabled ? 'stop' : 'start' }); say(''); await refresh(); drawOpsBtn(); }) }, ''),
        el('button', { class: 'btn ghost danger', disabled: !S.configured, onclick: () => busy(async () => {
          const ev = S.event; const typed = prompt(T(`Isto APAGA o evento "${ev}" no servidor do Animeitor, com placares, sedes e submissões. Digite o nome do evento para confirmar:`, `This DELETES the event "${ev}" on the Animeitor server, with scoreboards, sites and submissions. Type the event name to confirm:`, `Esto BORRA el evento "${ev}" en el servidor del Animeitor, con marcadores, sedes y envíos. Escribe el nombre del evento para confirmar:`));
          if (typed == null) { say(''); return; }
          await post({ action: 'reset', confirm: typed }); say(T('Evento apagado lá.', 'Event deleted there.', 'Evento borrado allá.')); await load();
        }) }, T('apagar o evento lá', 'delete the event there', 'borrar el evento allá'))));
  }
  const drawOpsBtn = () => { const b = root.querySelector('#anFeedBtn'); if (b) b.textContent = S.enabled ? T('⏹ parar o alimentador', '⏹ stop the feeder', '⏹ detener el alimentador') : T('▶ ligar o alimentador (relógio e submissões)', '▶ start the feeder (clock and submissions)', '▶ iniciar el alimentador (reloj y envíos)'); };

  // ---- estado ao vivo (EM LUGAR) e links ----------------------------------------------------
  const hms = (t) => { const n = Math.abs(t), s = (t < 0 ? '−' : '') + [Math.floor(n / 3600), Math.floor(n / 60) % 60, n % 60].map((x) => String(x).padStart(2, '0')).join(':'); return s; };
  function drawStatus() {
    const st = S.status || {}, ck = S.clock, parts = [];
    parts.push(S.enabled ? T('alimentador LIGADO', 'feeder ON', 'alimentador ACTIVADO') : T('alimentador desligado', 'feeder off', 'alimentador desactivado'));
    const dead = S.enabled && (S.now - (S.feeder_alive_at || 0) > 15);
    if (st.published_at) parts.push(T('publicado às ', 'published at ', 'publicado a las ') + new Date(st.published_at * 1000).toLocaleTimeString(uiLocale()));
    if (ck) parts.push(T('relógio enviado: ', 'clock sent: ', 'reloj enviado: ') + hms(ck.time_seconds) + (S.now - ck.at > 5 && S.enabled ? T(` (há ${S.now - ck.at} s — o alimentador está rodando?)`, ` (${S.now - ck.at} s ago — is the feeder running?)`, ` (hace ${S.now - ck.at} s — ¿el alimentador está corriendo?)`) : '') + (ck.http && ck.http !== '200' ? ' ⚠ HTTP ' + ck.http : ''));
    if (st.runs) parts.push(T(`submissões: ${st.runs.total} no MOJ, ${st.runs.added || 0} criadas e ${st.runs.updated || 0} corrigidas lá`, `submissions: ${st.runs.total} in MOJ, ${st.runs.added || 0} created and ${st.runs.updated || 0} corrected there`, `envíos: ${st.runs.total} en el MOJ, ${st.runs.added || 0} creados y ${st.runs.updated || 0} corregidos allá`) + (st.runs.ignored ? T(` · ${st.runs.ignored} recusadas (time fora do evento: publique de novo)`, ` · ${st.runs.ignored} refused (team not in the event: publish again)`, ` · ${st.runs.ignored} rechazados (equipo fuera del evento: publica de nuevo)`) : ''));
    statusBox.innerHTML = '';
    statusBox.append(el('div', {}, parts.join(' · ')));
    if (S.managed && S.managed.event) {
      const [vt, vc] = verifyText(S.verify);
      statusBox.append(el('div', { class: vc === 'error-box' ? 'error-box' : (vc === 'muted' ? 'muted' : ''), style: 'margin-top:.3rem', id: 'anVerify' }, T('Conferência: ', 'Check: ', 'Verificación: ') + vt));
    }
    if (dead) statusBox.append(el('div', { class: 'error-box', style: 'margin-top:.3rem' },
      T('O processo alimentador não está rodando no servidor do MOJ: o relógio do telão está PARADO. Avise o administrador do servidor (serviço animeitor-feed).',
        'The feeder process is not running on the MOJ server: the big-screen clock is STOPPED. Tell the server administrator (animeitor-feed service).',
        'El proceso alimentador no está corriendo en el servidor del MOJ: el reloj de la pantalla está DETENIDO. Avisa al administrador del servidor (servicio animeitor-feed).')));
    if (st.last_error) statusBox.append(el('div', { class: 'error-box', style: 'margin-top:.3rem' },
      T('Último erro', 'Last error', 'Último error') + ' (' + st.last_error.where + (st.last_error.http ? ', HTTP ' + st.last_error.http : '') + ', ' + new Date(st.last_error.at * 1000).toLocaleTimeString(uiLocale()) + '): ' + (st.last_error.message || '')));
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
    linksBox.append(el('h3', {}, T('Links do telão', 'Big-screen links', 'Enlaces de la pantalla')), revealSwitch());
    const L = S.links; if (!L) { linksBox.append(el('button', { class: 'btn ghost', disabled: !S.configured, onclick: () => refresh(true).catch((e) => say(e.message, 'error-box')) }, T('mostrar os links do telão', 'show the big-screen links', 'mostrar los enlaces de la pantalla'))); return; }
    const copy = (u) => el('button', { class: 'btn ghost', onclick: async () => { try { await navigator.clipboard.writeText(u); } catch { prompt(T('Copie:', 'Copy:', 'Copia:'), u); } } }, T('copiar', 'copy', 'copiar'));
    const tbl = (rows) => el('table', { class: 'moj' }, el('tbody', {}, ...rows));
    linksBox.append(
      tbl((L.public || []).map((x) => el('tr', {}, el('td', {}, x.contest), el('td', {}, el('a', { href: x.url, target: '_blank', rel: 'noopener' }, x.url)), el('td', {}, copy(x.url))))),
      el('p', { class: 'note' }, '⚠ ', T('Os links de REVELAÇÃO mostram as respostas depois do congelamento. Cada sede tem o seu. Trate como senha: entregue só ao responsável da sede.',
        'The REVEAL links show the answers after the freeze. Each site has its own. Treat them as passwords: give each one only to the person in charge of that site.',
        'Los enlaces de REVELACIÓN muestran las respuestas después del congelamiento. Cada sede tiene el suyo. Trátalos como contraseñas: entrégalos solo al responsable de cada sede.')),
      el('details', {}, el('summary', {}, T(`${(L.revelation || []).length} links de revelação`, `${(L.revelation || []).length} reveal links`, `${(L.revelation || []).length} enlaces de revelación`),
          (S.reveal || {}).released ? null : el('span', { class: 'small muted' }, ' — ', T('prévia: ainda NÃO liberados às sedes', 'preview: NOT released to the sites yet', 'vista previa: todavía NO liberados a las sedes'))),
        // PRÉVIA (pedido do Ribas, 03/10/2026): abrir/copiar cada link e ver QUEM o receberá quando o reveleitor
        // for liberado — sem liberar nada. `L.sites` vem do servidor com a mesma regra do /reveal.
        el('table', { class: 'moj' },
          el('thead', {}, el('tr', {}, el('th', {}, T('Placar', 'Scoreboard', 'Marcador')), el('th', {}, T('Sede', 'Site', 'Sede')),
            el('th', {}, T('Recebe quando liberar', 'Gets it on release', 'Lo recibe al liberar')), el('th', {}, 'URL'), el('th', {}, ''))),
          el('tbody', {}, ...(L.revelation || []).map((x) => {
            const info = (L.sites || []).find((s) => s.contest === x.contest && s.site === x.site);
            const who = !info ? el('span', { class: 'small muted' }, '?')
              : info.whole ? el('span', { class: 'small' }, T('só admin e .animeitor (todos os times)', 'admin and .animeitor only (all teams)', 'solo admin y .animeitor (todos los equipos)'))
              : (info.recipients || []).length ? el('span', { class: 'small' }, info.recipients.join(', '))
              : el('span', { class: 'small error' }, T('ninguém — nenhum .cstaff/.staff com esta sede no escopo', 'nobody — no .cstaff/.staff with this site in scope', 'nadie — ningún .cstaff/.staff con esta sede en el alcance'));
            return el('tr', {}, el('td', {}, x.contest), el('td', {}, x.site), el('td', {}, who),
              el('td', { class: 'small' }, el('code', {}, x.url.replace(/secret=[^&]+/, 'secret=…'))),
              el('td', {}, el('div', { class: 'row', style: 'gap:.3rem;flex-wrap:nowrap' },
                el('a', { class: 'btn ghost', href: x.url, target: '_blank', rel: 'noopener' }, T('abrir', 'open', 'abrir')), copy(x.url))));
          })))));
    // ZERO links: o link de revelação do Animeitor é POR SEDE — placar publicado sem sede não gera link, e
    // liberar o reveleitor não tem o que liberar (XIV Maratona UnB, 25/09/2026, prova de sede única).
    if (!(L.revelation || []).length) {
      linksBox.append(el('p', { class: 'error-box' }, T('Nenhum link de revelação: os placares publicados não têm SEDE, e o link de revelação é por sede. Abra "Placares e sedes", use "+ sede Geral (todos os times)" no placar Geral (ou "voltar à proposta", que já a traz) e publique de novo.',
        'No reveal links: the published scoreboards have no SITE, and reveal links are per site. Open "Scoreboards and sites", use "+ Overall site (all teams)" on the Geral scoreboard (or "back to the proposal", which already has it) and publish again.',
        'Ningún enlace de revelación: los marcadores publicados no tienen SEDE, y el enlace de revelación es por sede. Abre "Marcadores y sedes", usa "+ sede General (todos los equipos)" en el marcador Geral (o "volver a la propuesta", que ya la trae) y publica de nuevo.')));
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
          say(T('Conferindo sede a sede antes de liberar…', 'Checking site by site before releasing…', 'Verificando sede por sede antes de liberar…'));
          try { const r = await verifyNow(); vt = verifyText(r.verify)[0]; } catch (e) { vt = '⚠ ' + T('a conferência falhou: ', 'the check failed: ', 'la verificación falló: ') + (e.message || ''); }
          say('');
        }
        if (!on && !confirm(T('Conferência: ', 'Check: ', 'Verificación: ') + vt + '\n\n' + T('Liberar os links de revelação para as sedes? Cada chefe de sede e cada staff passa a ver os links da sede dele (em todos os placares em que ela aparece), com o resultado da conferência. Quem não tem sede definida não vê nenhum.',
          'Release the reveal links to the sites? Each site chief and each staff member will see the links of their own site (in every scoreboard that includes it), with the check result. Accounts with no site defined see none.',
          '¿Liberar los enlaces de revelación a las sedes? Cada jefe de sede y cada staff pasa a ver los enlaces de su sede (en todos los marcadores en que aparece), con el resultado de la verificación. Quien no tenga sede definida no ve ninguno.'))) return;
        say('…');
        try { await post({ action: on ? 'reveal-recall' : 'reveal-release' }); say(''); await refresh(); drawLinks(); }
        catch (e) { say(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
      } }, on ? T('recolher os links das sedes', 'take the links back from the sites', 'recoger los enlaces de las sedes') : T('🎬 liberar os links de revelação para as sedes', '🎬 release the reveal links to the sites', '🎬 liberar los enlaces de revelación a las sedes')),
      el('span', { class: 'small' + (on ? '' : ' muted') }, on
        ? T('LIBERADO para as sedes', 'RELEASED to the sites', 'LIBERADO a las sedes') + (rv.at ? ' · ' + new Date(rv.at * 1000).toLocaleTimeString(uiLocale()) : '') + (rv.by ? ' · ' + rv.by : '')
        : T('as sedes ainda não veem nenhum link', 'the sites do not see any link yet', 'las sedes todavía no ven ningún enlace')));
  }

  async function verifyNow() { const r = await post({ action: 'verify' }); S.verify = r.verify; return r; }

  function arm() {
    if (timer) { clearInterval(timer); timer = null; }
    if (S && S.enabled) timer = setInterval(() => (document.hidden ? null : refresh().catch(() => {})), 3000);
  }

  function render() {
    root.innerHTML = '';
    root.append(el('h2', {}, T('📡 Animeitor (telão)', '📡 Animeitor (big screen)', '📡 Animeitor (pantalla)')),
      el('p', { class: 'note' }, T('O MOJ envia ao servidor do Animeitor o evento (problemas e times), os placares e sedes, as submissões e o relógio da prova. As respostas vão sempre reais: quem congela o placar público e conduz a revelação é o Animeitor.',
        'MOJ sends the Animeitor server the event (problems and teams), the scoreboards and sites, the submissions and the contest clock. Answers are always the real ones: the Animeitor freezes the public scoreboard and runs the reveal.',
        'El MOJ envía al servidor del Animeitor el evento (problemas y equipos), los marcadores y sedes, los envíos y el reloj de la competencia. Las respuestas van siempre reales: quien congela el marcador público y conduce la revelación es el Animeitor.')),
      connCard(), boardsHost, opsCard(), msgBox, statusBox, linksBox);
    redrawBoards(); drawStatus(); drawOpsBtn(); drawLinks(); arm();
  }

  return { node: root, load };
}
