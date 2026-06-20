// shared/editor.js — editor de código embutido.
// Usa CodeMirror 6 via ESM (sem build). Se a rede/CDN falhar, cai para <textarea>
// automaticamente — a submissão funciona nos dois casos. Para self-host completo,
// baixe os módulos em web/shared/vendor/ e troque as URLs por caminhos locais.
// `cm` é o modo de realce (ver shared/languages.js); null/desconhecido = sem realce.

const CM = 'https://esm.sh/codemirror@6.0.1';
const LANG = {
  cpp:        () => import('https://esm.sh/@codemirror/lang-cpp@6.0.1').then(m => m.cpp()),
  python:     () => import('https://esm.sh/@codemirror/lang-python@6.1.6').then(m => m.python()),
  java:       () => import('https://esm.sh/@codemirror/lang-java@6.0.1').then(m => m.java()),
  rust:       () => import('https://esm.sh/@codemirror/lang-rust@6.0.1').then(m => m.rust()),
  go:         () => import('https://esm.sh/@codemirror/lang-go@6.0.1').then(m => m.go()),
  javascript: () => import('https://esm.sh/@codemirror/lang-javascript@6.2.2').then(m => m.javascript()),
};

export async function createEditor(parent, { doc = '', cm = 'cpp' } = {}) {
  try {
    const { EditorView, basicSetup } = await import(CM);
    const exts = [basicSetup];
    if (cm && LANG[cm]) { try { exts.push(await LANG[cm]()); } catch {} }
    const view = new EditorView({ doc, extensions: exts, parent });
    view.dom.classList.add('cm-mojeditor');
    return {
      kind: 'codemirror',
      getValue: () => view.state.doc.toString(),
      setValue: (v) => view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: v } }),
    };
  } catch (e) {
    const ta = document.createElement('textarea');
    ta.className = 'code-fallback';
    ta.value = doc; ta.spellcheck = false; ta.rows = 20;
    parent.appendChild(ta);
    return { kind: 'textarea', getValue: () => ta.value, setValue: (v) => { ta.value = v; } };
  }
}
