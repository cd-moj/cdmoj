// shared/editor-tab.js — o Tab nos editores de CÓDIGO (createEditor(…, { tab })), PR #37.
//   'indent'  — Tab indenta (4 espaços, o que os esqueletos de languages.js usam); com linhas
//               selecionadas indenta o bloco; Shift+Tab desindenta;
//   'literal' — Tab insere um TAB de verdade (editor de scripts/ em shell: receita de Makefile e
//               `<<-EOF` só funcionam com \t — 4 espaços davam CE em TODA submissão);
//   false     — o Tab do CodeMirror (move o foco). É o padrão: editores de markdown seguem navegando
//               o formulário.
// No CodeMirror entra por EditorView.domEventHandlers, e NÃO por listener no view.dom (a 1ª versão do
// PR): o handler só recebe eventos do CONTEÚDO (o painel de busca fica de fora — Tab lá trocava o
// trecho achado por espaços), roda DEPOIS do keymap (o Tab que navega os campos de snippet vence) e o
// próprio CM já cuida do Esc→Tab (tabFocusMode: sair do editor pelo teclado) e da composição (IME).
// O bundle vendorizado não exporta keymap/indentWithTab (receita p/ regerar: vendor/codemirror/README.md).

export const TAB_INDENT = '    ';

// tabEdit(doc, from, to, shift, mode) -> {from, to, insert, selFrom, selTo} — UMA troca de [from,to)
// por `insert` e a seleção depois dela. Pura (server/test/smoke-editor-tab.gjs.sh).
export function tabEdit(doc, from, to, shift, mode = 'indent') {
  const unit = mode === 'literal' ? '\t' : TAB_INDENT;
  if (from > to) [from, to] = [to, from];
  // cursor sem Shift: insere um nível onde está
  if (!shift && from === to) return { from, to, insert: unit, selFrom: from + unit.length, selTo: from + unit.length };
  // seleção (ou Shift): as linhas tocadas; seleção que termina no começo de uma linha não a leva junto
  const start = doc.lastIndexOf('\n', from - 1) + 1;
  const endPos = (to > from && doc[to - 1] === '\n') ? to - 1 : to;
  let end = doc.indexOf('\n', endPos); if (end < 0) end = doc.length;
  let removedFirst = 0;
  const insert = doc.slice(start, end).split('\n').map((l, i) => {
    if (!shift) return l.length ? unit + l : l;
    const m = /^(\t| {1,4})/.exec(l);
    if (!m) return l;
    if (i === 0) removedFirst = m[0].length;
    return l.slice(m[0].length);
  }).join('\n');
  if (from === to) {                     // Shift+Tab com cursor: o cursor anda junto com a linha
    const c = Math.max(start, from - removedFirst);
    return { from: start, to: end, insert, selFrom: c, selTo: c };
  }
  return { from: start, to: end, insert, selFrom: start, selTo: start + insert.length };
}

const MOD = (e) => e.ctrlKey || e.altKey || e.metaKey;

// a extensão do CodeMirror (EditorView vem do bundle, que este módulo não importa)
export function tabExtension(EditorView, mode) {
  return EditorView.domEventHandlers({
    keydown(e, view) {
      if (e.key !== 'Tab' || MOD(e) || e.isComposing) return false;
      const r = view.state.selection.main;
      const t = tabEdit(view.state.doc.toString(), r.from, r.to, e.shiftKey, mode);
      view.dispatch({ changes: { from: t.from, to: t.to, insert: t.insert },
        selection: { anchor: t.selFrom, head: t.selTo }, scrollIntoView: true, userEvent: 'input' });
      return true;                         // o CM chama preventDefault
    },
  });
}

// o <textarea> de emergência (bundle que não carrega): mesma regra, e Esc→Tab sai do campo (2 s,
// como o tabFocusMode do CM). execCommand('insertText') preserva o desfazer (Ctrl+Z).
export function attachTabTextarea(ta, mode) {
  let esc = 0;
  ta.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { esc = Date.now() + 2000; return; }
    if (e.key !== 'Tab') { if (!['Shift', 'Control', 'Alt', 'Meta', 'CapsLock'].includes(e.key)) esc = 0; return; }
    if (MOD(e) || e.isComposing) return;
    if (Date.now() <= esc) { esc = 0; return; }
    e.preventDefault();
    const t = tabEdit(ta.value, ta.selectionStart, ta.selectionEnd, e.shiftKey, mode);
    ta.setSelectionRange(t.from, t.to);
    const ok = typeof document.execCommand === 'function' && document.execCommand('insertText', false, t.insert);
    if (!ok) ta.setRangeText(t.insert, t.from, t.to, 'end');
    ta.setSelectionRange(t.selFrom, t.selTo);
  });
}
