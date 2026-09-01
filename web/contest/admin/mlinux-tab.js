// contest/admin/mlinux-tab.js — painel 🖥 mlinux (nutellaboot): panorama das máquinas das
// sedes (specs, editores, série da prova), coleta, configuração da chave e COMANDOS.
//
// É usado em DOIS lugares: o painel do admin (Operação › mlinux) e a página avulsa
// /contest/mlinux/ (cstaff/staff — o servidor já entrega `sedes[]` recortado ao escopo
// e `can_admin:false` esconde config/coleta/frota; a trava de verdade é a API).
// As SEÇÕES do panorama moram em web/lib/mlinux-view.js (compartilhadas com o relatório).
import { apiGet, apiPost } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';
import { mlinuxSections, MLINUX_CSS } from '/lib/mlinux-view.js';

const enc = encodeURIComponent;

export function makeMlinuxTab(CONTEST) {
  const G = { contest: CONTEST, auth: true };
  const panel = el('div', {});
  let RESP = null;          // último GET /contest/nutella
  let RTREE = [];           // árvore de regions.json (mesma hierarquia do placar)
  let sel = { kind: 'g', key: '' };   // g=global · n=nó da árvore · s=sede
  let pollT = null;

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
      ? T('chave gravada — digite p/ trocar', 'key stored — type to replace') : 'nb3a_…' });
    const save = async (remove) => {
      msg.textContent = '…';
      try {
        const body = { action: 'config', url: url.value.trim() };
        if (remove) body.key = '';
        else if (key.value.trim()) body.key = key.value.trim();
        const r = await apiPost('/contest/nutella?contest=' + enc(CONTEST), body, G);
        msg.textContent = r.configured ? T('✓ configurado', '✓ configured') : T('✓ chave removida', '✓ key removed');
        key.value = ''; load();
      } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    };
    return el('div', { class: 'section' },
      el('h2', {}, T('⚙ Integração', '⚙ Integration'),
        ' ', RESP && RESP.configured ? el('span', { class: 'pill ok' }, T('configurada', 'configured'))
          : el('span', { class: 'pill' }, T('sem chave', 'no key'))),
      el('div', { class: 'row', style: 'gap:.5rem;flex-wrap:wrap;align-items:center' },
        el('label', {}, 'URL ', url), el('label', {}, T('Chave ', 'Key '), key),
        el('button', { class: 'btn', onclick: () => save(false) }, T('Salvar', 'Save')),
        RESP && RESP.configured
          ? el('button', { class: 'btn ghost', onclick: () => save(true) }, T('remover chave', 'remove key')) : null,
        msg));
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
    if (st && st.running && !pollT) pollT = setTimeout(() => { pollT = null; if (!panel.hidden) load(); }, 3000);
    return el('div', { class: 'section' },
      el('h2', {}, T('Coleta', 'Collection')),
      el('div', { class: 'row', style: 'gap:.6rem;align-items:center' }, btn,
        el('span', { class: 'small muted' }, stTxt), msg));
  }

  // -- comandos (admin: qualquer sede + frota; c/staff: as próprias — a API corta) ------
  function commandCard() {
    const d = RESP && RESP.data;
    if (!d || !d.sedes || !d.sedes.length) return null;
    const msg = el('div', { class: 'small' });
    const selSede = el('select', {},
      ...(RESP.can_admin ? [el('option', { value: 'all' }, T('🌐 FROTA INTEIRA', '🌐 WHOLE FLEET'))] : []),
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
      const alvo = img === 'all' ? T('TODAS as máquinas de TODAS as sedes', 'ALL machines in ALL sites')
        : mac ? T(`a máquina ${mac} (${sede ? sede.name : img})`, `machine ${mac} (${sede ? sede.name : img})`)
          : T(`as ${sede ? sede.seen : '?'} máquinas de ${sede ? sede.name : img}`, `the ${sede ? sede.seen : '?'} machines of ${sede ? sede.name : img}`);
      // eslint-disable-next-line no-alert
      if (!confirm(T(`Enviar "${op}" para ${alvo}?`, `Send "${op}" to ${alvo}?`))) return;
      msg.textContent = '…';
      try {
        const body = { action: 'command', op, image: img };
        if (mac) body.mac = mac;
        await apiPost('/contest/nutella?contest=' + enc(CONTEST), body, G);
        msg.className = 'small'; msg.textContent = T(`✓ "${op}" enviado`, `✓ "${op}" sent`);
      } catch (e) { msg.className = 'small error-box'; msg.textContent = e.message || T('falha', 'failed'); }
    } }, T('▶ Enviar comando', '▶ Send command'));
    return el('div', { class: 'section' },
      el('h2', {}, T('🕹 Comandos nas máquinas', '🕹 Machine commands')),
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
        '  '.repeat(o.depth) + o.key)));
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
    // a view recebe o cache INTEIRO + a árvore + o recorte: as tabelas "por recorte" comparam
    // os filhos do nó (subregiões com dado, ou as sedes dele) — mesmo contrato do relatório
    mlinuxSections(currentAgg(), { showMachines: sel.kind === 's', window: d.window, contest: d.contest,
      link: d.link, data: d, tree: RTREE, sel })
      .forEach((s) => box.append(s));
    return el('div', {}, bar, box);
  }

  function render() {
    panel.innerHTML = '';
    panel.append(el('style', {}, MLINUX_CSS));
    if (RESP && RESP.can_admin) { panel.append(configCard()); panel.append(collectCard()); }
    const cc = commandCard(); if (cc) panel.append(cc);
    panel.append(panorama());
  }

  async function load() {
    panel.innerHTML = '';
    panel.append(el('p', { class: 'muted' }, T('Carregando…', 'Loading…')));
    try {
      const [r, rg] = await Promise.all([
        apiGet('/contest/nutella?contest=' + enc(CONTEST), G),
        apiGet('/contest/regions?contest=' + enc(CONTEST), G).catch(() => null),
      ]);
      RESP = r;
      RTREE = rg ? (Array.isArray(rg) ? rg : (rg.regions || [])) : [];
      render();
    } catch (e) {
      panel.innerHTML = '';
      panel.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load')));
    }
  }
  return { panel, load };
}
