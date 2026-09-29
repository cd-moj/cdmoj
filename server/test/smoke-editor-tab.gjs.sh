#!/bin/bash
# smoke-editor-tab.gjs.sh — o Tab dos editores de código (web/shared/editor-tab.js, PR #37):
#   • tabEdit (pura): cursor insere um nível; seleção indenta as LINHAS (sem apagar o selecionado);
#     linha vazia fica vazia; seleção que termina no começo de linha não leva a seguinte; Shift+Tab
#     desindenta (TAB ou até 4 espaços) e o cursor anda junto; modo 'literal' usa \t (Makefile/<<-EOF);
#   • a extensão do CodeMirror: só Tab puro (Ctrl/Alt/Meta e composição passam adiante), UMA troca
#     por Tab, seleção nova aplicada — e ela é um domEventHandlers (só o CONTEÚDO; a busca fica de fora);
#   • o <textarea> de emergência: mesma regra, e Esc→Tab SAI do campo (Shift no meio não desarma).
set -u
command -v gjs >/dev/null 2>&1 || { echo "editor-tab: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ echo 'const document = {};'
  strip "$WEB/shared/editor-tab.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const J=(x)=>JSON.stringify(x);
const apply=(doc,t)=>doc.slice(0,t.from)+t.insert+doc.slice(t.to);
// ---- tabEdit
let d='abc', t=tabEdit(d,2,2,false);
ck('cursor: insere 4 espaços e o cursor anda', apply(d,t)==='ab    c' && t.selFrom===6 && t.selTo===6, J(t));
t=tabEdit(d,2,2,false,'literal');
ck("modo 'literal': insere um TAB de verdade", apply(d,t)==='ab\tc' && t.selFrom===3);
d='  x = 1\ny'; t=tabEdit(d,2,3,false);
ck('seleção DENTRO de uma linha indenta a linha (não apaga o selecionado)', apply(d,t)==='      x = 1\ny', J(apply(d,t)));
d='a\nb\n\nc'; t=tabEdit(d,0,d.length,false);
ck('bloco: cada linha ganha um nível; linha vazia fica vazia; seleção = o bloco', apply(d,t)==='    a\n    b\n\n    c' && t.selFrom===0 && t.selTo===t.insert.length, J(apply(d,t)));
d='a\nb\nc'; t=tabEdit(d,0,2,false);
ck('seleção que termina no começo da linha seguinte não a leva junto', apply(d,t)==='    a\nb\nc', J(apply(d,t)));
d='    a\n\tb\n  c\nd'; t=tabEdit(d,0,d.length,true);
ck('Shift+Tab no bloco: tira UM nível (TAB ou até 4 espaços)', apply(d,t)==='a\nb\nc\nd', J(apply(d,t)));
d='    abc'; t=tabEdit(d,6,6,true);
ck('Shift+Tab com cursor: desindenta a linha e o cursor anda junto', apply(d,t)==='abc' && t.selFrom===2, J(t));
d='  x'; t=tabEdit(d,1,1,true);
ck('…sem passar do começo da linha', apply(d,t)==='x' && t.selFrom===0, J(t));
d='\t\tx'; t=tabEdit(d,3,3,true,'literal');
ck("Shift+Tab no 'literal' tira um \\t", apply(d,t)==='\tx');
d='abc'; t=tabEdit(d,3,0,false);
ck('seleção invertida (from > to) é normalizada', apply(d,t)==='    abc');
// ---- extensão do CodeMirror (EditorView falso: domEventHandlers devolve o objeto de handlers)
const EV={ domEventHandlers:(h)=>({__dom:h}) };
const ext=tabExtension(EV,'indent');
ck('é um domEventHandlers (só o CONTEÚDO recebe — o painel de busca fica de fora)', !!(ext.__dom && ext.__dom.keydown));
function fakeView(doc,from,to){ const v={doc, sel:[from,to], n:0,
  get state(){ const self=this; return { doc:{ toString:()=>self.doc }, selection:{ main:{ from:self.sel[0], to:self.sel[1] } } }; },
  dispatch(tr){ this.n++; const c=tr.changes; this.doc=this.doc.slice(0,c.from)+c.insert+this.doc.slice(c.to); this.sel=[tr.selection.anchor,tr.selection.head]; } }; return v; }
const K=(o)=>Object.assign({key:'Tab',shiftKey:false,ctrlKey:false,altKey:false,metaKey:false,isComposing:false},o);
let v=fakeView('int x;',0,0);
ck('Tab: trata (true = o CM dá preventDefault) com UMA troca', ext.__dom.keydown(K({}),v)===true && v.n===1 && v.doc==='    int x;' && v.sel[0]===4);
v=fakeView('a',0,0);
ck('Ctrl+Tab / Alt+Tab / Meta+Tab passam adiante', ext.__dom.keydown(K({ctrlKey:true}),v)===false && ext.__dom.keydown(K({altKey:true}),v)===false && ext.__dom.keydown(K({metaKey:true}),v)===false && v.n===0);
ck('composição (IME) passa adiante', ext.__dom.keydown(K({isComposing:true}),v)===false && v.n===0);
ck('outra tecla passa adiante', ext.__dom.keydown(K({key:'a'}),v)===false);
// ---- textarea de emergência (sem execCommand: cai no setRangeText)
function fakeTA(value,s,e){ const ta={value, selectionStart:s, selectionEnd:e, h:null,
  addEventListener(tp,f){ if (tp==='keydown') this.h=f; },
  setSelectionRange(a,b){ this.selectionStart=a; this.selectionEnd=b; },
  setRangeText(ins,a,b){ this.value=this.value.slice(0,a)+ins+this.value.slice(b); } }; return ta; }
const ev=(o)=>{ const e=K(o); e.prevented=false; e.preventDefault=()=>{ e.prevented=true; }; return e; };
let ta=fakeTA('abc',1,1); attachTabTextarea(ta,'indent');
let e=ev({}); ta.h(e);
ck('textarea: Tab indenta', e.prevented && ta.value==='a    bc' && ta.selectionStart===5, J(ta.value));
ta=fakeTA('abc',0,0); attachTabTextarea(ta,'indent');
ta.h(ev({key:'Escape'})); ta.h(ev({key:'Shift'})); e=ev({shiftKey:true}); ta.h(e);
ck('textarea: Esc (+Shift) e depois Tab SAI do campo (não trata)', !e.prevented && ta.value==='abc');
ta.h(ev({key:'Escape'})); ta.h(ev({key:'x'})); e=ev({}); ta.h(e);
ck('textarea: outra tecla entre o Esc e o Tab desarma a saída', e.prevented && ta.value==='    abc');
ta=fakeTA('l1\nl2',0,5); attachTabTextarea(ta,'literal'); e=ev({}); ta.h(e);
ck("textarea 'literal': bloco ganha \\t", ta.value==='\tl1\n\tl2', J(ta.value));
print(''); print('RESULT: '+pass+' passed, '+fail+' failed'); imports.system.exit(fail>0?1:0);
EOF
} > "$JS"
gjs "$JS"
