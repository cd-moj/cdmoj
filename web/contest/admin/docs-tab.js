// contest/admin/docs-tab.js — aba "📄 Documentos" (admin e juiz-chefe): gera o info sheet, o
// caderno da prova (com capa customizável), a folha de time limits e o EDITORIAL (solução de
// cada problema; só publica após o fim), em PDF+HTML e nos TRÊS idiomas; baixa, publica
// (seção "Prova" do contest + notícia opcional com o PDF anexo) e despublica. O .cstaff só
// VÊ o que foi publicado (gates de fase e publicação na API, não aqui).
//
// Idioma: PT/EN/ES vale para capa, títulos e tabelas. O corpo do ENUNCIADO sai no idioma em
// que foi escrito — o MOJ não traduz enunciado (dito na própria tela, para não enganar); para
// prova traduzida existe o PDF ENVIADO, que vence o gerado.
//
// .odt (25/09/2026): todo PDF gerado tem o gêmeo .odt — o intermediário editável. A organização
// (admin/juiz-chefe; a API corta os demais) baixa, ajusta no LibreOffice o que o Markdown deixou torto
// (espaço entre elementos, imagem grande), exporta PDF e sobe em "subir PDF" (o enviado vence o gerado).
// Os TEMPLATES (capa e info sheet) usam o editor do MOJ (realce + números de linha), uma ABA por idioma
// como na gestão de problemas, e já abrem com o texto padrão (a capa também, desde que virou template).
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { T } from '/shared/i18n.js';
import { fmtEpoch as fmtDate, fmtKB } from '/shared/admin-ui.js';
import { createEditor } from '/shared/editor.js';

const enc = encodeURIComponent;
const LANGS = ['pt', 'en', 'es'];           // idioma dos DOCUMENTOS (outro eixo que o da interface)
const PDF_MAX_MB = 60;                       // o mesmo teto do handler (DOC_PDF_MAX_MB)

const TYPES = [
  { id: 'info-sheet', pt: 'Ambiente de julgamento', en: 'Judging environment',
    hpt: 'Sistema, compiladores, linguagens, limites, linhas de compilação e execução, veredictos e penalidade. Envie um PDF pronto ou gere.',
    hen: 'System, compilers, languages, limits, compile and run lines, verdicts and penalty. Upload a ready PDF or generate.',
    es: 'Entorno de evaluación', hes: 'Sistema, compiladores, lenguajes, límites, líneas de compilación y ejecución, veredictos y penalización. Sube un PDF listo o genéralo.' },
  { id: 'contest', pt: 'Caderno da prova', en: 'Problem set',
    hpt: 'Capa + enunciados (usa o PDF do problema quando existir).', hen: 'Cover + statements (uses each problem PDF when present).',
    es: 'Cuadernillo de la competencia', hes: 'Portada + enunciados (usa el PDF de cada problema cuando existe).' },
  { id: 'times', pt: 'Folha de time limits', en: 'Time limits sheet',
    hpt: 'Tabela letra · nome · tempo limite (+ errata).', hen: 'Table letter · name · time limit (+ errata).',
    es: 'Hoja de límites de tiempo', hes: 'Tabla letra · nombre · límite de tiempo (+ fe de erratas).' },
  { id: 'editorial', pt: 'Editorial', en: 'Editorial',
    hpt: 'A solução de cada problema (docs/solucao.md do pacote). Gere e revise quando quiser; SÓ PUBLICA depois do fim da prova (todas as sedes).',
    hen: 'Each problem’s solution write-up (the package’s docs/solucao.md). Generate and review anytime; it can only be PUBLISHED after the contest ends (all sites).',
    es: 'Editorial', hes: 'La solución de cada problema (docs/solucao.md del paquete). Genérala y revísala cuando quieras; SOLO se PUBLICA después del fin de la competencia (todas las sedes).' },
];

export function makeDocsTab(CONTEST, opts = {}) {
  const readOnly = !!opts.readOnly;         // .cstaff: só baixa o que está publicado
  const bare = !!opts.bare;                 // página própria já tem título/introdução
  const panel = el('div', { class: 'section' });
  let DATA = null;

  async function api(path, body) {
    return body ? apiPost(path, body, { contest: CONTEST, auth: true })
                : apiGet(path, { contest: CONTEST, auth: true });
  }
  async function download(type, lang, fmt) {
    const path = `/contest/doc?contest=${enc(CONTEST)}&type=${enc(type)}&lang=${enc(lang)}&fmt=${enc(fmt)}`;
    const r = await fetch('/api/v1' + path, { headers: { Authorization: 'Bearer ' + (getToken(CONTEST) || '') } });
    if (!r.ok) { alert(T('Falha ao baixar (HTTP ', 'Download failed (HTTP ', 'Error al descargar (HTTP ') + r.status + ')'); return; }
    const url = URL.createObjectURL(await r.blob());
    const a = el('a', { href: url, download: `${CONTEST}-${type}.${lang}.${fmt}` });
    document.body.append(a); a.click();
    setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 0);
  }
  function openDoc(type, lang, fmt) {   // abrir p/ conferir/imprimir (mesmo padrão das etiquetas)
    const w = window.open('', '_blank');
    const path = `/api/v1/contest/doc?contest=${enc(CONTEST)}&type=${enc(type)}&lang=${enc(lang)}&fmt=${enc(fmt)}`;
    fetch(path, { headers: { Authorization: 'Bearer ' + (getToken(CONTEST) || '') } })
      .then(r => r.blob()).then(b => { const u = URL.createObjectURL(b); if (w) w.location = u; })
      .catch(() => { if (w) w.close(); alert(T('Falha ao abrir.', 'Failed to open.', 'No se pudo abrir.')); });
  }

  const msg = el('div', { class: 'small', style: 'margin:.4rem 0' });
  const setMsg = (t, cls) => { msg.className = 'small ' + (cls || ''); msg.textContent = t; };

  function docRow(t) {
    const row = el('div', { class: 'subcard', style: 'margin:.5rem 0' });
    row.append(el('div', { class: 'row', style: 'gap:.6rem;align-items:baseline' },
      el('b', {}, T(t.pt, t.en, t.es)), el('span', { class: 'small muted' }, T(t.hpt, t.hen, t.hes))));
    LANGS.forEach(lang => {
      const d = (DATA.docs || []).find(x => x.type === t.id && x.lang === lang);
      const line = el('div', { class: 'row', style: 'gap:.5rem;margin-top:.35rem;align-items:center' },
        el('span', { class: 'pill' }, lang.toUpperCase()));
      if (d) {
        // PDF ENVIADO vence o gerado no que o mundo baixa — a linha diz qual é qual. Enviado
        // e ainda não publicado = "pronto para publicar": o PDF pronto é um documento completo,
        // não precisa gerar a versão do MOJ (o servidor sempre aceitou; a lista é que o escondia).
        line.append(d.uploaded
          ? el('span', { class: 'small' }, el('b', {}, T('enviado', 'uploaded', 'subido')),
              ` · PDF ${fmtKB(d.uploaded_bytes)}`,
              d.published ? '' : el('span', { class: 'muted' }, T(' · pronto para publicar', ' · ready to publish', ' · listo para publicar')),
              d.pdf_bytes ? el('span', { class: 'muted' }, T(' (o gerado está guardado)', ' (generated copy kept)', ' (se conserva la copia generada)')) : '')
          : el('span', { class: 'small muted' }, `${T('gerado', 'generated', 'generado')} ${fmtDate(d.generated_at)} · PDF ${fmtKB(d.pdf_bytes)} · HTML ${fmtKB(d.html_bytes)}`),
          el('button', { class: 'btn ghost', onclick: () => download(t.id, lang, 'pdf') }, 'PDF'));
        if (!d.uploaded && d.html_bytes) line.append(el('button', { class: 'btn ghost', onclick: () => download(t.id, lang, 'html') }, 'HTML'));
        // o .odt editável é da ORGANIZAÇÃO (a API devolve 403 p/ os demais); só existe p/ o que foi gerado
        if (!readOnly && d.odt_bytes) line.append(el('button', { class: 'btn ghost',
          title: T('o documento editável: ajuste no LibreOffice (ou Word), exporte em PDF e suba em “subir PDF” — o enviado vence o gerado',
            'the editable document: adjust it in LibreOffice (or Word), export to PDF and upload it with “upload PDF” — the uploaded file wins',
            'el documento editable: ajústalo en LibreOffice (o Word), expórtalo a PDF y súbelo con “subir PDF” — el archivo subido gana al generado'),
          onclick: () => download(t.id, lang, 'odt') }, '✎ .odt'));
        line.append(el('button', { class: 'btn ghost', onclick: () => openDoc(t.id, lang, 'pdf') }, T('abrir', 'open', 'abrir')));
        if (d.published) line.append(el('span', { class: 'pill ok' }, T('publicado', 'published', 'publicado')));
      } else {
        line.append(el('span', { class: 'small muted' }, readOnly
          ? T('ainda não disponível', 'not available yet', 'todavía no disponible')
          : T('sem documento — gere ou envie um PDF', 'no document — generate or upload a PDF', 'sin documento — genera o sube un PDF')));
      }
      if (!readOnly) {
        line.append(el('span', { style: 'flex:1' }));
        line.append(uploadBtn(t.id, lang, !!(d && d.uploaded)));
        line.append(el('button', { class: 'btn', onclick: () => generate([t.id], [lang]) }, T('gerar', 'generate', 'generar')));
        if (d) {
          if (d.published) {
            line.append(el('button', { class: 'btn ghost', onclick: () => publish(t.id, lang, false) }, T('despublicar', 'unpublish', 'despublicar')));
          } else {
            const chk = el('input', { type: 'checkbox', id: `news-${t.id}-${lang}` });
            line.append(el('label', { class: 'small row', style: 'gap:.25rem' }, chk, T('+ notícia', '+ news', '+ noticia')),
              el('button', { class: 'btn', onclick: () => publish(t.id, lang, true, chk.checked) }, T('publicar', 'publish', 'publicar')));
          }
        }
      }
      row.append(line);
    });
    return row;
  }

  // --- PDF PRONTO enviado pelo admin (vence o gerado) ---------------------------------
  // ⚠ o base64 sai do FileReader (fileToBase64). O código antigo fazia
  // `btoa(String.fromCharCode(...new Uint8Array(buf)))` — um argumento por byte, que estoura a
  // pilha do V8 a partir de ~100 KB — e a linha ficava FORA do try: o clique morria calado.
  async function sendPdf(action, extra, f, okMsg) {
    if (f.size > PDF_MAX_MB * 1024 * 1024) {
      setMsg(T(`PDF muito grande (máx ${PDF_MAX_MB}MB).`, `PDF too large (max ${PDF_MAX_MB}MB).`, `PDF demasiado grande (máx ${PDF_MAX_MB}MB).`), 'error-box');
      return false;
    }
    setMsg(T('Enviando o PDF…', 'Uploading the PDF…', 'Subiendo el PDF…'));
    try {
      await api('/contest/admin/docs?contest=' + enc(CONTEST), { action, ...extra, pdf_b64: await fileToBase64(f) });
      setMsg(okMsg); await load(); return true;
    } catch (e) { setMsg(e.message || T('falha', 'failed', 'fallido'), 'error-box'); return false; }
  }

  function uploadBtn(type, lang, has) {
    const inp = el('input', { type: 'file', accept: 'application/pdf', style: 'display:none' });
    inp.addEventListener('change', () => {
      const f = inp.files && inp.files[0];
      if (f) sendPdf('upload', { type, lang }, f, T('✓ PDF enviado — é ele que os times baixam', '✓ PDF uploaded — this is what teams download', '✓ PDF subido — es lo que descargan los equipos'));
    });
    const box = el('span', { class: 'row', style: 'gap:.3rem' }, inp,
      el('button', { class: 'btn ghost', title: T('subir o PDF pronto deste documento (vence o gerado)', 'upload the finished PDF for this document (wins over the generated one)', 'sube el PDF terminado de este documento (gana al generado)'),
        onclick: () => inp.click() }, has ? T('trocar PDF', 'replace PDF', 'reemplazar PDF') : T('subir PDF', 'upload PDF', 'subir PDF')));
    if (has) box.append(el('button', { class: 'btn ghost', onclick: async () => {
      if (!confirm(T('Voltar ao PDF gerado pelo MOJ?', 'Go back to the MOJ-generated PDF?', '¿Volver al PDF generado por MOJ?'))) return;
      try {
        await api('/contest/admin/docs?contest=' + enc(CONTEST), { action: 'upload', type, lang, remove_upload: true });
        setMsg(T('✓ voltou ao gerado', '✓ back to the generated one', '✓ volvió al generado')); await load();
      } catch (e) { setMsg(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
    } }, T('voltar ao gerado', 'back to generated', 'volver al generado')));
    return box;
  }

  async function generate(types, langs) {
    setMsg(T('Gerando… (converter PDF pode levar alguns segundos)', 'Generating… (PDF conversion may take a few seconds)', 'Generando… (la conversión a PDF puede tardar unos segundos)'));
    try {
      const j = await api('/contest/admin/docs?contest=' + enc(CONTEST), { action: 'generate', types, langs });
      setMsg(T(`✓ ${j.counts.ok} documento(s) gerado(s)`, `✓ ${j.counts.ok} document(s) generated`, `✓ ${j.counts.ok} documento(s) generado(s)`)
        + (j.counts.fail ? T(` · ${j.counts.fail} falharam`, ` · ${j.counts.fail} failed`, ` · ${j.counts.fail} fallaron`) : ''), j.counts.fail ? 'error-box' : '');
      await load();
    } catch (e) { setMsg(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
  }
  async function publish(type, lang, on, news) {
    try {
      await api('/contest/admin/docs?contest=' + enc(CONTEST),
        on ? { action: 'publish', type, lang, news: !!news } : { action: 'unpublish', type, lang });
      setMsg(on ? T('✓ publicado (aparece na seção Prova e para a sede)', '✓ published (shown under Contest and to the site)', '✓ publicado (aparece en la sección Competencia y para la sede)')
                : T('✓ despublicado', '✓ unpublished', '✓ despublicado'));
      await load();
    } catch (e) { setMsg(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
  }

  // editor de TEMPLATE com uma aba por idioma (as mesmas fichas da gestão de problemas): o editor do
  // MOJ (CodeMirror: realce de Markdown + números de linha), montado sob demanda e mantido ao trocar de
  // aba — trocar de idioma não perde o que foi digitado; "Salvar" grava TODOS os idiomas alterados.
  // O texto é o do contest, senão o PADRÃO do MOJ (a API manda o padrão; `custom` diz qual é).
  function templateBox(kind, title, help, extraFor) {
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' });
    const chips = el('div', { class: 'stmt-chips', title: T('idioma do documento', 'document language', 'idioma del documento') });
    const status = el('span', { class: 'small muted' });
    const extra = el('div', {});
    const area = el('div', {});
    const mounts = {}, eds = {}, orig = {};
    const tpl = (l) => (((DATA.templates || {})[kind] || {})[l]) || (DATA.templates || {})[kind + '_' + l] || '';
    const custom = (l) => !!(((DATA.custom || {})[kind] || {})[l]);
    let cur = LANGS[0];
    function paintChips() {
      chips.innerHTML = '';
      LANGS.forEach(l => chips.append(el('button', { type: 'button', class: 'stmt-chip' + (l === cur ? ' active' : ''),
        onclick: () => show(l) }, l.toUpperCase())));
    }
    async function show(l) {
      cur = l; paintChips();
      Object.entries(mounts).forEach(([k, m]) => { m.style.display = k === l ? '' : 'none'; });
      status.textContent = custom(l) ? T('texto editado neste contest', 'text edited in this contest', 'texto editado en esta competencia')
                                     : T('texto padrão do MOJ', 'MOJ default text', 'texto predeterminado de MOJ');
      extra.innerHTML = ''; if (extraFor) { const x = extraFor(l); if (x) extra.append(x); }
      if (!mounts[l]) {
        const m = el('div', { class: 'editor-mount' }); area.append(m); mounts[l] = m;
        orig[l] = tpl(l);
        eds[l] = await createEditor(m, { doc: orig[l], cm: 'markdown' });
      }
    }
    const save = el('button', { class: 'btn', onclick: async () => {
      const body = { action: 'config' }; let n = 0;
      Object.keys(eds).forEach(l => { const v = eds[l].getValue(); if (v !== orig[l]) { body[kind + '_' + l] = v; n++; } });
      if (!n) { setMsg(T('Nada mudou.', 'Nothing changed.', 'Nada cambió.')); return; }
      try { await api('/contest/admin/docs?contest=' + enc(CONTEST), body); setMsg(T('✓ salvo — gere o documento de novo', '✓ saved — generate the document again', '✓ guardado — genera el documento de nuevo')); await load(); }
      catch (e) { setMsg(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
    } }, T('Salvar', 'Save', 'Guardar'));
    const reset = el('button', { class: 'btn ghost', onclick: async () => {
      if (!confirm(T(`Voltar o ${cur.toUpperCase()} ao texto padrão do MOJ?`, `Restore the ${cur.toUpperCase()} text to the MOJ default?`, `¿Restaurar el texto ${cur.toUpperCase()} al predeterminado de MOJ?`))) return;
      try { await api('/contest/admin/docs?contest=' + enc(CONTEST), { action: 'config', [kind + '_' + cur]: '' }); setMsg(T('✓ voltou ao padrão', '✓ back to the default', '✓ volvió al predeterminado')); await load(); }
      catch (e) { setMsg(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
    } }, T('voltar ao padrão', 'restore default', 'restaurar predeterminado'));
    box.append(el('h3', { style: 'margin:.1rem 0 .4rem' }, title), el('p', { class: 'small muted', style: 'margin:.1rem 0 .5rem' }, help),
      el('div', { class: 'row', style: 'gap:.6rem;align-items:center;margin-bottom:.4rem' }, chips, status), extra, area,
      el('div', { class: 'row', style: 'gap:.4rem;margin-top:.4rem' }, save, reset));
    show(cur);
    return box;
  }

  function coverBox() {
    return templateBox('cover', T('🎨 Capa do caderno', '🎨 Problem set cover', '🎨 Portada del cuadernillo'),
      T('Dois modos, nesta ordem de precedência: PDF enviado › este texto (que já vem com o padrão do MOJ). Marcadores: {{CONTEST_NAME}} {{DATE}} {{N_PROBLEMS}} {{N_PAGES}} {{SITES}} {{VERSION}} {{NOTE}}. {{N_PAGES}}, {{SITES}} e {{NOTE}} são opcionais: o bloco em que um deles fica vazio some.',
        'Two modes, in this precedence: uploaded PDF › this text (which starts as the MOJ default). Markers: {{CONTEST_NAME}} {{DATE}} {{N_PROBLEMS}} {{N_PAGES}} {{SITES}} {{VERSION}} {{NOTE}}. {{N_PAGES}}, {{SITES}} and {{NOTE}} are optional: a block where one of them is empty disappears.',
        'Dos modos, en este orden de precedencia: PDF subido › este texto (que empieza con el predeterminado de MOJ). Marcadores: {{CONTEST_NAME}} {{DATE}} {{N_PROBLEMS}} {{N_PAGES}} {{SITES}} {{VERSION}} {{NOTE}}. {{N_PAGES}}, {{SITES}} y {{NOTE}} son opcionales: el bloque donde uno de ellos esté vacío desaparece.'),
      (lang) => {
        const up = (DATA.cover_uploaded || {})[lang];
        const file = el('input', { type: 'file', accept: 'application/pdf', style: 'display:none' });
        file.addEventListener('change', () => {
          const f = file.files && file.files[0]; if (!f) return;
          sendPdf('cover', { lang }, f, T('✓ capa enviada — gere o caderno de novo', '✓ cover uploaded — generate the problem set again', '✓ portada subida — genera el cuadernillo de nuevo'));
        });
        return el('div', { class: 'row', style: 'gap:.5rem;align-items:center;margin:.2rem 0 .4rem' },
          up ? el('span', { class: 'pill ok' }, T('PDF de capa enviado (vence o texto)', 'uploaded cover PDF (overrides the text)', 'PDF de portada subido (sustituye al texto)'))
             : el('span', { class: 'small muted' }, T('sem capa em PDF enviada', 'no uploaded cover PDF', 'sin PDF de portada subido')),
          el('button', { class: 'btn ghost', onclick: () => file.click() }, up ? T('trocar PDF de capa…', 'replace cover PDF…', 'reemplazar PDF de portada…') : T('enviar PDF de capa…', 'upload cover PDF…', 'subir PDF de portada…')),
          up ? el('button', { class: 'btn ghost', onclick: async () => {
            if (!confirm(T('Remover o PDF de capa?', 'Remove the cover PDF?', '¿Eliminar el PDF de portada?'))) return;
            await api('/contest/admin/docs?contest=' + enc(CONTEST), { action: 'cover', lang, remove: true });
            await load();
          } }, T('remover', 'remove', 'quitar')) : null,
          file);
      });
  }

  function configBox() {
    const cfg = DATA.config || {};
    const ver = el('input', { value: cfg.caderno_version || 'v1.0', style: 'width:7rem' });
    const note = el('textarea', { rows: '2', style: 'width:100%' }, cfg.cover_note || '');
    const err = el('textarea', { rows: '3', style: 'width:100%' }, cfg.errata || '');
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' },
      el('h3', { style: 'margin:.1rem 0 .4rem' }, T('⚙️ Dados dos documentos', '⚙️ Document data', '⚙️ Datos de los documentos')),
      el('div', { class: 'row', style: 'gap:.5rem;align-items:center' }, el('span', { class: 'small' }, T('versão do caderno', 'problem set version', 'versión del cuadernillo')), ver),
      el('div', { class: 'small', style: 'margin-top:.4rem' }, T('nota da capa (Markdown; entra no marcador {{NOTE}} da capa)', 'cover note (Markdown; fills the {{NOTE}} marker of the cover)', 'nota de portada (Markdown; llena el marcador {{NOTE}} de la portada)')), note,
      el('div', { class: 'small', style: 'margin-top:.4rem' }, T('errata (aparece na folha de time limits)', 'errata (shown on the time limits sheet)', 'fe de erratas (aparece en la hoja de time limits)')), err,
      el('button', { class: 'btn', style: 'margin-top:.4rem', onclick: async () => {
        try {
          await api('/contest/admin/docs?contest=' + enc(CONTEST),
            { action: 'config', caderno_version: ver.value.trim(), cover_note: note.value, errata: err.value });
          setMsg(T('✓ salvo', '✓ saved', '✓ guardado')); await load();
        } catch (e) { setMsg(e.message || T('falha', 'failed', 'fallido'), 'error-box'); }
      } }, T('salvar', 'save', 'guardar')));
    return box;
  }

  function infoSheetBox() {
    return templateBox('info_sheet', T('📝 Texto do info sheet', '📝 Info sheet text', '📝 Texto del info sheet'),
      T('Markdown. Os marcadores {{TOOLCHAIN}} {{TL_TABLE}} {{LANGS_TABLE}} {{MEMLIMIT}} {{STACK}} {{CONTEST_NAME}} {{DATE}} são preenchidos na geração.',
        'Markdown. Markers {{TOOLCHAIN}} {{TL_TABLE}} {{LANGS_TABLE}} {{MEMLIMIT}} {{STACK}} {{CONTEST_NAME}} {{DATE}} are filled in at generation time.',
        'Markdown. Los marcadores {{TOOLCHAIN}} {{TL_TABLE}} {{LANGS_TABLE}} {{MEMLIMIT}} {{STACK}} {{CONTEST_NAME}} {{DATE}} se completan al generar.'));
  }

  function render() {
    panel.innerHTML = '';
    if (!bare) panel.append(el('h2', {}, T('📄 Documentos da prova', '📄 Contest documents', '📄 Documentos de la competencia')));
    if (readOnly) {
      if (!bare) panel.append(el('p', { class: 'small muted' },
        T('Documentos publicados pela organização — baixe e imprima na sede.',
          'Documents published by the organization — download and print at your site.',
          'Documentos publicados por la organización — descárgalos e imprímelos en tu sede.')));
      panel.append(el('div', { class: 'row', style: 'gap:.5rem;margin:.3rem 0' },
        el('button', { class: 'btn ghost', onclick: load }, T('↻ atualizar', '↻ refresh', '↻ actualizar'))));
      if (!(DATA.docs || []).length) panel.append(el('div', { class: 'small muted', style: 'margin:.4rem 0' },
        T('A organização ainda não publicou documentos. Volte mais perto da prova.',
          'The organization has not published any documents yet. Check back closer to the contest.',
          'La organización todavía no publicó documentos. Vuelve más cerca de la competencia.')));
    } else {
      panel.append(el('p', { class: 'small muted' },
        T('Gere em PDF e HTML, em pt, en e es. Publicar deixa o documento visível na seção “Prova” do contest e para os chefes de sede (.cstaff).',
          'Generate as PDF and HTML, in pt, en and es. Publishing shows the document under “Contest” and to site chiefs (.cstaff).',
          'Genera en PDF y HTML, en pt, en y es. Publicar deja el documento visible en la sección “Competencia” y para los jefes de sede (.cstaff).')),
        el('p', { class: 'small muted' },
          T('⚠️ O idioma vale para capa, títulos e tabelas. O enunciado sai no idioma em que foi escrito — para prova traduzida, use “subir PDF” (o enviado vence o gerado).',
            '⚠️ The language applies to cover, headings and tables. Statements come out in the language they were written in — for a translated set, use “upload PDF” (the uploaded file wins).',
            '⚠️ El idioma se aplica a la portada, los títulos y las tablas. El enunciado sale en el idioma en que fue escrito — para una prueba traducida, usa “subir PDF” (el archivo subido gana al generado).')),
        el('p', { class: 'small muted' },
          T('✎ Algo torto no PDF gerado (espaço demais ou de menos entre os elementos, imagem grande)? Baixe o “✎ .odt”, ajuste no LibreOffice (ou Word), exporte em PDF e suba em “subir PDF” — o enviado vence o gerado e é ele que os times baixam.',
            '✎ Something off in the generated PDF (too much or too little space between elements, an oversized image)? Download the “✎ .odt”, adjust it in LibreOffice (or Word), export to PDF and upload it with “upload PDF” — the uploaded file wins and is what teams download.',
            '✎ ¿Algo torcido en el PDF generado (demasiado espacio o muy poco entre los elementos, una imagen grande)? Descarga el “✎ .odt”, ajústalo en LibreOffice (o Word), expórtalo a PDF y súbelo con “subir PDF” — el archivo subido gana al generado y es lo que descargan los equipos.')),
        el('div', { class: 'row', style: 'gap:.5rem;margin:.5rem 0' },
          el('button', { class: 'btn', onclick: () => generate(TYPES.map(t => t.id), LANGS) },
            T('⚙️ Gerar todos (pt+en+es)', '⚙️ Generate all (pt+en+es)', '⚙️ Generar todo (pt+en+es)')),
          el('button', { class: 'btn ghost', onclick: load }, '↻')));
    }
    panel.append(msg);
    TYPES.forEach(t => panel.append(docRow(t)));
    if (!readOnly) {
      const probs = DATA.problems || [];
      const semEnun = probs.filter(p => !p.has_pdf && !p.has_html);
      if (semEnun.length) panel.append(el('div', { class: 'error-box small', style: 'margin:.5rem 0' },
        T('⚠️ sem enunciado no contest: ', '⚠️ no statement in the contest: ', '⚠️ sin enunciado en la competencia: ') + semEnun.map(p => p.letter).join(', ')
        + T(' — o caderno usa o enunciado do banco, se houver.', ' — the problem set falls back to the bank statement, if any.', ' — el cuadernillo recurre al enunciado del banco, si existe.')));
      panel.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' },
        T(`${probs.length} problema(s) · ${probs.filter(p => p.has_pdf).length} com PDF próprio`,
          `${probs.length} problem(s) · ${probs.filter(p => p.has_pdf).length} with their own PDF`,
          `${probs.length} problema(s) · ${probs.filter(p => p.has_pdf).length} con PDF propio`)));
      panel.append(configBox(), coverBox(), infoSheetBox());
    }
  }

  async function load() {
    if (!DATA) panel.append(el('div', { class: 'muted small' }, T('carregando…', 'loading…', 'cargando…')));
    try {
      // só-leitura (sede) usa a rota de LISTAGEM — a de admin é cortada p/ .cstaff na API
      DATA = await api((readOnly ? '/contest/doc?contest=' : '/contest/admin/docs?contest=') + enc(CONTEST));
      render();
    } catch (e) {
      panel.innerHTML = '';
      if (!bare) panel.append(el('h2', {}, T('📄 Documentos da prova', '📄 Contest documents', '📄 Documentos de la competencia')));
      panel.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load', 'falló al cargar')));
    }
  }
  return { panel, load };
}
