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
