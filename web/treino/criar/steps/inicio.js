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
    el('h3', {}, T('📄 Em branco', '📄 Blank', '📄 En blanco')),
    el('p', { class: 'muted small' }, T('Preencha os passos 1–7 do zero.', 'Fill steps 1–7 from scratch.', 'Completa los pasos 1–7 desde cero.')),
    el('button', { class: 'btn', onclick: () => ctx.goto(1) }, T('Começar →', 'Start →', 'Empezar →')));

  // --- template salvo ---
  const tplSel = el('select', { style: 'min-width:220px' });
  const tplApply = el('button', { class: 'btn', onclick: async () => {
    const n = tplSel.value; if (!n) return;
    try {
      const r = await ctx.api.get('/treino/contest-create/templates?name=' + encodeURIComponent(n));
      ctx.applyTemplate(r.template.spec || {}, T('template "', 'template "', 'plantilla "') + n + '"');
      ctx.goto(1);
    } catch (e) { say(e.message || T('falha ao carregar o template', 'failed to load the template', 'no se pudo cargar la plantilla'), true); }
  } }, T('Usar template →', 'Use template →', 'Usar plantilla →'));
  const tplDel = el('button', { class: 'btn danger', onclick: async () => {
    const n = tplSel.value; if (!n || !confirm(T('Excluir o template "', 'Delete the template "', 'Eliminar la plantilla "') + n + '"?')) return;
    try { await ctx.api.post('/treino/contest-create/templates', { op: 'delete', name: n }); say(T('template excluído', 'template deleted', 'plantilla eliminada')); loadTemplates(); }
    catch (e) { say(e.message || T('falha', 'failed', 'fallido'), true); }
  } }, '✕');
  const tplBox = el('div', { class: 'start-card' },
    el('h3', {}, T('📋 A partir de um template salvo', '📋 From a saved template', '📋 A partir de una plantilla guardada')),
    el('p', { class: 'muted small' }, T('Pré-preenche modo, duração, opções, linguagens e visual (datas viram "a partir da próxima hora cheia").', 'Pre-fills mode, duration, options, languages and appearance (dates become "from the next full hour").', 'Rellena de antemano modo, duración, opciones, lenguajes y aspecto visual (las fechas pasan a ser "a partir de la próxima hora en punto").')),
    el('div', { class: 'row' }, tplSel, tplApply, tplDel));
  async function loadTemplates() {
    tplSel.innerHTML = '';
    try {
      const r = await ctx.api.get('/treino/contest-create/templates');
      const ts = r.templates || [];
      if (!ts.length) { tplSel.append(el('option', { value: '' }, T('(você não tem templates)', '(you have no templates)', '(no tienes plantillas)'))); tplApply.disabled = tplDel.disabled = true; return; }
      tplApply.disabled = tplDel.disabled = false;
      ts.forEach((t) => tplSel.append(el('option', { value: t.name },
        t.name + ' · ' + (t.mode || '?') + (t.duration ? ' · ' + Math.round(t.duration / 3600) + 'h' : '') + (t.has_problems ? T(' · com problemas', ' · with problems', ' · con problemas') : ''))));
    } catch { tplSel.append(el('option', { value: '' }, T('(falha ao listar)', '(failed to list)', '(no se pudo listar)'))); }
  }

  // --- duplicar contest meu ---
  const dupSel = el('select', { style: 'min-width:260px' });
  const dupBtn = el('button', { class: 'btn', onclick: async () => {
    const id = dupSel.value; if (!id) return;
    say(T('carregando ', 'loading ', 'cargando ') + id + '…');
    try {
      const spec = await ctx.api.get('/treino/contest-create/export?id=' + encodeURIComponent(id));
      ctx.applyExport(spec, T('cópia de "', 'copy of "', 'copia de "') + id + '"');
      say(''); ctx.goto(1);
    } catch (e) { say(e.message || T('falha ao exportar', 'failed to export', 'no se pudo exportar'), true); }
  } }, T('Duplicar →', 'Duplicate →', 'Duplicar →'));
  // CÓPIA FIEL: o caminho acima passa pelo wizard (o enunciado é re-buscado do banco); este
  // chama /contest-create/duplicate, que copia os enunciados POR ARQUIVO — é o único jeito de
  // levar o HTML/PDF que o admin subiu à mão (o caderno da prova!) para o contest novo.
  const dupId = el('input', { placeholder: T('id novo (minúsculo; vazio = derivado do nome)', 'new id (lowercase; empty = derived from the name)', 'id nuevo (minúsculas; vacío = derivado del nombre)'), style: 'min-width:220px' });
  const dupName = el('input', { placeholder: T('nome novo (vazio = "Cópia de …")', 'new name (empty = "Cópia de …")', 'nombre nuevo (vacío = "Copia de …")'), style: 'min-width:200px' });
  // compartilhar de novo é sempre PEDIDO (o duplicate nunca herda users_from — 28/09/2026); a inscrição só liga com as
  // contas do treino (07/10/2026): sem esta caixa, a cópia fiel de um contest com inscrição seria recusada
  const dupShared = el('input', { type: 'checkbox' });
  const dupNow = el('button', { class: 'btn ghost', onclick: async () => {
    const id = dupSel.value; if (!id) return;
    const nid = dupId.value.trim().toLowerCase();
    if (nid && !/^[a-z0-9][a-z0-9-]*$/.test(nid)) { say(T('id inválido: minúsculas, números e hífen (vira subdomínio)', 'invalid id: lowercase, digits and hyphen (it becomes a subdomain)', 'id inválido: minúsculas, números y guion (se convierte en subdominio)'), true); return; }
    const rsv = (Array.isArray(ctx.perm.reserved_id_prefixes) ? ctx.perm.reserved_id_prefixes : ['icpc']).find((pfx) => nid.startsWith(pfx));
    if (rsv && !ctx.perm.is_superadmin) { say(T(`ids que começam por "${rsv}" são da organização: só um super-admin cria`, `ids starting with "${rsv}" belong to the organization: only a super-admin can create them`, `ids que empiezan por "${rsv}" son de la organización: solo un super-admin puede crearlos`), true); return; }
    if (!confirm(T('Criar AGORA uma cópia fiel de "', 'Create a faithful copy of "', 'Crear una copia fiel de "') + id + T('"?\n\nProblemas, enunciados enviados à mão, opções e visual são copiados. Usuários e submissões NÃO.', '"NOW?\n\nProblems, hand-uploaded statements, options and appearance are copied. Users and submissions are NOT.', '"AHORA?\n\nLos problemas, los enunciados subidos a mano, las opciones y el aspecto visual se copian. Los usuarios y los envíos NO.'))) return;
    dupNow.disabled = true; say(T('duplicando ', 'duplicating ', 'duplicando ') + id + '…');
    try {
      const r = await ctx.api.post('/treino/contest-create/duplicate', {
        from: id, ...(nid ? { id: nid } : {}), ...(dupName.value.trim() ? { name: dupName.value.trim() } : {}),
        ...(dupShared.checked ? { users_from: 'treino' } : {}),
      });
      say(''); ctx.showResult(r);
    } catch (e) { say(e.message || T('falha ao duplicar', 'failed to duplicate', 'no se pudo duplicar'), true); }
    dupNow.disabled = false;
  } }, T('Cópia fiel agora', 'Faithful copy now', 'Copia fiel ahora'));
  const dupBox = el('div', { class: 'start-card' },
    el('h3', {}, T('🧬 Duplicar um contest meu', '🧬 Duplicate one of my contests', '🧬 Duplicar una de mis competencias')),
    el('p', { class: 'muted small' }, T('Copia problemas, opções e visual (nunca usuários/submissões). Datas novas; revise e crie.', 'Copies problems, options and appearance (never users/submissions). New dates; review and create.', 'Copia problemas, opciones y aspecto visual (nunca usuarios/envíos). Fechas nuevas; revisa y crea.')),
    el('div', { class: 'row' }, dupSel, dupBtn),
    el('p', { class: 'muted small', style: 'margin:.5rem 0 .2rem' },
      T('Ou crie a cópia direto, sem passar pelos passos: mantém os enunciados que você subiu à mão (HTML/PDF) e a duração original.',
        'Or create the copy directly, skipping the steps: it keeps the statements you uploaded by hand (HTML/PDF) and the original duration.',
        'O crea la copia directamente, sin pasar por los pasos: mantiene los enunciados que subiste a mano (HTML/PDF) y la duración original.')),
    el('div', { class: 'row', style: 'flex-wrap:wrap' }, dupId, dupName, dupNow),
    el('label', { class: 'small', style: 'display:flex;gap:.4rem;align-items:center;margin-top:.3rem' }, dupShared,
      T('usar as contas do Treino Livre (usuários compartilhados — obrigatório se o contest tem inscrição)', 'use the Free Training accounts (shared users — required if the contest has registration)', 'usar las cuentas del Entrenamiento Libre (usuarios compartidos — obligatorio si la competencia tiene inscripción)')));

  // --- salvar template a partir de contest existente ---
  const stSel = el('select', { style: 'min-width:220px' });
  const stName = el('input', { placeholder: T('nome do template', 'template name', 'nombre de la plantilla'), style: 'min-width:180px' });
  const stProbs = el('input', { type: 'checkbox' });
  const stBtn = el('button', { class: 'btn ghost', onclick: async () => {
    const from = stSel.value, name = stName.value.trim();
    if (!from || !name) { say(T('escolha o contest e dê um nome ao template', 'choose the contest and name the template', 'elige la competencia y dale un nombre a la plantilla'), true); return; }
    try {
      await ctx.api.post('/treino/contest-create/templates', { op: 'save', name, from_contest: from, include_problems: stProbs.checked });
      say(T('template "', 'template "', 'plantilla "') + name + T('" salvo', '" saved', '" guardada')); stName.value = ''; loadTemplates();
    } catch (e) { say(e.message || T('falha ao salvar', 'failed to save', 'no se pudo guardar'), true); }
  } }, T('💾 Salvar template', '💾 Save template', '💾 Guardar plantilla'));
  const saveBox = el('div', { class: 'start-card' },
    el('h3', {}, T('💾 Salvar template de um contest existente', '💾 Save a template from an existing contest', '💾 Guardar una plantilla de una competencia existente')),
    el('div', { class: 'row', style: 'flex-wrap:wrap' }, stSel, stName,
      el('label', { class: 'small' }, stProbs, T(' incluir problemas', ' include problems', ' incluir problemas')), stBtn));

  async function loadMine() {
    dupSel.innerHTML = ''; stSel.innerHTML = '';
    try {
      const r = await ctx.api.get('/treino/contest-create/mine');
      const cs = r.contests || [];
      if (!cs.length) {
        dupSel.append(el('option', { value: '' }, T('(você ainda não criou contests)', '(you have not created contests yet)', '(todavía no has creado competencias)')));
        stSel.append(el('option', { value: '' }, T('(nenhum)', '(none)', '(ninguno)')));
        dupBtn.disabled = dupNow.disabled = stBtn.disabled = true; return;
      }
      dupBtn.disabled = dupNow.disabled = stBtn.disabled = false;
      cs.forEach((c) => {
        const label = c.id + ' — ' + (c.name || '') + ' (' + (c.problems_count || 0) + ' probs)';
        dupSel.append(el('option', { value: c.id }, label));
        stSel.append(el('option', { value: c.id }, label));
      });
    } catch {
      dupSel.append(el('option', { value: '' }, T('(falha ao listar)', '(failed to list)', '(no se pudo listar)')));
      stSel.append(el('option', { value: '' }, T('(falha ao listar)', '(failed to list)', '(no se pudo listar)')));
    }
  }

  // --- importar tar.gz + baixar template ---
  const fileInp = el('input', { type: 'file', accept: '.tar.gz,.tgz,application/gzip', style: 'display:none' });
  fileInp.addEventListener('change', async () => {
    const f = fileInp.files[0]; if (!f) return;
    say(T('Importando ', 'Importing ', 'Importando ') + f.name + '…');
    try {
      const buf = await f.arrayBuffer(); const b = new Uint8Array(buf); let bin = '';
      for (let i = 0; i < b.length; i += 0x8000) bin += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
      ctx.showResult(await ctx.api.post('/treino/contest-create/import', { tar_b64: btoa(bin) }));
    } catch (e) { say(T('Falha no import: ', 'Import failed: ', 'Error al importar: ') + (e.message || T('erro', 'error', 'error')), true); }
    fileInp.value = '';
  });
  async function downloadTemplate() {
    try {
      const r = await fetch('/api/v1/treino/contest-create/template', { headers: { Authorization: 'Bearer ' + ctx.api.token() } });
      if (!r.ok) throw new Error('HTTP ' + r.status);
      const blob = await r.blob(); const a = document.createElement('a');
      a.href = URL.createObjectURL(blob); a.download = 'contest-template.json'; a.click(); URL.revokeObjectURL(a.href);
    } catch { say(T('Falha ao baixar o template.', 'Failed to download the template.', 'No se pudo descargar la plantilla.'), true); }
  }
  const advBox = el('div', { class: 'start-card' },
    el('h3', {}, T('📦 Arquivo (avançado)', '📦 File (advanced)', '📦 Archivo (avanzado)')),
    el('p', { class: 'muted small' }, T('Importe um .tar.gz com contest.json (+ enunciados/) — cria direto. O template JSON documenta todos os campos.', 'Import a .tar.gz with contest.json (+ enunciados/) — creates directly. The JSON template documents all fields.', 'Importa un .tar.gz con contest.json (+ enunciados/) — crea directamente. La plantilla JSON documenta todos los campos.')),
    el('div', { class: 'row' },
      el('button', { class: 'btn ghost', onclick: () => fileInp.click() }, T('⬆ Importar .tar.gz', '⬆ Import .tar.gz', '⬆ Importar .tar.gz')), fileInp,
      el('button', { class: 'btn ghost', onclick: downloadTemplate }, T('⬇ Template (JSON)', '⬇ Template (JSON)', '⬇ Plantilla (JSON)'))));

  loadTemplates(); loadMine();
  root.append(el('div', { class: 'section' },
    el('h2', {}, T('0 · Começar de…', '0 · Start from…', '0 · Empezar desde…')), msg, blank, tplBox, dupBox, saveBox, advBox));
  return { el: root };
}
