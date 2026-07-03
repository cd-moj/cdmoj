// steps/inicio.js — passo 0: começar de (em branco | template salvo | duplicar contest meu |
// importar .tar.gz) + utilitários (baixar template JSON, salvar template de contest existente).
import { el } from '/shared/ui.js';

export function makeStepInicio(ctx) {
  const root = el('div', {});
  const msg = el('div', { class: 'small', style: 'margin:.4rem 0' });
  const say = (t, err) => { msg.className = err ? 'small error-box' : 'small'; msg.textContent = t; };

  // --- em branco ---
  const blank = el('div', { class: 'start-card' },
    el('h3', {}, '📄 Em branco'),
    el('p', { class: 'muted small' }, 'Preencha os passos 1–7 do zero.'),
    el('button', { class: 'btn', onclick: () => ctx.goto(1) }, 'Começar →'));

  // --- template salvo ---
  const tplSel = el('select', { style: 'min-width:220px' });
  const tplApply = el('button', { class: 'btn', onclick: async () => {
    const n = tplSel.value; if (!n) return;
    try {
      const r = await ctx.api.get('/treino/contest-create/templates?name=' + encodeURIComponent(n));
      ctx.applyTemplate(r.template.spec || {}, 'template "' + n + '"');
      ctx.goto(1);
    } catch (e) { say(e.message || 'falha ao carregar o template', true); }
  } }, 'Usar template →');
  const tplDel = el('button', { class: 'btn danger', onclick: async () => {
    const n = tplSel.value; if (!n || !confirm('Excluir o template "' + n + '"?')) return;
    try { await ctx.api.post('/treino/contest-create/templates', { op: 'delete', name: n }); say('template excluído'); loadTemplates(); }
    catch (e) { say(e.message || 'falha', true); }
  } }, '✕');
  const tplBox = el('div', { class: 'start-card' },
    el('h3', {}, '📋 A partir de um template salvo'),
    el('p', { class: 'muted small' }, 'Pré-preenche modo, duração, opções, linguagens e visual (datas viram "a partir da próxima hora cheia").'),
    el('div', { class: 'row' }, tplSel, tplApply, tplDel));
  async function loadTemplates() {
    tplSel.innerHTML = '';
    try {
      const r = await ctx.api.get('/treino/contest-create/templates');
      const ts = r.templates || [];
      if (!ts.length) { tplSel.append(el('option', { value: '' }, '(você não tem templates)')); tplApply.disabled = tplDel.disabled = true; return; }
      tplApply.disabled = tplDel.disabled = false;
      ts.forEach((t) => tplSel.append(el('option', { value: t.name },
        t.name + ' · ' + (t.mode || '?') + (t.duration ? ' · ' + Math.round(t.duration / 3600) + 'h' : '') + (t.has_problems ? ' · com problemas' : ''))));
    } catch { tplSel.append(el('option', { value: '' }, '(falha ao listar)')); }
  }

  // --- duplicar contest meu ---
  const dupSel = el('select', { style: 'min-width:260px' });
  const dupBtn = el('button', { class: 'btn', onclick: async () => {
    const id = dupSel.value; if (!id) return;
    say('carregando ' + id + '…');
    try {
      const spec = await ctx.api.get('/treino/contest-create/export?id=' + encodeURIComponent(id));
      ctx.applyExport(spec, 'cópia de "' + id + '"');
      say(''); ctx.goto(1);
    } catch (e) { say(e.message || 'falha ao exportar', true); }
  } }, 'Duplicar →');
  const dupBox = el('div', { class: 'start-card' },
    el('h3', {}, '🧬 Duplicar um contest meu'),
    el('p', { class: 'muted small' }, 'Copia problemas, opções e visual (nunca usuários/submissões). Datas novas; revise e crie.'),
    el('div', { class: 'row' }, dupSel, dupBtn));

  // --- salvar template a partir de contest existente ---
  const stSel = el('select', { style: 'min-width:220px' });
  const stName = el('input', { placeholder: 'nome do template', style: 'min-width:180px' });
  const stProbs = el('input', { type: 'checkbox' });
  const stBtn = el('button', { class: 'btn ghost', onclick: async () => {
    const from = stSel.value, name = stName.value.trim();
    if (!from || !name) { say('escolha o contest e dê um nome ao template', true); return; }
    try {
      await ctx.api.post('/treino/contest-create/templates', { op: 'save', name, from_contest: from, include_problems: stProbs.checked });
      say('template "' + name + '" salvo'); stName.value = ''; loadTemplates();
    } catch (e) { say(e.message || 'falha ao salvar', true); }
  } }, '💾 Salvar template');
  const saveBox = el('div', { class: 'start-card' },
    el('h3', {}, '💾 Salvar template de um contest existente'),
    el('div', { class: 'row', style: 'flex-wrap:wrap' }, stSel, stName,
      el('label', { class: 'small' }, stProbs, ' incluir problemas'), stBtn));

  async function loadMine() {
    dupSel.innerHTML = ''; stSel.innerHTML = '';
    try {
      const r = await ctx.api.get('/treino/contest-create/mine');
      const cs = r.contests || [];
      if (!cs.length) {
        dupSel.append(el('option', { value: '' }, '(você ainda não criou contests)'));
        stSel.append(el('option', { value: '' }, '(nenhum)'));
        dupBtn.disabled = stBtn.disabled = true; return;
      }
      dupBtn.disabled = stBtn.disabled = false;
      cs.forEach((c) => {
        const label = c.id + ' — ' + (c.name || '') + ' (' + (c.problems_count || 0) + ' probs)';
        dupSel.append(el('option', { value: c.id }, label));
        stSel.append(el('option', { value: c.id }, label));
      });
    } catch {
      dupSel.append(el('option', { value: '' }, '(falha ao listar)'));
      stSel.append(el('option', { value: '' }, '(falha ao listar)'));
    }
  }

  // --- importar tar.gz + baixar template ---
  const fileInp = el('input', { type: 'file', accept: '.tar.gz,.tgz,application/gzip', style: 'display:none' });
  fileInp.addEventListener('change', async () => {
    const f = fileInp.files[0]; if (!f) return;
    say('Importando ' + f.name + '…');
    try {
      const buf = await f.arrayBuffer(); const b = new Uint8Array(buf); let bin = '';
      for (let i = 0; i < b.length; i += 0x8000) bin += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
      ctx.showResult(await ctx.api.post('/treino/contest-create/import', { tar_b64: btoa(bin) }));
    } catch (e) { say('Falha no import: ' + (e.message || 'erro'), true); }
    fileInp.value = '';
  });
  async function downloadTemplate() {
    try {
      const r = await fetch('/api/v1/treino/contest-create/template', { headers: { Authorization: 'Bearer ' + ctx.api.token() } });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const blob = await r.blob(); const a = document.createElement('a');
      a.href = URL.createObjectURL(blob); a.download = 'contest-template.json'; a.click(); URL.revokeObjectURL(a.href);
    } catch { say('Falha ao baixar o template.', true); }
  }
  const advBox = el('div', { class: 'start-card' },
    el('h3', {}, '📦 Arquivo (avançado)'),
    el('p', { class: 'muted small' }, 'Importe um .tar.gz com contest.json (+ enunciados/) — cria direto. O template JSON documenta todos os campos.'),
    el('div', { class: 'row' },
      el('button', { class: 'btn ghost', onclick: () => fileInp.click() }, '⬆ Importar .tar.gz'), fileInp,
      el('button', { class: 'btn ghost', onclick: downloadTemplate }, '⬇ Template (JSON)')));

  loadTemplates(); loadMine();
  root.append(el('div', { class: 'section' },
    el('h2', {}, '0 · Começar de…'), msg, blank, tplBox, dupBox, saveBox, advBox));
  return { el: root };
}
