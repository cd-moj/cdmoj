// shared/editor.js — editor de código/texto embutido.
// Usa CodeMirror 6 via ESM (sem build). Se a rede/CDN falhar, cai para <textarea>
// automaticamente. `cm` é o modo de realce (ver shared/languages.js; 'markdown' p/ enunciados).
// Opção `images:true` habilita colar/arrastar imagem -> embute no texto como ![](data:...)
// (downscale via canvas), resolvendo a gestão de imagens de forma transparente.

const CM = 'https://esm.sh/codemirror@6.0.1';
const LANG = {
  cpp:        () => import('https://esm.sh/@codemirror/lang-cpp@6.0.1').then(m => m.cpp()),
  python:     () => import('https://esm.sh/@codemirror/lang-python@6.1.6').then(m => m.python()),
  java:       () => import('https://esm.sh/@codemirror/lang-java@6.0.1').then(m => m.java()),
  rust:       () => import('https://esm.sh/@codemirror/lang-rust@6.0.1').then(m => m.rust()),
  go:         () => import('https://esm.sh/@codemirror/lang-go@6.0.1').then(m => m.go()),
  javascript: () => import('https://esm.sh/@codemirror/lang-javascript@6.2.2').then(m => m.javascript()),
  markdown:   () => import('https://esm.sh/@codemirror/lang-markdown@6.2.5').then(m => m.markdown()),
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
    const exts = [basicSetup];
    if (cm && LANG[cm]) { try { exts.push(await LANG[cm]()); } catch {} }
    const view = new EditorView({ doc, extensions: exts, parent });
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
