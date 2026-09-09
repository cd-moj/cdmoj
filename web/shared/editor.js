// shared/editor.js — editor de código/texto embutido.
// Usa CodeMirror 6 VENDORIZADO (bundle ESM local em shared/vendor/codemirror/ — nada de
// CDN: contest roda em LAN isolada). Se o bundle falhar, cai para <textarea>
// automaticamente. `cm` é o modo de realce (ver shared/languages.js; 'markdown' p/ enunciados).
// Opção `images:true` habilita colar/arrastar imagem -> embute no texto como ![](data:...)
// (downscale via canvas), resolvendo a gestão de imagens de forma transparente.

const CM = '/shared/vendor/codemirror/cm-bundle.js';
// modo "legacy" (StreamLanguage): linguagens sem pacote dedicado do CodeMirror 6.
// O bundle re-exporta os modos pelo NOME do export original (csharp, haskell, oCaml, …).
const legacy = (name) => import(CM).then(m => m.StreamLanguage.define(m[name]));
// realce mínimo de Prolog (não há modo pronto): comentários %, :-/?-, variáveis, átomos, strings.
const PROLOG = {
  startState: () => ({}),
  token(stream) {
    if (stream.eatSpace()) return null;
    if (stream.match(/%.*/)) return 'comment';
    if (stream.match(/\/\*/)) { stream.match(/[^*]*\*+([^/*][^*]*\*+)*\//) || stream.skipToEnd(); return 'comment'; }
    if (stream.match(/:-|\?-|-->|\\\+|=\.\.|==|\\==|@[<>]=?|\bis\b/)) return 'operator';
    if (stream.match(/"(?:[^"\\]|\\.)*"/) || stream.match(/'(?:[^'\\]|\\.)*'/)) return 'string';
    if (stream.match(/\d+(\.\d+)?/)) return 'number';
    if (stream.match(/[A-Z_][A-Za-z0-9_]*/)) return 'variable-2';   // variáveis
    if (stream.match(/[a-z][A-Za-z0-9_]*/)) return 'atom';          // átomos / predicados
    stream.next(); return null;
  },
};
const LANG = {
  cpp:        () => import(CM).then(m => m.cpp()),
  python:     () => import(CM).then(m => m.python()),
  java:       () => import(CM).then(m => m.java()),
  rust:       () => import(CM).then(m => m.rust()),
  go:         () => import(CM).then(m => m.go()),
  javascript: () => import(CM).then(m => m.javascript()),
  markdown:   () => import(CM).then(m => m.markdown()),
  // linguagens aceitas sem pacote dedicado -> modos legacy (StreamLanguage):
  csharp:     () => legacy('csharp'),   // C#
  kotlin:     () => legacy('kotlin'),   // Kotlin (modo clike legacy)
  haskell:    () => legacy('haskell'),  // Haskell
  ocaml:      () => legacy('oCaml'),    // OCaml
  pascal:     () => legacy('pascal'),   // Pascal
  shell:      () => legacy('shell'),    // sh / bash
  apl:        () => legacy('apl'),      // APL
  gas:        () => legacy('gas'),      // assembly (MIPS/spim, RISC-V/rars)
  prolog:     () => import(CM).then(m => m.StreamLanguage.define(PROLOG)),
};

// imagem -> markdown ![](data:...), com downscale se larga demais (mantém o .md leve)
async function imageToMarkdown(file, maxW = 1100) {
  const dataUri = await new Promise((res, rej) => {
    const r = new FileReader(); r.onload = () => res(r.result); r.onerror = rej; r.readAsDataURL(file);
  });
  try {
    const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = dataUri; });
    if (img.width > maxW) {
      const c = document.createElement('canvas');
      c.width = maxW; c.height = Math.round(img.height * (maxW / img.width));
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      return '![imagem](' + c.toDataURL('image/png') + ')';
    }
  } catch { /* usa o dataUri original */ }
  return '![imagem](' + dataUri + ')';
}
function attachImages(dom, insert) {
  dom.addEventListener('paste', async (e) => {
    const it = [...(e.clipboardData?.items || [])].find(i => i.type.startsWith('image/'));
    if (!it) return;
    e.preventDefault(); insert('\n' + await imageToMarkdown(it.getAsFile()) + '\n');
  });
  dom.addEventListener('drop', async (e) => {
    const f = [...(e.dataTransfer?.files || [])].find(x => x.type.startsWith('image/'));
    if (!f) return;
    e.preventDefault(); insert('\n' + await imageToMarkdown(f) + '\n');
  });
}

// Tab INDENTA em vez de mudar o foco. O CodeMirror 6 não liga isto por padrão, de
// propósito: quem navega por teclado precisa do Tab para conseguir sair do editor.
// A saída de emergência é a convenção do próprio CM — ESC e depois TAB move o foco.
//
// Feito por listener de DOM, e não pelo `keymap.of([indentWithTab])` que seria o
// caminho normal, porque o bundle vendorizado (shared/vendor/codemirror/cm-bundle.js)
// exporta só EditorView/basicSetup/modos: não exporta `keymap` nem `indentWithTab`
// (o identificador nem aparece no bundle). Trocar isso exigiria regerar o bundle,
// que é construído fora deste repositório.
const NB_INDENT = '    ';   // 4 espaços, igual ao que os esqueletos de languages.js usam

function attachTabIndent(view) {
  let escaped = false;
  view.dom.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { escaped = true; return; }
    if (e.key !== 'Tab') { escaped = false; return; }
    if (escaped) { escaped = false; return; }      // ESC+TAB: deixa sair do editor
    e.preventDefault();
    const st = view.state;
    const r = st.selection.main;
    const l1 = st.doc.lineAt(r.from);
    const l2 = st.doc.lineAt(r.to);
    // cursor ou seleção dentro de UMA linha, sem shift: insere um nível
    if (!e.shiftKey && l1.number === l2.number) {
      view.dispatch(st.replaceSelection(NB_INDENT));
      return;
    }
    // bloco de linhas (ou shift): indenta / desindenta cada linha
    const changes = [];
    for (let n = l1.number; n <= l2.number; n++) {
      const line = st.doc.line(n);
      if (e.shiftKey) {
        const m = /^(\t| {1,4})/.exec(line.text);
        if (m) changes.push({ from: line.from, to: line.from + m[0].length });
      } else if (line.length) {
        changes.push({ from: line.from, insert: NB_INDENT });
      }
    }
    if (changes.length) view.dispatch({ changes });
  });
}

// mesma coisa para o <textarea> de emergência (quando o bundle não carrega)
function attachTabIndentTextarea(ta) {
  let escaped = false;
  ta.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { escaped = true; return; }
    if (e.key !== 'Tab') { escaped = false; return; }
    if (escaped) { escaped = false; return; }
    e.preventDefault();
    const s = ta.selectionStart, t = ta.selectionEnd, v = ta.value;
    if (!e.shiftKey && !v.slice(s, t).includes('\n')) {
      ta.value = v.slice(0, s) + NB_INDENT + v.slice(t);
      ta.selectionStart = ta.selectionEnd = s + NB_INDENT.length;
      return;
    }
    const ini = v.lastIndexOf('\n', s - 1) + 1;
    const fim = v.indexOf('\n', t) === -1 ? v.length : v.indexOf('\n', t);
    const bloco = v.slice(ini, fim).split('\n').map((l) => (
      e.shiftKey ? l.replace(/^(\t| {1,4})/, '') : (l.length ? NB_INDENT + l : l)
    )).join('\n');
    ta.value = v.slice(0, ini) + bloco + v.slice(fim);
    ta.selectionStart = ini; ta.selectionEnd = ini + bloco.length;
  });
}

export async function createEditor(parent, { doc = '', cm = 'cpp', images = false } = {}) {
  try {
    const { EditorView, basicSetup } = await import(CM);
    let langExt = null;
    if (cm && LANG[cm]) { try { langExt = await LANG[cm](); } catch { langExt = null; } }
    let view;
    try {
      view = new EditorView({ doc, extensions: langExt ? [basicSetup, langExt] : [basicSetup], parent });
    } catch {
      // extensão de linguagem incompatível -> CM puro (sem realce), sem cair p/ <textarea>
      view = new EditorView({ doc, extensions: [basicSetup], parent });
    }
    view.dom.classList.add('cm-mojeditor');
    attachTabIndent(view);
    const insert = (text) => { view.dispatch(view.state.replaceSelection(text)); view.focus(); };
    if (images) attachImages(view.dom, insert);
    return {
      kind: 'codemirror',
      getValue: () => view.state.doc.toString(),
      setValue: (v) => view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: v } }),
      insert,
      focus: () => view.focus(),
    };
  } catch (e) {
    const ta = document.createElement('textarea');
    ta.className = 'code-fallback'; ta.value = doc; ta.spellcheck = false; ta.rows = 20;
    attachTabIndentTextarea(ta);
    parent.appendChild(ta);
    const insert = (text) => {
      const s = ta.selectionStart ?? ta.value.length, en = ta.selectionEnd ?? ta.value.length;
      ta.value = ta.value.slice(0, s) + text + ta.value.slice(en);
      ta.selectionStart = ta.selectionEnd = s + text.length; ta.focus();
    };
    if (images) attachImages(ta, insert);
    return { kind: 'textarea', getValue: () => ta.value, setValue: (v) => { ta.value = v; }, insert, focus: () => ta.focus() };
  }
}
