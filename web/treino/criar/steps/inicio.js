// steps/inicio.js — passo 0: começar de (em branco | template salvo | duplicar contest meu |
// importar .tar.gz) + utilitários (baixar template JSON, salvar template de contest existente).
import { el } from '/shared/ui.js';
import { T } from '/shared/i18n.js';

export function makeStepInicio(ctx) {
  const root = el('div', {});
  const msg = el('div', { class: 'small', style: 'margin:.4rem 0' });
  const say = (t, err) => { msg.className = err ? 'small error-box' : 'small'; msg.textContent = t; };

  // --- em branco ---
  const blank = el('div', { class: 'start-card' },
    el('h3', {}, T('📄 Em branco', '📄 Blank')),
    el('p', { class: 'muted small' }, T('Preencha os passos 1–7 do zero.', 'Fill steps 1–7 from scratch.')),
    el('button', { class: 'btn', onclick: () => ctx.goto(1) }, T('Começar →', 'Start →')));

  // --- template salvo ---
  const tplSel = el('select', { style: 'min-width:220px' });
  const tplApply = el('button', { class: 'btn', onclick: async () => {
    const n = tplSel.value; if (!n) return;
    try {
      const r = await ctx.api.get('/treino/contest-create/templates?name=' + encodeURIComponent(n));
      ctx.applyTemplate(r.template.spec || {}, T('template "', 'template "') + n + '"');
      ctx.goto(1);
    } catch (e) { say(e.message || T('falha ao carregar o template', 'failed to load the template'), true); }
  } }, T('Usar template →', 'Use template →'));
  const tplDel = el('button', { class: 'btn danger', onclick: async () => {
    const n = tplSel.value; if (!n || !confirm(T('Excluir o template "', 'Delete the template "') + n + '"?')) return;
    try { await ctx.api.post('/treino/contest-create/templates', { op: 'delete', name: n }); say(T('template excluído', 'template deleted')); loadTemplates(); }
    catch (e) { say(e.message || T('falha', 'failed'), true); }
  } }, '✕');
  const tplBox = el('div', { class: 'start-card' },
    el('h3', {}, T('📋 A partir de um template salvo', '📋 From a saved template')),
    el('p', { class: 'muted small' }, T('Pré-preenche modo, duração, opções, linguagens e visual (datas viram "a partir da próxima hora cheia").', 'Pre-fills mode, duration, options, languages and appearance (dates become "from the next full hour").')),
    el('div', { class: 'row' }, tplSel, tplApply, tplDel));
  async function loadTemplates() {
    tplSel.innerHTML = '';
    try {
      const r = await ctx.api.get('/treino/contest-create/templates');
      const ts = r.templates || [];
      if (!ts.length) { tplSel.append(el('option', { value: '' }, T('(você não tem templates)', '(you have no templates)'))); tplApply.disabled = tplDel.disabled = true; return; }
      tplApply.disabled = tplDel.disabled = false;
      ts.forEach((t) => tplSel.append(el('option', { value: t.name },
        t.name + ' · ' + (t.mode || '?') + (t.duration ? ' · ' + Math.round(t.duration / 3600) + 'h' : '') + (t.has_problems ? T(' · com problemas', ' · with problems') : ''))));
    } catch { tplSel.append(el('option', { value: '' }, T('(falha ao listar)', '(failed to list)'))); }
  }

  // --- duplicar contest meu ---
  const dupSel = el('select', { style: 'min-width:260px' });
  const dupBtn = el('button', { class: 'btn', onclick: async () => {
    const id = dupSel.value; if (!id) return;
    say(T('carregando ', 'loading ') + id + '…');
    try {
      const spec = await ctx.api.get('/treino/contest-create/export?id=' + encodeURIComponent(id));
      ctx.applyExport(spec, T('cópia de "', 'copy of "') + id + '"');
      say(''); ctx.goto(1);
    } catch (e) { say(e.message || T('falha ao exportar', 'failed to export'), true); }
  } }, T('Duplicar →', 'Duplicate →'));
  const dupBox = el('div', { class: 'start-card' },
    el('h3', {}, T('🧬 Duplicar um contest meu', '🧬 Duplicate one of my contests')),
    el('p', { class: 'muted small' }, T('Copia problemas, opções e visual (nunca usuários/submissões). Datas novas; revise e crie.', 'Copies problems, options and appearance (never users/submissions). New dates; review and create.')),
    el('div', { class: 'row' }, dupSel, dupBtn));

  // --- salvar template a partir de contest existente ---
  const stSel = el('select', { style: 'min-width:220px' });
  const stName = el('input', { placeholder: T('nome do template', 'template name'), style: 'min-width:180px' });
  const stProbs = el('input', { type: 'checkbox' });
  const stBtn = el('button', { class: 'btn ghost', onclick: async () => {
    const from = stSel.value, name = stName.value.trim();
    if (!from || !name) { say(T('escolha o contest e dê um nome ao template', 'choose the contest and name the template'), true); return; }
    try {
      await ctx.api.post('/treino/contest-create/templates', { op: 'save', name, from_contest: from, include_problems: stProbs.checked });
      say(T('template "', 'template "') + name + T('" salvo', '" saved')); stName.value = ''; loadTemplates();
    } catch (e) { say(e.message || T('falha ao salvar', 'failed to save'), true); }
  } }, T('💾 Salvar template', '💾 Save template'));
  const saveBox = el('div', { class: 'start-card' },
    el('h3', {}, T('💾 Salvar template de um contest existente', '💾 Save a template from an existing contest')),
    el('div', { class: 'row', style: 'flex-wrap:wrap' }, stSel, stName,
      el('label', { class: 'small' }, stProbs, T(' incluir problemas', ' include problems')), stBtn));

  async function loadMine() {
    dupSel.innerHTML = ''; stSel.innerHTML = '';
    try {
      const r = await ctx.api.get('/treino/contest-create/mine');
      const cs = r.contests || [];
      if (!cs.length) {
        dupSel.append(el('option', { value: '' }, T('(você ainda não criou contests)', '(you have not created contests yet)')));
        stSel.append(el('option', { value: '' }, T('(nenhum)', '(none)')));
        dupBtn.disabled = stBtn.disabled = true; return;
      }
      dupBtn.disabled = stBtn.disabled = false;
      cs.forEach((c) => {
        const label = c.id + ' — ' + (c.name || '') + ' (' + (c.problems_count || 0) + ' probs)';
        dupSel.append(el('option', { value: c.id }, label));
        stSel.append(el('option', { value: c.id }, label));
      });
    } catch {
      dupSel.append(el('option', { value: '' }, T('(falha ao listar)', '(failed to list)')));
      stSel.append(el('option', { value: '' }, T('(falha ao listar)', '(failed to list)')));
    }
  }

  // --- importar tar.gz + baixar template ---
  const fileInp = el('input', { type: 'file', accept: '.tar.gz,.tgz,application/gzip', style: 'display:none' });
  fileInp.addEventListener('change', async () => {
    const f = fileInp.files[0]; if (!f) return;
    say(T('Importando ', 'Importing ') + f.name + '…');
    try {
      const buf = await f.arrayBuffer(); const b = new Uint8Array(buf); let bin = '';
      for (let i = 0; i < b.length; i += 0x8000) bin += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
      ctx.showResult(await ctx.api.post('/treino/contest-create/import', { tar_b64: btoa(bin) }));
    } catch (e) { say(T('Falha no import: ', 'Import failed: ') + (e.message || T('erro', 'error')), true); }
    fileInp.value = '';
  });
  async function downloadTemplate() {
    try {
      const r = await fetch('/api/v1/treino/contest-create/template', { headers: { Authorization: 'Bearer ' + ctx.api.token() } });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const blob = await r.blob(); const a = document.createElement('a');
      a.href = URL.createObjectURL(blob); a.download = 'contest-template.json'; a.click(); URL.revokeObjectURL(a.href);
    } catch { say(T('Falha ao baixar o template.', 'Failed to download the template.'), true); }
  }
  const advBox = el('div', { class: 'start-card' },
    el('h3', {}, T('📦 Arquivo (avançado)', '📦 File (advanced)')),
    el('p', { class: 'muted small' }, T('Importe um .tar.gz com contest.json (+ enunciados/) — cria direto. O template JSON documenta todos os campos.', 'Import a .tar.gz with contest.json (+ enunciados/) — creates directly. The JSON template documents all fields.')),
    el('div', { class: 'row' },
      el('button', { class: 'btn ghost', onclick: () => fileInp.click() }, T('⬆ Importar .tar.gz', '⬆ Import .tar.gz')), fileInp,
      el('button', { class: 'btn ghost', onclick: downloadTemplate }, T('⬇ Template (JSON)', '⬇ Template (JSON)'))));

  loadTemplates(); loadMine();
  root.append(el('div', { class: 'section' },
    el('h2', {}, T('0 · Começar de…', '0 · Start from…')), msg, blank, tplBox, dupBox, saveBox, advBox));
  return { el: root };
}
