// contest/admin/docs-tab.js — aba "📄 Documentos" (admin e juiz-chefe): gera o info sheet, o
// caderno da prova (com capa customizável), a folha de time limits e o EDITORIAL (solução de
// cada problema; só publica após o fim), em PDF+HTML e nos TRÊS idiomas; baixa, publica
// (seção "Prova" do contest + notícia opcional com o PDF anexo) e despublica. O .cstaff só
// VÊ o que foi publicado (gates de fase e publicação na API, não aqui).
//
// Idioma: PT/EN/ES vale para capa, títulos e tabelas. O corpo do ENUNCIADO sai no idioma em
// que foi escrito — o MOJ não traduz enunciado (dito na própria tela, para não enganar); para
// prova traduzida existe o PDF ENVIADO, que vence o gerado.
import { apiGet, apiPost, getToken } from '/shared/api.js';
import { el } from '/shared/ui.js';
import { fileToBase64 } from '/shared/auth.js';
import { T } from '/shared/i18n.js';

const enc = encodeURIComponent;
const LANGS = ['pt', 'en', 'es'];           // idioma dos DOCUMENTOS (a interface segue pt/en)
const PDF_MAX_MB = 60;                       // o mesmo teto do handler (DOC_PDF_MAX_MB)
const fmtDate = (e) => (+e ? new Date(+e * 1000).toLocaleString() : '—');
const fmtKB = (n) => (!n ? '—' : n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.max(1, Math.round(n / 1024)) + ' KB');

const TYPES = [
  { id: 'info-sheet', pt: 'Informações do ambiente', en: 'Testing environment',
    hpt: 'Compiladores, limites de memória/tempo e linguagens aceitas.', hen: 'Compilers, memory/time limits and accepted languages.' },
  { id: 'contest', pt: 'Caderno da prova', en: 'Problem set',
    hpt: 'Capa + enunciados (usa o PDF do problema quando existir).', hen: 'Cover + statements (uses each problem PDF when present).' },
  { id: 'times', pt: 'Folha de time limits', en: 'Time limits sheet',
    hpt: 'Tabela letra · nome · tempo limite (+ errata).', hen: 'Table letter · name · time limit (+ errata).' },
  { id: 'editorial', pt: 'Editorial', en: 'Editorial',
    hpt: 'A solução de cada problema (docs/solucao.md do pacote). Gere e revise quando quiser; SÓ PUBLICA depois do fim da prova (todas as sedes).',
    hen: 'Each problem’s solution write-up (the package’s docs/solucao.md). Generate and review anytime; it can only be PUBLISHED after the contest ends (all sites).' },
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
    if (!r.ok) { alert(T('Falha ao baixar (HTTP ', 'Download failed (HTTP ') + r.status + ')'); return; }
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
      .catch(() => { if (w) w.close(); alert(T('Falha ao abrir.', 'Failed to open.')); });
  }

  const msg = el('div', { class: 'small', style: 'margin:.4rem 0' });
  const setMsg = (t, cls) => { msg.className = 'small ' + (cls || ''); msg.textContent = t; };

  function docRow(t) {
    const row = el('div', { class: 'subcard', style: 'margin:.5rem 0' });
    row.append(el('div', { class: 'row', style: 'gap:.6rem;align-items:baseline' },
      el('b', {}, T(t.pt, t.en)), el('span', { class: 'small muted' }, T(t.hpt, t.hen))));
    LANGS.forEach(lang => {
      const d = (DATA.docs || []).find(x => x.type === t.id && x.lang === lang);
      const line = el('div', { class: 'row', style: 'gap:.5rem;margin-top:.35rem;align-items:center' },
        el('span', { class: 'pill' }, lang.toUpperCase()));
      if (d) {
        // PDF ENVIADO vence o gerado no que o mundo baixa — a linha diz qual é qual
        line.append(d.uploaded
          ? el('span', { class: 'small' }, el('b', {}, T('enviado', 'uploaded')),
              ` · PDF ${fmtKB(d.uploaded_bytes)}`,
              d.pdf_bytes ? el('span', { class: 'muted' }, T(' (o gerado está guardado)', ' (generated copy kept)')) : '')
          : el('span', { class: 'small muted' }, `${T('gerado', 'generated')} ${fmtDate(d.generated_at)} · PDF ${fmtKB(d.pdf_bytes)} · HTML ${fmtKB(d.html_bytes)}`),
          el('button', { class: 'btn ghost', onclick: () => download(t.id, lang, 'pdf') }, 'PDF'));
        if (!d.uploaded && d.html_bytes) line.append(el('button', { class: 'btn ghost', onclick: () => download(t.id, lang, 'html') }, 'HTML'));
        line.append(el('button', { class: 'btn ghost', onclick: () => openDoc(t.id, lang, 'pdf') }, T('abrir', 'open')));
        if (d.published) line.append(el('span', { class: 'pill ok' }, T('publicado', 'published')));
      } else {
        line.append(el('span', { class: 'small muted' }, readOnly
          ? T('ainda não disponível', 'not available yet')
          : T('ainda não gerado', 'not generated yet')));
      }
      if (!readOnly) {
        line.append(el('span', { style: 'flex:1' }));
        line.append(uploadBtn(t.id, lang, !!(d && d.uploaded)));
        line.append(el('button', { class: 'btn', onclick: () => generate([t.id], [lang]) }, T('gerar', 'generate')));
        if (d) {
          if (d.published) {
            line.append(el('button', { class: 'btn ghost', onclick: () => publish(t.id, lang, false) }, T('despublicar', 'unpublish')));
          } else {
            const chk = el('input', { type: 'checkbox', id: `news-${t.id}-${lang}` });
            line.append(el('label', { class: 'small row', style: 'gap:.25rem' }, chk, T('+ notícia', '+ news')),
              el('button', { class: 'btn', onclick: () => publish(t.id, lang, true, chk.checked) }, T('publicar', 'publish')));
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
      setMsg(T(`PDF muito grande (máx ${PDF_MAX_MB}MB).`, `PDF too large (max ${PDF_MAX_MB}MB).`), 'error-box');
      return false;
    }
    setMsg(T('Enviando o PDF…', 'Uploading the PDF…'));
    try {
      await api('/contest/admin/docs?contest=' + enc(CONTEST), { action, ...extra, pdf_b64: await fileToBase64(f) });
      setMsg(okMsg); await load(); return true;
    } catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); return false; }
  }

  function uploadBtn(type, lang, has) {
    const inp = el('input', { type: 'file', accept: 'application/pdf', style: 'display:none' });
    inp.addEventListener('change', () => {
      const f = inp.files && inp.files[0];
      if (f) sendPdf('upload', { type, lang }, f, T('✓ PDF enviado — é ele que os times baixam', '✓ PDF uploaded — this is what teams download'));
    });
    const box = el('span', { class: 'row', style: 'gap:.3rem' }, inp,
      el('button', { class: 'btn ghost', title: T('subir o PDF pronto deste documento (vence o gerado)', 'upload the finished PDF for this document (wins over the generated one)'),
        onclick: () => inp.click() }, has ? T('trocar PDF', 'replace PDF') : T('subir PDF', 'upload PDF')));
    if (has) box.append(el('button', { class: 'btn ghost', onclick: async () => {
      if (!confirm(T('Voltar ao PDF gerado pelo MOJ?', 'Go back to the MOJ-generated PDF?'))) return;
      try {
        await api('/contest/admin/docs?contest=' + enc(CONTEST), { action: 'upload', type, lang, remove_upload: true });
        setMsg(T('✓ voltou ao gerado', '✓ back to the generated one')); await load();
      } catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); }
    } }, T('voltar ao gerado', 'back to generated')));
    return box;
  }

  async function generate(types, langs) {
    setMsg(T('Gerando… (converter PDF pode levar alguns segundos)', 'Generating… (PDF conversion may take a few seconds)'));
    try {
      const j = await api('/contest/admin/docs?contest=' + enc(CONTEST), { action: 'generate', types, langs });
      setMsg(T(`✓ ${j.counts.ok} documento(s) gerado(s)`, `✓ ${j.counts.ok} document(s) generated`)
        + (j.counts.fail ? T(` · ${j.counts.fail} falharam`, ` · ${j.counts.fail} failed`) : ''), j.counts.fail ? 'error-box' : '');
      await load();
    } catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); }
  }
  async function publish(type, lang, on, news) {
    try {
      await api('/contest/admin/docs?contest=' + enc(CONTEST),
        on ? { action: 'publish', type, lang, news: !!news } : { action: 'unpublish', type, lang });
      setMsg(on ? T('✓ publicado (aparece na seção Prova e para a sede)', '✓ published (shown under Contest and to the site)')
                : T('✓ despublicado', '✓ unpublished'));
      await load();
    } catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); }
  }

  function coverBox() {
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' });
    box.append(el('h3', { style: 'margin:.1rem 0 .4rem' }, T('🎨 Capa do caderno', '🎨 Problem set cover')),
      el('p', { class: 'small muted', style: 'margin:.1rem 0 .5rem' },
        T('Três modos, nesta ordem de precedência: PDF enviado › texto editado › capa padrão. Marcadores do texto: {{CONTEST_NAME}} {{DATE}} {{N_PROBLEMS}} {{N_PAGES}} {{SITES}} {{VERSION}}.',
          'Three modes, in this precedence: uploaded PDF › edited text › default cover. Text markers: {{CONTEST_NAME}} {{DATE}} {{N_PROBLEMS}} {{N_PAGES}} {{SITES}} {{VERSION}}.')));
    LANGS.forEach(lang => {
      const up = (DATA.cover_uploaded || {})[lang];
      const ta = el('textarea', { rows: '6', style: 'width:100%;font-family:var(--mono);font-size:.86rem' },
        (DATA.templates || {})['cover_' + lang] || '');
      const file = el('input', { type: 'file', accept: 'application/pdf', style: 'display:none' });
      file.addEventListener('change', () => {
        const f = file.files && file.files[0]; if (!f) return;
        sendPdf('cover', { lang }, f, T('✓ capa enviada — gere o caderno de novo', '✓ cover uploaded — generate the problem set again'));
      });
      box.append(el('div', { style: 'margin-top:.5rem' },
        el('div', { class: 'row', style: 'gap:.5rem;align-items:center' },
          el('b', {}, lang.toUpperCase()),
          up ? el('span', { class: 'pill ok' }, T('PDF enviado (vence o texto)', 'uploaded PDF (overrides text)')) : el('span', { class: 'small muted' }, T('sem PDF enviado', 'no uploaded PDF')),
          el('button', { class: 'btn ghost', onclick: () => file.click() }, T('enviar PDF…', 'upload PDF…')),
          up ? el('button', { class: 'btn ghost', onclick: async () => {
            if (!confirm(T('Remover o PDF de capa?', 'Remove the cover PDF?'))) return;
            await api('/contest/admin/docs?contest=' + enc(CONTEST), { action: 'cover', lang, remove: true });
            await load();
          } }, T('remover', 'remove')) : null,
          file),
        el('div', { class: 'small muted', style: 'margin:.3rem 0 .15rem' }, T('ou edite o texto da capa:', 'or edit the cover text:')),
        ta,
        el('button', { class: 'btn ghost', style: 'margin-top:.3rem', onclick: async () => {
          try {
            await api('/contest/admin/docs?contest=' + enc(CONTEST), { action: 'config', ['cover_' + lang]: ta.value });
            setMsg(T('✓ capa salva', '✓ cover saved')); await load();
          } catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); }
        } }, T('salvar capa ' + lang.toUpperCase(), 'save ' + lang.toUpperCase() + ' cover'))));
    });
    return box;
  }

  function configBox() {
    const cfg = DATA.config || {};
    const ver = el('input', { value: cfg.caderno_version || 'v1.0', style: 'width:7rem' });
    const note = el('textarea', { rows: '2', style: 'width:100%' }, cfg.cover_note || '');
    const err = el('textarea', { rows: '3', style: 'width:100%' }, cfg.errata || '');
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' },
      el('h3', { style: 'margin:.1rem 0 .4rem' }, T('⚙️ Dados dos documentos', '⚙️ Document data')),
      el('div', { class: 'row', style: 'gap:.5rem;align-items:center' }, el('span', { class: 'small' }, T('versão do caderno', 'problem set version')), ver),
      el('div', { class: 'small', style: 'margin-top:.4rem' }, T('nota da capa (Markdown, capa padrão)', 'cover note (Markdown, default cover)')), note,
      el('div', { class: 'small', style: 'margin-top:.4rem' }, T('errata (aparece na folha de time limits)', 'errata (shown on the time limits sheet)')), err,
      el('button', { class: 'btn', style: 'margin-top:.4rem', onclick: async () => {
        try {
          await api('/contest/admin/docs?contest=' + enc(CONTEST),
            { action: 'config', caderno_version: ver.value.trim(), cover_note: note.value, errata: err.value });
          setMsg(T('✓ salvo', '✓ saved')); await load();
        } catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); }
      } }, T('salvar', 'save')));
    return box;
  }

  function infoSheetBox() {
    const box = el('div', { class: 'subcard', style: 'margin:.6rem 0' });
    box.append(el('h3', { style: 'margin:.1rem 0 .4rem' }, T('📝 Texto do info sheet', '📝 Info sheet text')),
      el('p', { class: 'small muted', style: 'margin:.1rem 0 .4rem' },
        T('Markdown. Os marcadores {{TOOLCHAIN}} {{TL_TABLE}} {{LANGS_TABLE}} {{MEMLIMIT}} {{STACK}} {{CONTEST_NAME}} {{DATE}} são preenchidos na geração. Deixe em branco para voltar ao texto padrão.',
          'Markdown. Markers {{TOOLCHAIN}} {{TL_TABLE}} {{LANGS_TABLE}} {{MEMLIMIT}} {{STACK}} {{CONTEST_NAME}} {{DATE}} are filled in at generation time. Leave empty to restore the default text.')));
    LANGS.forEach(lang => {
      const ta = el('textarea', { rows: '10', style: 'width:100%;font-family:var(--mono);font-size:.85rem' },
        (DATA.templates || {})['info_sheet_' + lang] || '');
      box.append(el('div', { style: 'margin-top:.5rem' },
        el('b', {}, lang.toUpperCase()), ta,
        el('button', { class: 'btn ghost', style: 'margin-top:.3rem', onclick: async () => {
          try {
            await api('/contest/admin/docs?contest=' + enc(CONTEST), { action: 'config', ['info_sheet_' + lang]: ta.value });
            setMsg(T('✓ texto salvo', '✓ text saved')); await load();
          } catch (e) { setMsg(e.message || T('falha', 'failed'), 'error-box'); }
        } }, T('salvar ' + lang.toUpperCase(), 'save ' + lang.toUpperCase()))));
    });
    return box;
  }

  function render() {
    panel.innerHTML = '';
    if (!bare) panel.append(el('h2', {}, T('📄 Documentos da prova', '📄 Contest documents')));
    if (readOnly) {
      if (!bare) panel.append(el('p', { class: 'small muted' },
        T('Documentos publicados pela organização — baixe e imprima na sede.',
          'Documents published by the organization — download and print at your site.')));
      panel.append(el('div', { class: 'row', style: 'gap:.5rem;margin:.3rem 0' },
        el('button', { class: 'btn ghost', onclick: load }, T('↻ atualizar', '↻ refresh'))));
      if (!(DATA.docs || []).length) panel.append(el('div', { class: 'small muted', style: 'margin:.4rem 0' },
        T('A organização ainda não publicou documentos. Volte mais perto da prova.',
          'The organization has not published any documents yet. Check back closer to the contest.')));
    } else {
      panel.append(el('p', { class: 'small muted' },
        T('Gere em PDF e HTML, nos dois idiomas. Publicar deixa o documento visível na seção “Prova” do contest e para os chefes de sede (.cstaff).',
          'Generate as PDF and HTML, in both languages. Publishing shows the document under “Contest” and to site chiefs (.cstaff).')),
        el('p', { class: 'small muted' },
          T('⚠️ PT/EN vale para capa, títulos e tabelas. O enunciado sai no idioma em que foi escrito.',
            '⚠️ PT/EN applies to cover, headings and tables. Statements come out in the language they were written in.')),
        el('div', { class: 'row', style: 'gap:.5rem;margin:.5rem 0' },
          el('button', { class: 'btn', onclick: () => generate(TYPES.map(t => t.id), LANGS) },
            T('⚙️ Gerar todos (pt+en+es)', '⚙️ Generate all (pt+en+es)')),
          el('button', { class: 'btn ghost', onclick: load }, '↻')));
    }
    panel.append(msg);
    TYPES.forEach(t => panel.append(docRow(t)));
    if (!readOnly) {
      const probs = DATA.problems || [];
      const semEnun = probs.filter(p => !p.has_pdf && !p.has_html);
      if (semEnun.length) panel.append(el('div', { class: 'error-box small', style: 'margin:.5rem 0' },
        T('⚠️ sem enunciado no contest: ', '⚠️ no statement in the contest: ') + semEnun.map(p => p.letter).join(', ')
        + T(' — o caderno usa o enunciado do banco, se houver.', ' — the problem set falls back to the bank statement, if any.')));
      panel.append(el('div', { class: 'small muted', style: 'margin:.3rem 0' },
        T(`${probs.length} problema(s) · ${probs.filter(p => p.has_pdf).length} com PDF próprio`,
          `${probs.length} problem(s) · ${probs.filter(p => p.has_pdf).length} with their own PDF`)));
      panel.append(configBox(), coverBox(), infoSheetBox());
    }
  }

  async function load() {
    if (!DATA) panel.append(el('div', { class: 'muted small' }, T('carregando…', 'loading…')));
    try {
      // só-leitura (sede) usa a rota de LISTAGEM — a de admin é cortada p/ .cstaff na API
      DATA = await api((readOnly ? '/contest/doc?contest=' : '/contest/admin/docs?contest=') + enc(CONTEST));
      render();
    } catch (e) {
      panel.innerHTML = '';
      if (!bare) panel.append(el('h2', {}, T('📄 Documentos da prova', '📄 Contest documents')));
      panel.append(el('div', { class: 'error-box' }, e.message || T('falha ao carregar', 'failed to load')));
    }
  }
  return { panel, load };
}
