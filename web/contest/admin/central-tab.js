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
import { field } from '/shared/admin-ui.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const ICON = { ok: '🟢', warn: '🟡', fail: '🔴' };
// id da checagem do preflight -> [grupo, painel] onde ela se resolve
const TARGET = {
  window: ['central', 'regras'], show_log: ['central', 'regras'], show_code: ['central', 'regras'],
  freeze: ['central', 'regras'], mode: ['central', 'regras'], langs: ['central', 'regras'],
  balloons_freeze: ['central', 'regras'],
  tov: ['central', 'regras'],
  problems: ['prova', 'problemas'], pool_problems: ['prova', 'problemas'], pool: ['prova', 'problemas'],
  next_round: ['prova', 'rodadas'], docs: ['prova', 'documentos'], balloons: ['prova', 'baloes'],
  users: ['pessoas', 'contas'], cohorts: ['pessoas', 'coortes'], ua_gate: ['pessoas', 'maquinas'],
  registration: ['pessoas', 'inscricoes'], reg_invites: ['pessoas', 'inscricoes'],
  reg_source: ['pessoas', 'inscricoes'], reg_cohorts: ['pessoas', 'coortes'],
  reg_warmup: ['prova', 'rodadas'],
  print: ['operacao', 'staff'], staff_filters: ['operacao', 'staff'],
  judges: ['operacao', 'situacao'], daemon: ['operacao', 'situacao'], manual: ['operacao', 'juizes'],
  report: ['operacao', 'situacao'],   // postflight (encerrar evento)
  mlinux: ['operacao', 'mlinux'],
};

export function makeCentralTab(CONTEST, opts = {}) {
  const G = { contest: CONTEST, auth: true };
  const go = opts.go || (() => {});
  const panel = el('div', {});
  let timer = null;

  const gcard = (title, state, ...actions) => el('div', { class: 'gen-card' },
    el('h4', {}, title), el('span', { class: 'st' }, state),
    el('div', { class: 'row', style: 'gap:.35rem;flex-wrap:wrap' }, ...actions));

  const num = (n) => (n == null ? '—' : String(n));
  function renderLive(box, dash) {
    const j = (dash && dash.judges) || null, sub = (dash && dash.submissions) || null, rv = (dash && dash.review) || null;
    const dc = (val, label, warn) => el('div', { class: 'dash-card' + (warn ? ' warn' : '') },
      el('div', { class: 'dash-val' }, val), el('div', { class: 'dash-lbl' }, label));
    box.innerHTML = '';
    box.append(el('div', { class: 'row', style: 'gap:.6rem;align-items:baseline' },
      el('h2', { style: 'margin:.1rem 0' }, T('Ao vivo', 'Live')),
      el('span', { style: 'flex:1' }),
      el('button', { class: 'btn ghost', onclick: () => go('operacao', 'situacao') }, T('ver tudo →', 'see all →'))),
      el('div', { class: 'dash-cards' },
        dc(num(sub && sub.pending), T('pendentes', 'pending'), sub && sub.pending > 0),
        dc(num(sub && sub.total), T('submissões na janela', 'submissions in window')),
        dc(j ? `${j.online || 0}/${j.total || 0}` : '—', T('juízes online', 'judges online'), j && j.total > 0 && !j.online),
        dc(num(sub && sub.response && sub.response.p95_s) + 's', T('resposta p95', 'p95 response'), sub && sub.response && sub.response.p95_s > 120),
        dc(num(rv && rv.pending_total), T('na correção manual', 'in manual review'), rv && rv.conflicts > 0)));
  }

  function checkEl(c) {
    const t = TARGET[c.id];
    return el('div', { class: 'ck' },
      el('span', { class: 'ico' }, ICON[c.level] || '•'),
      el('span', { class: 'txt' }, el('b', {}, c.label), el('span', { class: 'small muted' }, c.detail || '')),
      t ? el('button', { class: 'btn ghost', onclick: () => go(t[0], t[1]) }, T('resolver →', 'fix →')) : null);
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
      apiGet('/contest/admin/finish?contest=' + enc(CONTEST), G).catch((e) => ({ _err: (e && e.message) || T('falha de rede', 'network error') })),
    ]);

    // ---------- 1. falta para começar ----------
    const checks = (pre && pre.checks) || [];
    const s = (pre && pre.summary) || { ok: 0, warn: 0, fail: 0 };
    const head = !pre ? el('span', { class: 'pill bad' }, T('não foi possível checar', 'could not check'))
      : s.fail > 0 ? el('span', { class: 'pill bad' }, T(`${s.fail} item(ns) BLOQUEIAM a prova`, `${s.fail} item(s) BLOCK the contest`))
        : s.warn > 0 ? el('span', { class: 'pill' }, T(`${s.warn} aviso(s) — nada bloqueia`, `${s.warn} warning(s) — nothing blocks`))
          : el('span', { class: 'pill ok' }, T('tudo pronto', 'all clear'));
    const box1 = el('div', { class: 'section' },
      el('div', { class: 'row', style: 'gap:.6rem;align-items:baseline' },
        el('h2', { style: 'margin:.1rem 0' }, T('Falta para começar', 'Before you start')), head,
        el('span', { style: 'flex:1' }),
        el('button', { class: 'btn ghost', title: T('rodar de novo', 'run again'), onclick: load }, '↻')));
    const bad = checks.filter((c) => c.level === 'fail').concat(checks.filter((c) => c.level === 'warn'));
    const good = checks.filter((c) => c.level === 'ok');
    bad.forEach((c) => box1.append(checkEl(c)));
    if (!bad.length) box1.append(el('div', { class: 'small muted', style: 'padding:.3rem 0' },
      T('Nenhum item pendente.', 'Nothing pending.')));
    if (good.length) box1.append(el('details', { class: 'fgroup' },
      el('summary', {}, T(`${good.length} itens já conferidos`, `${good.length} items already checked`)),
      ...good.map(checkEl)));
    panel.append(box1);

    // ---------- 1½. depois da prova ------------------------------------------------------
    // Renderiza sempre que o cartão é ESPERADO (fim base já passou), mesmo quando
    // can_finish=false (prorrogação de sede) ou o GET falhou — sumir em silêncio foi o bug
    // da Maratona 29/08. can_act=false (juiz-chefe) = checklist somente-leitura.
    const postEnd = !st || !st.end || Math.floor(Date.now() / 1000) > st.end;
    if (fin && fin._err) {
      if (postEnd) panel.append(el('div', { class: 'section' },
        el('h2', { style: 'margin:.1rem 0' }, T('Depois da prova', 'After the contest')),
        el('div', { class: 'small error-box' },
          T('Não foi possível consultar o encerramento: ', 'Could not load the finish checklist: ') + fin._err)));
    } else if (fin && (fin.can_finish || postEnd)) {
      const canAct = fin.can_act !== false;
      const fchecks = fin.checks || [];
      const fs = fin.summary || { ok: 0, warn: 0, fail: 0 };
      const fbad = fchecks.filter((c) => c.level === 'fail').concat(fchecks.filter((c) => c.level === 'warn'));
      const fgood = fchecks.filter((c) => c.level === 'ok');
      const fmsg = el('div', { class: 'small' });
      const npd = (fin.pending_docs || []).length;
      const btn = el('button', { class: 'btn' + (fs.fail ? '' : ' ghost') }, T('🏁 Encerrar evento', '🏁 Finish event'));
      const box = el('div', { class: 'section' },
        el('div', { class: 'row', style: 'gap:.6rem;align-items:baseline' },
          el('h2', { style: 'margin:.1rem 0' }, T('Depois da prova', 'After the contest')),
          !fin.can_finish ? el('span', { class: 'pill' }, T('aguardando o fim em todas as sedes', 'waiting for every site to finish'))
            : fs.fail > 0 ? el('span', { class: 'pill bad' }, T(`${fs.fail} item(ns) ainda fechado(s)`, `${fs.fail} item(s) still closed`))
              : el('span', { class: 'pill ok' }, T('resultado liberado', 'results released'))),
        el('div', { class: 'small muted', style: 'margin:.1rem 0 .5rem' },
          T('O botão abre o PLACAR (tira o congelamento) e publica os documentos já gerados. O resto continua sendo escolha sua — cada item abaixo tem o atalho para resolver.',
            'The button opens the SCOREBOARD (removes the freeze) and publishes the documents already generated. Everything else stays your call — each item below links to where it is fixed.')));
      fbad.forEach((c) => box.append(checkEl(c)));
      if (fgood.length) box.append(el('details', { class: 'fgroup' },
        el('summary', {}, T(`${fgood.length} itens já liberados`, `${fgood.length} items already released`)),
        ...fgood.map(checkEl)));
      btn.addEventListener('click', async () => {
        const willFreeze = fchecks.some((c) => c.id === 'freeze' && c.level === 'fail');
        const what = [willFreeze ? T('descongelar o placar', 'unfreeze the scoreboard') : null,
          npd ? T(`publicar ${npd} documento(s)`, `publish ${npd} document(s)`) : null].filter(Boolean);
        if (!what.length) { fmsg.className = 'small muted'; fmsg.textContent = T('Nada a fazer: já está tudo liberado.', 'Nothing to do: everything is already released.'); return; }
        // eslint-disable-next-line no-alert
        if (!confirm(T('Encerrar o evento vai: ', 'Finishing the event will: ') + what.join(T(' e ', ' and ')) + '.\n\n'
          + T('Isso fica visível para todo mundo. Confirmar?', 'This becomes visible to everyone. Confirm?'))) return;
        btn.disabled = true; fmsg.className = 'small'; fmsg.textContent = T('Encerrando…', 'Finishing…');
        try {
          const r = await apiPost('/contest/admin/finish?contest=' + enc(CONTEST), { action: 'finish' }, G);
          fmsg.textContent = '✓ ' + (r.done || []).map((d) => d.item).join(', ');
          setTimeout(load, 600);
        } catch (e) { fmsg.className = 'small error-box'; fmsg.textContent = e.message || T('falha', 'failed'); btn.disabled = false; }
      });
      if (!canAct) {
        box.append(el('div', { class: 'small muted', style: 'margin-top:.6rem' },
          T('Só o admin do contest pode encerrar — para o juiz-chefe este checklist é somente leitura.',
            'Only the contest admin can finish — for the chief judge this checklist is read-only.')));
      } else {
        if (!fin.can_finish) {
          btn.disabled = true;
          btn.title = T('disponível depois do fim para todas as sedes', 'available after every site finishes');
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
      el('h2', { style: 'margin:.1rem 0 .5rem' }, T('Gerar', 'Generate')),
      el('div', { class: 'tcards' },
        gcard(T('📄 Documentos da prova', '📄 Contest documents'),
          nd ? T(`${nd} gerado(s) · ${npub} publicado(s)`, `${nd} generated · ${npub} published`)
            : T('info sheet, caderno e folha de time limits (PDF+HTML, pt/en)', 'info sheet, booklet and time-limits sheet (PDF+HTML, pt/en)'),
          el('button', { class: 'btn', onclick: () => go('prova', 'documentos') }, T('abrir', 'open'))),
        gcard(T('🏷️ Etiquetas de credenciais', '🏷️ Credential badges'),
          T('folhas Pimaco A4 com login e senha', 'Pimaco A4 sheets with login and password'),
          el('a', { class: 'btn', target: '_blank', href: '/contest/badges/?c=' + enc(CONTEST) }, T('abrir', 'open'))),
        gcard(T('🔁 Promover rodada', '🔁 Promote round'),
          next ? (blk.length ? T(`próxima: ${next} — ${blk.length} bloqueador(es)`, `next: ${next} — ${blk.length} blocker(s)`)
            : T(`próxima: ${next} — pronta para promover`, `next: ${next} — ready to promote`))
            : T('nenhuma rodada planejada (aquecimento → prova no mesmo contest)', 'no round planned (warm-up → contest in the same contest)'),
          el('button', { class: 'btn' + (blk.length || !next ? ' ghost' : ''), onclick: () => go('prova', 'rodadas') }, T('abrir', 'open'))),
        gcard(T('📦 Relatório final', '📦 Final report'),
          T('tar.gz navegável: placar aberto, runs, clarifications, staff', 'browsable tar.gz: open scoreboard, runs, clarifications, staff'),
          el('button', { class: 'btn ghost', onclick: () => go('operacao', 'situacao') }, T('em Situação →', 'in Status →'))),
        gcard(T('🏆 Cerimônia de revelação', '🏆 Reveal ceremony'),
          T('placar congelado → aberto, de baixo para cima', 'frozen → open scoreboard, bottom-up'),
          el('a', { class: 'btn', target: '_blank', href: '/contest/score/reveal.html?c=' + enc(CONTEST) }, T('abrir', 'open'))),
        gcard(T('🎥 Telão (Animeitor)', '🎥 Big screen (Animeitor)'),
          T('fotos e músicas dos times, pacote .zip e as chaves do webcast',
            'team photos and music, .zip package and the webcast keys'),
          el('a', { class: 'btn ghost', target: '_blank', href: '/contest/animeitor/?c=' + enc(CONTEST) }, T('abrir', 'open'))),
        gcard(T('🔍 jplag (similaridade)', '🔍 jplag (similarity)'),
          T('compara as soluções aceitas entre os times', 'compares accepted solutions across teams'),
          el('a', { class: 'btn ghost', target: '_blank', href: '/contest/jplag/?c=' + enc(CONTEST) }, T('abrir', 'open'))))));

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
      const save = el('button', { class: 'btn' }, T('Salvar janela', 'Save window'));
      save.addEventListener('click', async () => {
        const body = {};
        if (ini.value) body.start = dtToEpoch(ini.value);
        if (fim.value) body.end = dtToEpoch(fim.value);
        // campo de freeze VAZIO = sem congelamento -> manda 0. Omitir a chave (como era antes)
        // fazia o "limpar o freeze" virar no-op MUDO: o campo aceitava ser apagado, salvava
        // "✓" e o placar continuava congelado (a API só mexe no que vem no corpo).
        body.freeze = fz.value ? dtToEpoch(fz.value) : 0;
        if (body.start && body.end && body.end <= body.start) {
          msg.className = 'small error-box'; msg.textContent = T('o fim tem de ser depois do início.', 'the end must be after the start.'); return;
        }
        save.disabled = true; msg.className = 'small'; msg.textContent = T('Salvando…', 'Saving…');
        try { await apiPost('/contest/admin/settings?contest=' + enc(CONTEST), body, G); msg.textContent = T('✓ salvo', '✓ saved'); }
        catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
        save.disabled = false;
      });
      panel.append(el('div', { class: 'section' },
        el('h2', { style: 'margin:.1rem 0 .4rem' }, T('Regras da prova', 'Contest rules')),
        el('div', { class: 'row', style: 'gap:.7rem;flex-wrap:wrap;align-items:flex-end' },
          field(T('início', 'start'), ini), field(T('fim', 'end'), fim), field(T('freeze do placar', 'scoreboard freeze'), fz)),
        el('div', { class: 'small muted', style: 'margin:.2rem 0' },
          T('modo: ', 'mode: '), el('span', { class: 'pill' }, (st.mode || 'icpc').toUpperCase()),
          T(' (definido na criação) · linguagens: ', ' (set at creation) · languages: '),
          (st.languages || []).join(', ') || T('todas', 'all')),
        el('div', { class: 'row', style: 'gap:.5rem;margin-top:.3rem' }, save, msg,
          el('span', { style: 'flex:1' }),
          el('button', { class: 'btn ghost', onclick: () => go('central', 'regras') }, T('⚙ todas as configurações…', '⚙ all settings…')))));
    }
  }

  return { panel, load };
}
