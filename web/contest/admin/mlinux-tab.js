// contest/admin/mlinux-tab.js — painel 🖥️ mlinux (nutellaboot): panorama das máquinas das
// sedes (specs, editores, série da prova), coleta, configuração da chave e COMANDOS.
//
// É usado em DOIS lugares: o painel do admin (Máquinas › mlinux) e a página avulsa
// /contest/mlinux/ (cstaff/staff — o servidor já entrega `sedes[]` recortado ao escopo
// e `can_admin:false` esconde config/coleta/frota; a trava de verdade é a API).
// As SEÇÕES do panorama moram em web/lib/mlinux-view.js (compartilhadas com o relatório).
//
// ATUALIZAÇÃO EM LUGAR (regra da casa): quatro caixas fixas (config, coleta, comandos,
// panorama); cada uma troca só quando a sua assinatura muda. Durante a coleta o poll de 3 s
// mexe SÓ na caixa de coleta — até 05/09 ele refazia o painel inteiro (recorte e formulário de
// comando iam junto).
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { swapIf, sigOf } from '/shared/admin-ui.js';
import { mlinuxSections, MLINUX_CSS } from '/lib/mlinux-view.js';

const enc = encodeURIComponent;

export function makeMlinuxTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', {});
  let RESP = null;          // último GET /contest/nutella
  let RTREE = [];           // árvore de regions.json (mesma hierarquia do placar)
  let sel = { kind: 'g', key: '' };   // g=global · n=nó da árvore · s=sede
  let pollT = null;
  const SK = {};            // esqueleto: style, cfg, collect, cmd, pan, err

  // -- hierarquia: árvore (ordem/indentação do placar) + sedes fora dela no fim ---------
  function nodeOpts() {
    const d = RESP && RESP.data;
    if (!d) return [];
    const have = d.by_node || {};
    const sedeSet = new Set((d.sedes || []).map((s) => s.name.toLowerCase()));
    const out = [];
    const walk = (list, depth) => (list || []).forEach((r) => {
      if (r.name) {
        if (sedeSet.has(r.name.toLowerCase())) out.push({ kind: 's', key: r.name, depth });
        else if (Object.prototype.hasOwnProperty.call(have, r.name)) out.push({ kind: 'n', key: r.name, depth });
      }
      if (Array.isArray(r.subregions) && r.subregions.length) walk(r.subregions, depth + 1);
    });
    walk(RTREE, 0);
    const seen = new Set(out.map((o) => o.key.toLowerCase()));
    (d.sedes || []).map((s) => s.name).sort((a, b) => a.localeCompare(b)).forEach((n) => {
      if (!seen.has(n.toLowerCase())) out.push({ kind: 's', key: n, depth: 0 });
    });
    return out;
  }
  function currentAgg() {
    const d = RESP && RESP.data;
    if (!d) return null;
    if (sel.kind === 'n') return (d.by_node || {})[sel.key] || d.global;
    if (sel.kind === 's') return (d.sedes || []).find((s) => s.name === sel.key) || d.global;
    return d.global;
  }

  // -- cartão de configuração (só admin; chave é WRITE-ONLY) ----------------------------
  function configCard() {
    const msg = el('span', { class: 'small' });
    const url = el('input', { type: 'text', size: '38', value: (RESP && RESP.url) || '',
      placeholder: 'https://nutellaboot…' });
    const key = el('input', { type: 'password', size: '30', placeholder: RESP && RESP.configured
      ? T('chave gravada — digite p/ trocar', 'key stored — type to replace') : 'nb3s_… / nb3a_…' });
    // site-images do evento: OBRIGATÓRIO com chave de serviço (ela não lista as sedes do serviço);
    // com chave de administração é opcional e só restringe a coleta. Pré-preenche com a última coleta.
    const known = (RESP && RESP.images && RESP.images.length) ? RESP.images
      : ((RESP && RESP.data && RESP.data.sedes) || []).map((x) => x.id);
    const imgs = el('input', { type: 'text', size: '46', value: known.join(' '),
      placeholder: T('ids das site-images, separados por espaço', 'site-image ids, space separated') });
    const save = async (remove) => {
      msg.textContent = '…';
      try {
        const body = { action: 'config', url: url.value.trim(), images: imgs.value.trim() };
        if (remove) body.key = '';
        else if (key.value.trim()) body.key = key.value.trim();
        const r = await apiPost('/contest/nutella?contest=' + enc(CONTEST), body, G);
        msg.textContent = r.configured ? T('✓ configurado', '✓ configured') : T('✓ chave removida', '✓ key removed');
        key.value = ''; load();
      } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    };
    return el('div', { class: 'section' },
      el('h2', {}, T('⚙️ Integração', '⚙️ Integration'),
        ' ', RESP && RESP.configured ? el('span', { class: 'pill ok' }, T('configurada', 'configured'))
          : el('span', { class: 'pill' }, T('sem chave', 'no key'))),
      el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;align-items:center' },
        el('label', {}, 'URL ', url), el('label', {}, T('Chave ', 'Key '), key),
        RESP && RESP.key_kind ? el('span', { class: 'pill ' + (RESP.key_kind === 'service' ? 'ok' : 'warn'),
          title: RESP.key_kind === 'service'
            ? T('Chave de serviço: só os escopos e as imagens que a administração do nutellaboot liberou.',
                'Service key: only the scopes and images the nutellaboot administration granted.')
            : T('Chave de ADMINISTRAÇÃO: faz tudo no nutellaboot, em todas as sedes. Prefira uma chave de serviço (nb3s_…) com machines:read, commands:write, bindings:write, roster:read e roster:write nas imagens do evento.',
                'ADMINISTRATION key: can do anything in nutellaboot, on every site. Prefer a service key (nb3s_…) with machines:read, commands:write, bindings:write, roster:read and roster:write on the event images.') },
          RESP.key_kind === 'service' ? T('chave de serviço', 'service key') : T('chave de administração', 'administration key')) : null),
      el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;align-items:center;margin-top:.4rem' },
        el('label', {}, T('Site-images do evento ', 'Event site-images '), imgs),
        el('button', { class: 'btn', onclick: () => save(false) }, T('Salvar', 'Save')),
        RESP && RESP.configured
          ? el('button', { class: 'btn ghost', onclick: () => save(true) }, T('remover chave', 'remove key')) : null,
        msg),
      el('div', { class: 'small muted', style: 'margin-top:.3rem' },
        T('Com chave de serviço as site-images são obrigatórias: ela não lista as sedes do nutellaboot.',
          'With a service key the site-images are required: it cannot list the nutellaboot sites.')));
  }

  // -- cartão de coleta (só admin) ------------------------------------------------------
  function collectCard() {
    const st = (RESP && RESP.status) || null;
    const msg = el('span', { class: 'small' });
    let stTxt = T('nunca coletado', 'never collected');
    if (st && st.running) stTxt = T('coletando… ', 'collecting… ') + (st.phase || '');
    else if (st && st.ok) stTxt = T('última coleta: ', 'last collection: ') + new Date((st.finished_at || 0) * 1000).toLocaleString();
    else if (st && st.ok === false) stTxt = T('FALHOU: ', 'FAILED: ') + (st.error || '');
    const btn = el('button', { class: 'btn', disabled: !(RESP && RESP.configured) || !!(st && st.running),
      onclick: async () => {
        msg.textContent = '…';
        try { await apiPost('/contest/nutella?contest=' + enc(CONTEST), { action: 'collect' }, G); msg.textContent = ''; load(); }
        catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
      } }, T('📥 Coletar agora', '📥 Collect now'));
    return el('div', { class: 'section' },
      el('h2', {}, T('📥 Coleta', '📥 Collection')),
      el('div', { class: 'row', style: 'gap:.6rem;align-items:center' }, btn,
        el('span', { class: 'small muted' }, stTxt), msg));
  }

  // -- vínculo máquina↔time publicado no login (só admin) --------------------------------
  // O agente novo do mlinux põe o MAC no UA; o login do time diz em que máquina ele está e o MOJ
  // publica isso no nutellaboot (lib/nutella-bind.sh). Aqui: o estado, o liga/desliga e a republicação.
  function bindCard() {
    const b = RESP && RESP.bind; if (!b || !(RESP && RESP.configured)) return null;
    const msg = el('span', { class: 'small' });
    const lg = b.log || {};
    const act = async (body, okTxt) => {
      msg.className = 'small'; msg.textContent = '…';
      try { const r = await apiPost('/contest/nutella?contest=' + enc(CONTEST), body, G); msg.textContent = okTxt(r); load(); }
      catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    };
    const parts = [b.enabled ? T('ligado', 'on') : T('DESLIGADO', 'OFF'),
      T(`${b.published} máquinas vinculadas`, `${b.published} machines linked`)];
    if (b.queued) parts.push(T(`${b.queued} na fila`, `${b.queued} queued`));
    if (lg.noroster) parts.push(T(`${lg.noroster} recusadas: time fora do roster da imagem`, `${lg.noroster} refused: team not in the image roster`));
    if (lg.image_unknown) parts.push(T(`${lg.image_unknown} de imagem que não é deste contest`, `${lg.image_unknown} from an image not in this contest`));
    if (lg.error) parts.push(T(`${lg.error} erros do serviço`, `${lg.error} service errors`));
    return el('div', { class: 'section' },
      el('h2', {}, T('🔗 Vínculo máquina-time', '🔗 Machine-team link')),
      el('p', { class: 'ml-note' }, T('Quando um time faz login numa máquina do mlinux, o MOJ informa ao nutellaboot qual time está nela. A tela de bloqueio da máquina passa a mostrar o time. Só funciona com o agente novo do mlinux e com o time no roster da imagem.',
        'When a team logs in on an mlinux machine, MOJ tells nutellaboot which team is on it. The machine lock screen then shows the team. It needs the new mlinux agent and the team in the image roster.')),
      el('div', { class: 'small', style: 'margin:.2rem 0 .4rem' }, parts.join(' · ')),
      el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
        el('button', { class: 'btn ghost', onclick: () => act({ action: 'config', bind: !b.enabled }, () => '') },
          b.enabled ? T('desligar', 'turn off') : T('ligar', 'turn on')),
        el('button', { class: 'btn ghost', title: T('Envia ao nutellaboot os times de cada sede (da última coleta). Não mexe em roster já preenchido.', 'Sends the teams of each site (from the last collection) to nutellaboot. Does not touch a roster that already has entries.'),
          onclick: () => act({ action: 'push-roster' }, (r) => T(`roster: ${r.pushed} enviadas, ${r.kept} mantidas, ${r.failed} falharam`, `roster: ${r.pushed} sent, ${r.kept} kept, ${r.failed} failed`)) },
        T('📋 enviar roster', '📋 send roster')),
        el('button', { class: 'btn ghost', title: T('Reenvia o vínculo de todo login já feito (use depois de enviar o roster).', 'Resends the link of every login already made (use it after sending the roster).'),
          onclick: () => act({ action: 'push-bindings' }, (r) => T(`${r.queued} vínculos na fila de envio`, `${r.queued} links queued`)) },
        T('🔁 republicar vínculos', '🔁 republish links')),
        msg));
  }

  // -- alertas das máquinas em tempo real: webhook do nutellaboot → MOJ (só admin) --------
  function hookCard() {
    const w = RESP && RESP.webhook; if (!w || !(RESP && RESP.configured)) return null;
    const msg = el('span', { class: 'small' });
    // a rota do webhook não atende pelo subdomínio do contest: o palpite tira o "<contest>." da frente
    const guess = String(location.origin || '').replace('//' + CONTEST + '.', '//');
    const base = el('input', { type: 'text', value: guess, size: 34, 'aria-label': T('URL pública do MOJ', 'MOJ public URL') });
    const act = async (body) => {
      msg.className = 'small'; msg.textContent = '…';
      try {
        const r = await apiPost('/contest/nutella?contest=' + enc(CONTEST), Object.assign({ action: 'webhooks-install', base_url: base.value.trim() }, body), G);
        msg.textContent = T(`${r.ok} sede(s) ok, ${r.failed} falharam`, `${r.ok} site(s) ok, ${r.failed} failed`); load();
      } catch (e) {
        if (e.code === 'foreign_webhooks' && confirm((e.message || '') + '\n\n' + T('Substituir mesmo assim?', 'Replace anyway?'))) return act(Object.assign({}, body, { force: true }));
        msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed');
      }
    };
    return el('div', { class: 'section' },
      el('h2', {}, T('🔌 Alertas das máquinas em tempo real', '🔌 Real-time machine alerts')),
      el('p', { class: 'ml-note' }, T('O nutellaboot avisa o MOJ quando uma máquina levanta um alerta (pendrive, celular, rede por USB, identidade repetida). O alerta aparece em Máquinas › Anomalias e, durante a prova, o dono do contest recebe no Telegram. Para instalar, a chave gravada acima tem de ser a de administração do nutellaboot.',
        'Nutellaboot tells MOJ when a machine raises an alert (USB storage, phone, USB network, duplicate identity). The alert shows in Machines › Anomalies and, during the contest, the contest owner gets it on Telegram. To install it, the key saved above must be the nutellaboot administration key.')),
      el('div', { class: 'small', style: 'margin:.2rem 0 .4rem' },
        (w.installed ? T('instalado', 'installed') : T('não instalado', 'not installed')) + ' · ' + T(`${w.events} alertas recebidos`, `${w.events} alerts received`)
        + (RESP.key_kind === 'service' ? T(' · a chave atual é de serviço: não instala nem remove', ' · the current key is a service key: it cannot install or remove') : '')),
      el('div', { class: 'row', style: 'gap:.5rem;align-items:center;flex-wrap:wrap' },
        el('label', { class: 'small' }, T('URL pública do MOJ: ', 'MOJ public URL: '), base),
        el('button', { class: 'btn ghost', onclick: () => act({}) }, w.installed ? T('reinstalar', 'reinstall') : T('instalar', 'install')),
        w.installed ? el('button', { class: 'btn ghost', onclick: () => act({ remove: true }) }, T('remover', 'remove')) : null,
        msg));
  }

  // -- comandos (admin: qualquer sede + frota; c/staff: as próprias — a API corta) ------
  function commandCard() {
    const d = RESP && RESP.data;
    if (!d || !d.sedes || !d.sedes.length) return null;
    const msg = el('div', { class: 'small' });
    const selSede = el('select', {},
      ...(RESP.can_admin ? [el('option', { value: 'all' }, T('🌐 TODAS AS SEDES DO CONTEST', '🌐 ALL SITES OF THIS CONTEST'))] : []),
      ...d.sedes.map((s) => el('option', { value: s.id }, s.name + ' (' + s.id + ')')));
    if (RESP.can_admin && d.sedes.length) selSede.value = d.sedes[0].id;
    const selMac = el('select', {}, el('option', { value: '' }, T('todas as máquinas', 'all machines')));
    const selOp = el('select', {}, el('option', { value: '' }, '…'));
    const fillMacs = () => {
      selMac.innerHTML = ''; selMac.append(el('option', { value: '' }, T('todas as máquinas', 'all machines')));
      const sede = d.sedes.find((s) => s.id === selSede.value);
      ((sede && sede.machines) || []).forEach((m) => selMac.append(el('option', { value: m.mac }, m.mac)));
    };
    const fillOps = async () => {
      const img = selSede.value === 'all' ? (d.sedes[0] || {}).id : selSede.value;
      if (!img) return;
      try {
        const r = await apiGet('/contest/nutella?contest=' + enc(CONTEST) + '&catalog=' + enc(img), G);
        selOp.innerHTML = '';
        (r.allowed || []).forEach((op) => selOp.append(el('option', { value: op }, op)));
      } catch { /* catálogo indisponível: select fica vazio e o POST diria o porquê */ }
    };
    selSede.addEventListener('change', () => { fillMacs(); fillOps(); });
    fillMacs(); fillOps();
    const btn = el('button', { class: 'btn', onclick: async () => {
      const op = selOp.value, img = selSede.value, mac = selMac.value;
      if (!op || !img) return;
      const sede = d.sedes.find((s) => s.id === img);
      const alvo = img === 'all' ? T(`TODAS as máquinas das ${d.sedes.length} sedes DESTE contest`, `ALL machines in the ${d.sedes.length} sites of THIS contest`)
        : mac ? T(`a máquina ${mac} (${sede ? sede.name : img})`, `machine ${mac} (${sede ? sede.name : img})`)
          : T(`as ${sede ? sede.seen : '?'} máquinas de ${sede ? sede.name : img}`, `the ${sede ? sede.seen : '?'} machines of ${sede ? sede.name : img}`);
      // eslint-disable-next-line no-alert
      if (!confirm(T(`Enviar "${op}" para ${alvo}?`, `Send "${op}" to ${alvo}?`))) return;
      msg.textContent = '…';
      try {
        const body = { action: 'command', op, image: img };
        if (mac) body.mac = mac;
        const r = await apiPost('/contest/nutella?contest=' + enc(CONTEST), body, G);
        // o servidor manda UMA ordem por sede e conta quem aceitou: sede recusada aparece pelo nome
        const bad = Object.entries(r.sedes || {}).filter(([, v]) => !(v.status >= 200 && v.status < 300));
        const nm = Object.values(r.sedes || {}).reduce((a, v) => a + (v.machines || 0), 0);
        msg.className = 'small' + (bad.length ? ' error-box' : '');
        msg.textContent = T(`✓ "${op}" enviado a ${nm} máquina(s) em ${r.ok || 0} sede(s)`, `✓ "${op}" sent to ${nm} machine(s) in ${r.ok || 0} site(s)`)
          + (bad.length ? T(' — recusado em: ', ' — refused at: ') + bad.map(([k, v]) => k + ' (HTTP ' + v.status + (v.detail ? ': ' + v.detail : '') + ')').join(', ') : '');
      } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    } }, T('▶ Enviar comando', '▶ Send command'));
    return el('div', { class: 'section' },
      el('h2', {}, T('🕹️ Comandos nas máquinas', '🕹️ Machine commands')),
      el('div', { class: 'small muted', style: 'margin:.1rem 0 .4rem' },
        T('O comando entra na fila do nutellaboot e a máquina executa no próximo contato. Tudo é auditado.',
          'The command is queued in nutellaboot and runs on the machine\'s next contact. Everything is audited.')),
      el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;align-items:center' },
        el('label', {}, T('Sede ', 'Site '), selSede), el('label', {}, T('Máquina ', 'Machine '), selMac),
        el('label', {}, T('Comando ', 'Command '), selOp), btn),
      msg);
  }

  function panorama() {
    const d = RESP && RESP.data;
    if (!d) {
      return el('div', { class: 'section' }, el('p', { class: 'muted' },
        RESP && RESP.configured
          ? T('Nenhuma coleta ainda — rode "Coletar agora".', 'No collection yet — run "Collect now".')
          : T('Configure a chave do nutellaboot para começar.', 'Set the nutellaboot key to begin.')));
    }
    const opts = nodeOpts();
    const bar = el('div', { class: 'fbar' });
    const selN = el('select', { id: 'fRegion' }, el('option', { value: 'g|' }, T('— geral —', '— overall —')),
      ...opts.map((o) => el('option', { value: o.kind + '|' + o.key },
        '  '.repeat(o.depth) + o.key)));
    selN.value = sel.kind === 'g' ? 'g|' : sel.kind + '|' + sel.key;
    if (selN.selectedIndex < 0) { sel = { kind: 'g', key: '' }; selN.value = 'g|'; }
    selN.addEventListener('change', () => {
      const [k, ...rest] = selN.value.split('|');
      sel = { kind: k, key: rest.join('|') }; render();
    });
    const lk = d.link || {};
    bar.append(el('label', {}, T('Recorte: ', 'Selection: '), selN),
      el('span', { class: 'fcount' },
        T(`coletado ${new Date((d.collected_at || 0) * 1000).toLocaleString()}`,
          `collected ${new Date((d.collected_at || 0) * 1000).toLocaleString()}`)
        + (lk.mode === 'ua' ? T(` · vínculo máquina-time: ${lk.linked}/${lk.present} times presentes (${lk.coverage}%)`, ` · machine-team link: ${lk.linked}/${lk.present} present teams (${lk.coverage}%)`)
          : d.version >= 2 ? T(' · sem vínculo máquina-time', ' · no machine-team link') : '')));
    const box = el('div', {});
    // sede que o serviço NÃO devolveu nesta coleta (rede, escopo da chave): avisa — sumir calada não pode
    if ((d.skipped || []).length) box.append(el('p', { class: 'ml-note', style: 'color:var(--warn,#b9770e)' },
      T(`⚠ Sem dados nesta coleta: ${d.skipped.join(', ')}. Confira o escopo da chave e colete de novo.`,
        `⚠ No data in this collection: ${d.skipped.join(', ')}. Check the key scope and collect again.`)));
    // a view recebe o cache INTEIRO + a árvore + o recorte: as tabelas "por recorte" comparam
    // os filhos do nó (subregiões com dado, ou as sedes dele) — mesmo contrato do relatório
    mlinuxSections(currentAgg(), { showMachines: sel.kind === 's', window: d.window, contest: d.contest,
      link: d.link, data: d, tree: RTREE, sel })
      .forEach((s) => box.append(s));
    return el('div', {}, bar, box);
  }

  function skeleton() {
    SK.style = el('style', {}, MLINUX_CSS);
    SK.err = el('div', {}); SK.cfg = el('div', {}); SK.collect = el('div', {}); SK.bind = el('div', {}); SK.hook = el('div', {}); SK.cmd = el('div', {}); SK.pan = el('div', {});
    panel.innerHTML = '';
    panel.append(SK.style, SK.err, SK.cfg, SK.collect, SK.bind, SK.hook, SK.cmd, SK.pan);
  }

  // cada caixa troca só quando a SUA assinatura muda; a coleta em andamento só mexe na dela
  function render() {
    const d = (RESP && RESP.data) || null, adm = !!(RESP && RESP.can_admin), st = (RESP && RESP.status) || null;
    swapIf(SK.cfg, sigOf(adm, RESP && RESP.configured, RESP && RESP.url), () => (adm ? configCard() : null));
    swapIf(SK.collect, sigOf(adm, RESP && RESP.configured, st), () => (adm ? collectCard() : null));
    swapIf(SK.bind, sigOf(adm, RESP && RESP.configured, RESP && RESP.bind), () => (adm ? bindCard() : null));
    swapIf(SK.hook, sigOf(adm, RESP && RESP.configured, RESP && RESP.webhook, RESP && RESP.key_kind), () => (adm ? hookCard() : null));
    swapIf(SK.cmd, sigOf(adm, d && (d.sedes || []).map((s) => [s.id, s.name, s.seen, ((s.machines || []).map((m) => m.mac))])), () => commandCard());
    swapIf(SK.pan, sigOf(RESP && RESP.configured, d && d.collected_at, d && d.version, d && d.link, d && d.window, sel, RTREE), () => panorama());
    if (st && st.running && !pollT) pollT = setTimeout(() => { pollT = null; if (!panel.hidden) load(); }, 3000);
  }

  async function load() {
    if (!SK.style) { skeleton(); SK.pan.append(el('p', { class: 'muted' }, T('Carregando…', 'Loading…'))); }
    try {
      const [r, rg] = await Promise.all([
        apiGet('/contest/nutella?contest=' + enc(CONTEST), G),
        apiGet('/contest/regions?contest=' + enc(CONTEST), G).catch(() => null),
      ]);
      RESP = r;
      RTREE = rg ? (Array.isArray(rg) ? rg : (rg.regions || [])) : [];
      SK.err.innerHTML = '';
      render();
    } catch (e) {
      SK.err.innerHTML = '';
      SK.err.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load')));
    }
  }
  return { panel, load };
}
