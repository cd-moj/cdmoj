// contest/admin/central-tab.js — "🏁 Central": a primeira tela do painel. Responde a duas
// perguntas e nada mais: **o que falta para começar** e **o que eu preciso gerar**.
//
// 1. Falta para começar  = /contest/admin/preflight renderizado como lista ACIONÁVEL — cada item
//    ganha um botão que abre o painel exato (mapa TARGET abaixo; checagem nova do servidor
//    aparece na hora, só não tem botão até entrar no mapa). Os itens OK ficam recolhidos: a
//    Central mostra o que falta, não o que já está feito.
// 2. Gerar = os artefatos da prova, cada cartão com o estado atual (documentos, etiquetas,
//    promover rodada com os bloqueadores, relatório, revelação, jplag).
// 3. Ao vivo = resumo curto do /dashboard (o painel completo é Operação › Situação).
// 4. Regras da prova = os 3 essenciais editáveis inline (início/fim/freeze); o resto em Regras.
import { el } from '/shared/ui.js';
import { apiGet, apiPost } from '/shared/api.js';
import { toLocalDT, dtToEpoch } from '/shared/contest-config/index.js';
import { field, swapIf, sigOf } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';
import { MODULES } from './modules.js';

const enc = encodeURIComponent;
const ICON = { ok: '🟢', warn: '🟡', fail: '🔴' };
// id da checagem do preflight -> [grupo, painel] onde ela se resolve
// (o botão "resolver →" só aparece se o painel-alvo está visível — módulo ligado; ver nav.js)
const TARGET = {
  window: ['central', 'regras'], fim: ['central', 'regras'], show_log: ['central', 'regras'],
  freeze: ['central', 'regras'], mode: ['central', 'regras'], langs: ['central', 'regras'],
  balloons_freeze: ['central', 'regras'], submit_cap: ['central', 'regras'], login_open: ['central', 'regras'],
  modules: ['central', 'modulos'],
  problems: ['prova', 'problemas'], pool_problems: ['prova', 'problemas'], pool: ['prova', 'problemas'],
  prob_names: ['prova', 'problemas'],
  report: ['prova', 'relatorio'],   // postflight (encerrar evento)
  esqueletos: ['prova', 'esqueletos'],
  users: ['pessoas', 'contas'], shared_users: ['pessoas', 'contas'],
  registration: ['pessoas', 'inscricoes'], reg_invites: ['pessoas', 'inscricoes'], reg_source: ['pessoas', 'inscricoes'],
  print: ['operacao', 'staff'], staff_filters: ['operacao', 'staff'],
  judges: ['operacao', 'situacao'], judges_cpus: ['operacao', 'situacao'], daemon: ['operacao', 'situacao'], manual: ['operacao', 'juizes'],
  // módulos de evento
  next_round: ['evento', 'rodadas'], reg_warmup: ['evento', 'rodadas'],
  docs: ['evento', 'documentos'], balloons: ['evento', 'baloes'],
  cohorts: ['evento', 'coortes'], reg_cohorts: ['evento', 'coortes'],
  tov: ['evento', 'sedes'], regions: ['evento', 'sedes'], classificacao: ['evento', 'classificacao'],
  ua_gate: ['maquinas', 'gate'], session_single: ['maquinas', 'gate'], site_lock: ['maquinas', 'gate'],
  site_short: ['maquinas', 'mlinux'], mlinux: ['maquinas', 'mlinux'],
};

export function makeCentralTab(CONTEST, opts = {}) {
  const G = { contest: CONTEST, auth: true };
  const go = opts.go || (() => {});
  const has = typeof opts.has === 'function' ? opts.has : () => true;          // módulo ligado?
  const visible = typeof opts.visible === 'function' ? opts.visible : () => true; // painel visível?
  const mods = typeof opts.mods === 'function' ? opts.mods : () => [];
  const panel = el('div', {});
  let timer = null;
  let lastSt = null;   // /contest/admin/settings do último load (o aquecer avisa se a prova já começou)

  const gcard = (title, state, ...actions) => el('div', { class: 'gen-card' },
    el('h4', {}, title), el('span', { class: 'st' }, state),
    el('div', { class: 'row', style: 'gap:.35rem;flex-wrap:wrap' }, ...actions));

  const num = (n) => (n == null ? '—' : String(n));
  // EM LUGAR: o tick de 15 s só refaz os cartões quando os NÚMEROS mudam (assinatura sem relógio)
  function renderLive(box, dash) {
    const j = (dash && dash.judges) || null, sub = (dash && dash.submissions) || null, rv = (dash && dash.review) || null;
    const sig = sigOf(sub && sub.pending, sub && sub.total, j && j.online, j && j.total, sub && sub.response && sub.response.p95_s, rv && rv.pending_total, rv && rv.conflicts);
    swapIf(box, sig, () => liveBuild(j, sub, rv));
  }
  function liveBuild(j, sub, rv) {
    const dc = (val, label, warn) => el('div', { class: 'dash-card' + (warn ? ' warn' : '') },
      el('div', { class: 'dash-val' }, val), el('div', { class: 'dash-lbl' }, label));
    const box = el('div', {});
    box.append(el('div', { class: 'row', style: 'gap:.6rem;align-items:baseline' },
      el('h2', { style: 'margin:.1rem 0' }, T('📡 Ao vivo', '📡 Live', '📡 En vivo')),
      el('span', { style: 'flex:1' }),
      el('button', { class: 'btn ghost', onclick: () => go('operacao', 'situacao') }, T('ver tudo →', 'see all →', 'ver todo →'))),
      el('div', { class: 'dash-cards' },
        dc(num(sub && sub.pending), T('pendentes', 'pending', 'pendientes'), sub && sub.pending > 0),
        dc(num(sub && sub.total), T('submissões na janela', 'submissions in window', 'envíos en la ventana')),
        dc(j ? `${j.online || 0}/${j.total || 0}` : '—', T('juízes online', 'judges online', 'jueces en línea'), j && j.total > 0 && !j.online),
        dc(num(sub && sub.response && sub.response.p95_s) + 's', T('resposta p95', 'p95 response', 'respuesta p95'), sub && sub.response && sub.response.p95_s > 120),
        dc(num(rv && rv.pending_total), T('na correção manual', 'in manual review', 'en revisión manual'), rv && rv.conflicts > 0)));
    return box;
  }

  // "🔥 Aquecer juízes" (item judges_warm): calibração dirigida SÓ p/ os pares juiz×problema frios.
  // Cada uma ocupa um slot do juiz por alguns minutos — depois do início, a confirmação diz isso.
  async function warmJudges(btn, msg) {
    const started = !!(lastSt && lastSt.start && Math.floor(Date.now() / 1000) >= lastSt.start);
    const ask = started
      ? T('A prova já começou. Cada calibração ocupa um slot do juiz por alguns minutos, e as submissões esperam atrás dela. Aquecer mesmo assim?',
          'The contest has already started. Each calibration takes one judge slot for a few minutes, and submissions wait behind it. Warm up anyway?',
          'La competencia ya empezó. Cada calibración ocupa un slot del juez por algunos minutos, y los envíos esperan detrás. ¿Calentar de todos modos?')
      : T('Mandar cada juiz frio calibrar os problemas que ainda não calibrou? Cada calibração ocupa um slot do juiz por alguns minutos.',
          'Ask each cold judge to calibrate the problems it has not calibrated yet? Each calibration takes one judge slot for a few minutes.',
          '¿Pedir a cada juez frío que calibre los problemas que todavía no calibró? Cada calibración ocupa un slot del juez por algunos minutos.');
    if (!confirm(ask)) return;
    btn.disabled = true; msg.textContent = T('⏳ pedindo…', '⏳ requesting…', '⏳ solicitando…');
    try {
      const r = await apiPost('/contest/admin/warm-judges?contest=' + enc(CONTEST), {}, G);
      const n = (r.sent || []).length;
      msg.textContent = n
        ? T(`✓ ${n} calibração(ões) pedida(s) — os juízes pegam no próximo heartbeat; rode o checklist de novo (↻) em alguns minutos.`,
            `✓ ${n} calibration(s) requested — the judges pick them up on the next heartbeat; run the checklist again (↻) in a few minutes.`,
            `✓ ${n} calibración(es) solicitada(s) — los jueces las recogen en el próximo heartbeat; ejecuta el checklist de nuevo (↻) en unos minutos.`)
        : T('Nada a pedir: os pares frios já estão aquecendo.', 'Nothing to request: the cold pairs are already warming up.', 'Nada que pedir: los pares fríos ya se están calentando.');
    } catch (e) {
      msg.textContent = T('Falhou: ', 'Failed: ', 'Falló: ') + ((e && e.message) || T('erro de rede', 'network error', 'error de red'));
      btn.disabled = false;
    }
  }

  function checkEl(c) {
    const t = TARGET[c.id];
    // label/detail vêm do servidor em PT + label_en/detail_en + label_es/detail_es (preflight.sh e
    // finish.sh, add3); T() faz a cascata es → en → pt, então campo ausente cai no idioma seguinte.
    const label = T(c.label, c.label_en || null, c.label_es || null);
    const detail = T(c.detail || '', c.detail_en || null, c.detail_es || null);
    let act = null;
    if (c.action === 'warm_judges') {
      const msg = el('span', { class: 'small muted' });
      const btn = el('button', { class: 'btn' }, T('🔥 Aquecer juízes', '🔥 Warm up judges', '🔥 Calentar jueces'));
      btn.onclick = () => warmJudges(btn, msg);
      act = el('div', { class: 'row', style: 'gap:.35rem;flex-wrap:wrap;align-items:center;margin-top:.35rem' }, btn, msg);
    } else if (c.action === 'apply_titles') {
      // item prob_names: nome = título do banco em OUTRO idioma ⇒ o título no idioma da prova (só nesses;
      // nome personalizado ou escolhido no Renomear o servidor não toca — cc_title_fixes)
      const msg = el('span', { class: 'small muted' });
      const btn = el('button', { class: 'btn' }, T('🌐 Usar os títulos no idioma da prova', '🌐 Use the titles in the contest language', '🌐 Usar los títulos en el idioma de la competencia'));
      btn.onclick = async () => {
        btn.disabled = true; msg.textContent = T('⏳ aplicando…', '⏳ applying…', '⏳ aplicando…');
        try {
          const r = await apiPost('/contest/admin/problems?contest=' + enc(CONTEST), { action: 'apply_titles' }, G);
          const n = (r.changed || []).length;
          // como o 🔥 Aquecer: a mensagem fica e o ↻ refaz o checklist (recarregar sozinho levava a tela ao topo)
          msg.textContent = n
            ? T(`✓ ${n} problema(s) renomeado(s): ${r.changed.map((x) => x.letter + ' ' + x.to).join('; ')}.`,
                `✓ ${n} problem(s) renamed: ${r.changed.map((x) => x.letter + ' ' + x.to).join('; ')}.`,
                `✓ ${n} problema(s) renombrado(s): ${r.changed.map((x) => x.letter + ' ' + x.to).join('; ')}.`)
            : T('Nada a trocar.', 'Nothing to change.', 'Nada que cambiar.');
        } catch (e) {
          msg.textContent = T('Falhou: ', 'Failed: ', 'Falló: ') + ((e && e.message) || T('erro de rede', 'network error', 'error de red'));
          btn.disabled = false;
        }
      };
      act = el('div', { class: 'row', style: 'gap:.35rem;flex-wrap:wrap;align-items:center;margin-top:.35rem' }, btn, msg);
    } else if (c.action === 'open_telao') {
      // a mesa do telão é página AVULSA (não é um painel daqui): o "resolver" vira link p/ ela
      act = el('div', { style: 'margin-top:.35rem' }, el('a', { class: 'btn ghost', href: '/contest/animeitor/?c=' + enc(CONTEST) },
        T('abrir a mesa do telão →', 'open the big-screen page →', 'abrir la página de la pantalla →')));
    }
    return el('div', { class: 'ck' },
      el('span', { class: 'ico' }, ICON[c.level] || '•'),
      el('span', { class: 'txt' }, el('b', {}, label), el('span', { class: 'small muted' }, detail), act),
      t && visible(t[1]) ? el('button', { class: 'btn ghost', onclick: () => go(t[0], t[1]) }, T('resolver →', 'fix →', 'resolver →')) : null);
  }

  async function load() {
    panel.innerHTML = '';
    const [pre, dash, docs, rd, st, fin] = await Promise.all([
      apiGet('/contest/admin/preflight?contest=' + enc(CONTEST), G).catch(() => null),
      apiGet('/contest/admin/dashboard?contest=' + enc(CONTEST), G).catch(() => null),
      apiGet('/contest/admin/docs?contest=' + enc(CONTEST), G).catch(() => null),
      apiGet('/contest/admin/rounds?contest=' + enc(CONTEST), G).catch(() => null),
      apiGet('/contest/admin/settings?contest=' + enc(CONTEST), G).catch(() => null),
      // erro NUNCA vira null mudo: o cartão "Depois da prova" sumia em silêncio (403 do
      // .cjudge, Maratona 29/08) — o load renderiza o erro quando o cartão era esperado.
      apiGet('/contest/admin/finish?contest=' + enc(CONTEST), G).catch((e) => ({ _err: (e && e.message) || T('falha de rede', 'network error', 'error de red') })),
    ]);

    lastSt = st || null;
    // ---------- 1. falta para começar ----------
    const checks = (pre && pre.checks) || [];
    const s = (pre && pre.summary) || { ok: 0, warn: 0, fail: 0 };
    // O checklist é CONSULTIVO: o MOJ não impede login nem submissão por causa dele. O rótulo dizia
    // "BLOQUEIAM a prova" e um professor entendeu (com razão) que o sistema travaria — não trava.
    const head = !pre ? el('span', { class: 'pill bad' }, T('não foi possível checar', 'could not check', 'no se pudo comprobar'))
      : s.fail > 0 ? el('span', { class: 'pill bad' }, T(`${s.fail} item(ns) crítico(s) — confira antes de começar`, `${s.fail} critical item(s) — check before you start`, `${s.fail} elemento(s) crítico(s) — revisa antes de empezar`))
        : s.warn > 0 ? el('span', { class: 'pill' }, T(`${s.warn} aviso(s) — nada crítico`, `${s.warn} warning(s) — nothing critical`, `${s.warn} aviso(s) — nada crítico`))
          : el('span', { class: 'pill ok' }, T('tudo pronto', 'all clear', 'todo listo'));
    const box1 = el('div', { class: 'section' },
      el('div', { class: 'row', style: 'gap:.6rem;align-items:baseline' },
        el('h2', { style: 'margin:.1rem 0' }, T('🚦 Falta para começar', '🚦 Before you start', '🚦 Antes de empezar')), head,
        el('span', { style: 'flex:1' }),
        el('button', { class: 'btn ghost', title: T('rodar de novo', 'run again', 'ejecutar de nuevo'), onclick: load }, '↻')));
    const bad = checks.filter((c) => c.level === 'fail').concat(checks.filter((c) => c.level === 'warn'));
    const good = checks.filter((c) => c.level === 'ok');
    bad.forEach((c) => box1.append(checkEl(c)));
    if (!bad.length) box1.append(el('div', { class: 'small muted', style: 'padding:.3rem 0' },
      T('Nenhum item pendente.', 'Nothing pending.', 'Nada pendiente.')));
    if (good.length) box1.append(el('details', { class: 'fgroup' },
      el('summary', {}, T(`${good.length} itens já conferidos`, `${good.length} items already checked`, `${good.length} elementos ya revisados`)),
      ...good.map(checkEl)));
    panel.append(box1);

    // ---------- 1½. depois da prova ------------------------------------------------------
    // Renderiza sempre que o cartão é ESPERADO (fim base já passou), mesmo quando
    // can_finish=false (prorrogação de sede) ou o GET falhou — sumir em silêncio foi o bug
    // da Maratona 29/08. can_act=false (juiz-chefe) = checklist somente-leitura.
    const postEnd = !st || !st.end || Math.floor(Date.now() / 1000) > st.end;
    if (fin && fin._err) {
      if (postEnd) panel.append(el('div', { class: 'section' },
        el('h2', { style: 'margin:.1rem 0' }, T('🏁 Depois da prova', '🏁 After the contest', '🏁 Después de la competencia')),
        el('div', { class: 'small error-box' },
          T('Não foi possível consultar o encerramento: ', 'Could not load the finish checklist: ', 'No se pudo cargar el checklist de cierre: ') + fin._err)));
    } else if (fin && (fin.can_finish || postEnd)) {
      const canAct = fin.can_act !== false;
      const fchecks = fin.checks || [];
      const fs = fin.summary || { ok: 0, warn: 0, fail: 0 };
      const fbad = fchecks.filter((c) => c.level === 'fail').concat(fchecks.filter((c) => c.level === 'warn'));
      const fgood = fchecks.filter((c) => c.level === 'ok');
      const fmsg = el('div', { class: 'small' });
      const npd = (fin.pending_docs || []).length;
      const btn = el('button', { class: 'btn' + (fs.fail ? '' : ' ghost') }, T('🏁 Encerrar evento', '🏁 Finish event', '🏁 Terminar evento'));
      const box = el('div', { class: 'section' },
        el('div', { class: 'row', style: 'gap:.6rem;align-items:baseline' },
          el('h2', { style: 'margin:.1rem 0' }, T('🏁 Depois da prova', '🏁 After the contest', '🏁 Después de la competencia')),
          !fin.can_finish ? el('span', { class: 'pill' }, T('aguardando o fim em todas as sedes', 'waiting for every site to finish', 'esperando a que todas las sedes terminen'))
            : fs.fail > 0 ? el('span', { class: 'pill bad' }, T(`${fs.fail} item(ns) ainda fechado(s)`, `${fs.fail} item(s) still closed`, `${fs.fail} elemento(s) todavía cerrado(s)`))
              : el('span', { class: 'pill ok' }, T('resultado liberado', 'results released', 'resultado liberado'))),
        el('div', { class: 'small muted', style: 'margin:.1rem 0 .5rem' },
          T('O botão abre o PLACAR (tira o congelamento) e publica os documentos já gerados. O resto continua sendo escolha sua — cada item abaixo tem o atalho para resolver.',
            'The button opens the SCOREBOARD (removes the freeze) and publishes the documents already generated. Everything else stays your call — each item below links to where it is fixed.',
            'El botón abre el MARCADOR (quita el congelamiento) y publica los documentos ya generados. Todo lo demás sigue siendo tu decisión — cada elemento abajo tiene el acceso directo para resolverlo.')));
      fbad.forEach((c) => box.append(checkEl(c)));
      if (fgood.length) box.append(el('details', { class: 'fgroup' },
        el('summary', {}, T(`${fgood.length} itens já liberados`, `${fgood.length} items already released`, `${fgood.length} elementos ya liberados`)),
        ...fgood.map(checkEl)));
      btn.addEventListener('click', async () => {
        const willFreeze = fchecks.some((c) => c.id === 'freeze' && c.level === 'fail');
        const what = [willFreeze ? T('descongelar o placar', 'unfreeze the scoreboard', 'descongelar el marcador') : null,
          npd ? T(`publicar ${npd} documento(s)`, `publish ${npd} document(s)`, `publicar ${npd} documento(s)`) : null].filter(Boolean);
        if (!what.length) { fmsg.className = 'small muted'; fmsg.textContent = T('Nada a fazer: já está tudo liberado.', 'Nothing to do: everything is already released.', 'Nada que hacer: ya está todo liberado.'); return; }
        // eslint-disable-next-line no-alert
        if (!confirm(T('Encerrar o evento vai: ', 'Finishing the event will: ', 'Terminar el evento va a: ') + what.join(T(' e ', ' and ', ' y ')) + '.\n\n'
          + T('Isso fica visível para todo mundo. Confirmar?', 'This becomes visible to everyone. Confirm?', 'Esto queda visible para todos. ¿Confirmar?'))) return;
        btn.disabled = true; fmsg.className = 'small'; fmsg.textContent = T('Encerrando…', 'Finishing…', 'Terminando…');
        try {
          const r = await apiPost('/contest/admin/finish?contest=' + enc(CONTEST), { action: 'finish' }, G);
          fmsg.textContent = '✓ ' + (r.done || []).map((d) => d.item).join(', ');
          setTimeout(load, 600);
        } catch (e) { fmsg.className = 'small error-box'; fmsg.textContent = e.message || T('falha', 'failed', 'fallido'); btn.disabled = false; }
      });
      if (!canAct) {
        box.append(el('div', { class: 'small muted', style: 'margin-top:.6rem' },
          T('Só o admin do contest pode encerrar — para o juiz-chefe este checklist é somente leitura.',
            'Only the contest admin can finish — for the chief judge this checklist is read-only.',
            'Solo el admin de la competencia puede terminarla — para el juez principal este checklist es de solo lectura.')));
      } else {
        if (!fin.can_finish) {
          btn.disabled = true;
          // can_finish também espera o fim geral + 1 min quando há freeze (freeze_release_at)
          const at = +fin.freeze_release_at || 0;
          btn.title = (at && Math.floor(Date.now() / 1000) < at)
            ? T('disponível a partir de ', 'available from ', 'disponible a partir de ') + new Date(at * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) + T(' (fim para todas as sedes + 1 min)', ' (end for every site + 1 min)', ' (fin para todas las sedes + 1 min)')
            : T('disponível depois do fim para todas as sedes', 'available after every site finishes', 'disponible después de que todas las sedes terminen');
        }
        box.append(el('div', { class: 'row', style: 'gap:.5rem;margin-top:.6rem;align-items:center' }, btn, fmsg));
      }
      panel.append(box);
    }

    // ---------- 2. gerar ----------
    const nd = docs ? (docs.docs || []).length : 0;
    const npub = docs ? (docs.docs || []).filter((d) => d.published).length : 0;
    const next = rd ? (rd.next || '') : '';
    const blk = (rd && rd.promote_ready && rd.promote_ready.blockers) || [];
    panel.append(el('div', { class: 'section' },
      el('h2', { style: 'margin:.1rem 0 .5rem' }, T('🧰 Gerar', '🧰 Generate', '🧰 Generar')),
      // cartões de módulo só com o módulo ligado (documentos, rodadas, telão); os comuns sempre
      el('div', { class: 'tcards' },
        !has('documentos') ? null : gcard(T('📄 Documentos da prova', '📄 Contest documents', '📄 Documentos de la competencia'),
          nd ? T(`${nd} gerado(s) · ${npub} publicado(s)`, `${nd} generated · ${npub} published`, `${nd} generado(s) · ${npub} publicado(s)`)
            : T('info sheet, caderno e folha de time limits (PDF+HTML, pt/en/es)', 'info sheet, booklet and time-limits sheet (PDF+HTML, pt/en/es)', 'info sheet, cuadernillo y hoja de time limits (PDF+HTML, pt/en/es)'),
          el('button', { class: 'btn', onclick: () => go('evento', 'documentos') }, T('abrir', 'open', 'abrir'))),
        gcard(T('🏷️ Etiquetas de credenciais', '🏷️ Credential badges', '🏷️ Etiquetas de credenciales'),
          T('folhas Pimaco A4 com login e senha', 'Pimaco A4 sheets with login and password', 'hojas Pimaco A4 con usuario y contraseña'),
          el('a', { class: 'btn', target: '_blank', href: '/contest/badges/?c=' + enc(CONTEST) }, T('abrir', 'open', 'abrir'))),
        !has('rodadas') ? null : gcard(T('🔁 Promover rodada', '🔁 Promote round', '🔁 Promover ronda'),
          next ? (blk.length ? T(`próxima: ${next} — ${blk.length} bloqueador(es)`, `next: ${next} — ${blk.length} blocker(s)`, `siguiente: ${next} — ${blk.length} bloqueador(es)`)
            : T(`próxima: ${next} — pronta para promover`, `next: ${next} — ready to promote`, `siguiente: ${next} — lista para promover`))
            : T('nenhuma rodada planejada (aquecimento → prova no mesmo contest)', 'no round planned (warm-up → contest in the same contest)', 'ninguna ronda planeada (calentamiento → competencia en la misma competencia)'),
          el('button', { class: 'btn' + (blk.length || !next ? ' ghost' : ''), onclick: () => go('evento', 'rodadas') }, T('abrir', 'open', 'abrir'))),
        gcard(T('📑 Relatório da prova', '📑 Contest report', '📑 Informe de la competencia'),
          T('tar.gz navegável e publicação como histórico (/relatorio/<contest>/)', 'browsable tar.gz and publication as history (/relatorio/<contest>/)', 'tar.gz navegable y publicación como historial (/relatorio/<contest>/)'),
          el('button', { class: 'btn', onclick: () => go('prova', 'relatorio') }, T('abrir', 'open', 'abrir'))),
        !has('telao') ? null : gcard(T('🏆 Cerimônia de revelação', '🏆 Reveal ceremony', '🏆 Ceremonia de revelación'),
          T('placar congelado → aberto, de baixo para cima', 'frozen → open scoreboard, bottom-up', 'marcador congelado → abierto, de abajo hacia arriba'),
          el('a', { class: 'btn', target: '_blank', href: '/contest/score/reveal.html?c=' + enc(CONTEST) }, T('abrir', 'open', 'abrir'))),
        !has('telao') ? null : gcard(T('🎥 Telão (Animeitor)', '🎥 Big screen (Animeitor)', '🎥 Pantalla (Animeitor)'),
          T('fotos e músicas dos times, pacote .zip e as chaves do webcast',
            'team photos and music, .zip package and the webcast keys',
            'fotos y música de los equipos, paquete .zip y las claves del webcast'),
          el('a', { class: 'btn ghost', target: '_blank', href: '/contest/animeitor/?c=' + enc(CONTEST) }, T('abrir', 'open', 'abrir'))),
        gcard(T('🔍 jplag (similaridade)', '🔍 jplag (similarity)', '🔍 jplag (similitud)'),
          T('compara as soluções aceitas entre os times', 'compares accepted solutions across teams', 'compara las soluciones aceptadas entre los equipos'),
          el('a', { class: 'btn ghost', target: '_blank', href: '/contest/jplag/?c=' + enc(CONTEST) }, T('abrir', 'open', 'abrir'))))));

    // ---------- 3. ao vivo (o ÚNICO bloco com auto-refresh: re-renderiza só ele, senão o
    // refresh apagaria o que o admin está digitando nas Regras abaixo) ----------
    const liveBox = el('div', { class: 'section' });
    panel.append(liveBox);
    renderLive(liveBox, dash);
    clearInterval(timer);
    timer = setInterval(async () => {
      if (panel.hidden || !panel.isConnected) return;
      const d2 = await apiGet('/contest/admin/dashboard?contest=' + enc(CONTEST), G).catch(() => null);
      if (d2) renderLive(liveBox, d2);
    }, 15000);

    // ---------- 4. regras essenciais ----------
    if (st) {
      const ini = el('input', { type: 'datetime-local', value: toLocalDT(st.start) });
      const fim = el('input', { type: 'datetime-local', value: toLocalDT(st.end) });
      const fz = el('input', { type: 'datetime-local', value: toLocalDT(st.freeze) });
      const msg = el('div', { class: 'small' });
      const save = el('button', { class: 'btn' }, T('Salvar janela', 'Save window', 'Guardar ventana'));
      save.addEventListener('click', async () => {
        const body = {};
        if (ini.value) body.start = dtToEpoch(ini.value);
        if (fim.value) body.end = dtToEpoch(fim.value);
        // campo de freeze VAZIO = sem congelamento -> manda 0. Omitir a chave (como era antes)
        // fazia o "limpar o freeze" virar no-op MUDO: o campo aceitava ser apagado, salvava
        // "✓" e o placar continuava congelado (a API só mexe no que vem no corpo).
        body.freeze = fz.value ? dtToEpoch(fz.value) : 0;
        if (body.start && body.end && body.end <= body.start) {
          msg.className = 'small error-box'; msg.textContent = T('o fim tem de ser depois do início.', 'the end must be after the start.', 'el fin tiene que ser después del inicio.'); return;
        }
        save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…', 'Guardando…');
        try { await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), body, G); msg.textContent = T('✓ salvo', '✓ saved', '✓ guardado'); }
        catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed', 'fallido'); }
        save.disabled = false;
      });
      panel.append(el('div', { class: 'section' },
        el('h2', { style: 'margin:.1rem 0 .4rem' }, T('⏱️ Regras da prova', '⏱️ Contest rules', '⏱️ Reglas de la competencia')),
        el('div', { class: 'row', style: 'gap:.7rem;flex-wrap:wrap;align-items:flex-end' },
          field(T('início', 'start', 'inicio'), ini), field(T('fim', 'end', 'fin'), fim), field(T('freeze do placar', 'scoreboard freeze', 'congelamiento del marcador'), fz)),
        el('div', { class: 'small muted', style: 'margin:.2rem 0' },
          T('Apagar o freeze descongela o placar. O MOJ só aceita isso a partir do fim da prova para todas as sedes + 1 min (prorrogações incluídas).',
            'Clearing the freeze unfreezes the scoreboard. The MOJ only accepts this from the end of the contest for every site + 1 min (extensions included).',
            'Borrar el congelamiento descongela el marcador. MOJ solo acepta esto desde el fin de la competencia para todas las sedes + 1 min (prórrogas incluidas).')),
        el('div', { class: 'small muted', style: 'margin:.2rem 0' },
          T('modo: ', 'mode: ', 'modo: '), el('span', { class: 'pill' }, (st.mode || 'icpc').toUpperCase()),
          T(' (definido na criação) · linguagens: ', ' (set at creation) · languages: ', ' (definido en la creación) · idiomas: '),
          (st.languages || []).join(', ') || T('todas', 'all', 'todas')),
        el('div', { class: 'small muted', style: 'margin:.2rem 0' },
          T('módulos: ', 'modules: ', 'módulos: '),
          ...(mods().length ? MODULES().filter((m) => mods().includes(m.id)).map((m) => el('span', { class: 'pill', style: 'margin-right:.25rem' }, m.icon + ' ' + m.name))
            : [el('span', { class: 'pill' }, T('nenhum (prova comum)', 'none (plain contest)', 'ninguno (competencia común)'))]),
          ' ', el('a', { href: '#central/modulos', class: 'small' }, T('ligar/desligar →', 'turn on/off →', 'activar/desactivar →'))),
        el('div', { class: 'row', style: 'gap:.5rem;margin-top:.3rem' }, save, msg,
          el('span', { style: 'flex:1' }),
          el('button', { class: 'btn ghost', onclick: () => go('central', 'regras') }, T('⚙ todas as configurações…', '⚙ all settings…', '⚙ toda la configuración…')))));
    }
  }

  return { panel, load };
}
