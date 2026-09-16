#!/bin/bash
# smoke-statement-samples.gjs.sh — web/shared/statement-samples.js fora do browser (gjs):
#  • decorateSamples: 1 botão por bloco (h3+pre) dos .moj-exemplo, idempotente, ignora a nota;
#  • clique copia textContent + "\n" (writeText) e cai na seleção sem clipboard;
#  • samplesZip: o ZIP store-only ABRE no python (zipfile) com os nomes e bytes certos (o CRC é validado
#    pelo testzip). Sem gjs/python3: pula.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "statement-samples: gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
check(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (got '$1', want '$2')" >&2; fi; }
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=tag.toUpperCase(); this.nodeType=1; this.children=[]; this.attrs={}; this.dataset={}; this._ev={}; this._cls=new Set(); this._text=''; }
FakeNode.prototype.append=function(){ for (const k of arguments) { if (k==null||k==='') continue; const c = typeof k==='object'?k:{nodeType:3,text:String(k)}; c.parent=this; this.children.push(c); } };
FakeNode.prototype.setAttribute=function(k,v){ if(k==='class') this._cls=new Set(String(v).split(/\s+/).filter(Boolean)); this.attrs[k]=v; };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
FakeNode.prototype.click=function(){ for (const f of (this._ev.click||[])) f({preventDefault(){}, stopPropagation(){}}); };
FakeNode.prototype.remove=function(){ if (this.parent) this.parent.children=this.parent.children.filter(c=>c!==this); };
FakeNode.prototype._all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1){ o.push(c); o.push(...c._all()); } return o; };
FakeNode.prototype.querySelectorAll=function(sel){ const cls=sel.replace(/^\./,''); return this._all().filter(n=>n._cls.has(cls)); };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'classList',{get(){ const s=this._cls; return { contains:(c)=>s.has(c), toggle:(c,on)=>{ if(on===undefined) on=!s.has(c); on?s.add(c):s.delete(c); return on; }, add:(c)=>s.add(c), remove:(c)=>s.delete(c) }; }});
Object.defineProperty(FakeNode.prototype,'textContent',{ set(v){this._text=String(v); this.children=[];}, get(){ let t=this._text; for(const c of this.children) t+= c.nodeType===3?c.text:(c.textContent||''); return t; }});
Object.defineProperty(FakeNode.prototype,'nextElementSibling',{get(){ const k=this.parent?this.parent.children.filter(c=>c.nodeType===1):[]; return k[k.indexOf(this)+1]||null; }});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}), body:new FakeNode('body'), createRange:()=>({selectNodeContents(){}}) };
// no gjs `window` É o objeto global: getSelection tem de ser global
globalThis.SELECTED=0; globalThis.getSelection=()=>({ removeAllRanges(){}, addRange(){ globalThis.SELECTED++; } });
globalThis.COPIED=[]; globalThis.navigator={ clipboard:{ writeText: async (t)=>{ globalThis.COPIED.push(t); } } };
globalThis.setTimeout=(f)=>0; globalThis.URL={ createObjectURL:()=>'blob:x', revokeObjectURL(){} }; globalThis.Blob=function(parts){ this.parts=parts; };
function T(pt,en){ return pt; }
JS
  strip "$W/shared/dom.js"; strip "$W/shared/statement-samples.js"
  cat <<'JS'
// enunciado como o statement-langs.sh emite: 2 exemplos, o 1º com nota
const mk=(tag,cls,txt)=>{ const n=new FakeNode(tag); if(cls) n.setAttribute('class',cls); if(txt!=null) n.textContent=txt; return n; };
const root=mk('div','statement-content'); const sec=mk('section','moj-exemplos'); root.append(sec);
const ex1=mk('div','moj-exemplo'); ex1.append(mk('h3',null,'Entrada'), mk('pre',null,'3'), mk('h3',null,'Saída'), mk('pre',null,'3\n'));
const nota=mk('div','moj-exemplo-nota'); nota.append(mk('h3',null,'Explicação'), mk('p',null,'porque sim')); ex1.append(nota);
const ex2=mk('div','moj-exemplo'); ex2.append(mk('h3',null,'Entrada'), mk('pre',null,'7 8'), mk('h3',null,'Saída'), mk('pre',null,'15'));
sec.append(ex1, ex2);
const n1=decorateSamples(root), n2=decorateSamples(root);
const btns=root.querySelectorAll('sample-copy');
print('n1=' + n1 + ' n2=' + n2 + ' btns=' + btns.length + ' heads=' + root.querySelectorAll('sample-head').length);
(async () => {
  btns[0].click(); await Promise.resolve(); await Promise.resolve();
  print('copied0=' + JSON.stringify(COPIED[0]));
  btns[1].click(); await Promise.resolve(); await Promise.resolve();
  print('copied1=' + JSON.stringify(COPIED[1]));
  globalThis.navigator={}; btns[2].click(); await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
  print('fallback_selected=' + (globalThis.SELECTED||0) + ' label=' + btns[2].textContent);
  const zip = samplesZip([{name:'A/sample1.in', text:'3\n'}, {name:'A/sample1.out', text:'3\n'}, {name:'A/sample2.in', text:'7 8\n'}]);
  let hx=''; for (let i=0;i<zip.length;i++) hx+=zip[i].toString(16).padStart(2,'0');
  print('zip_hex=' + hx);
  print('dl=' + downloadSamplesZip([{name:'sample1',input:'3',output:'3\n'}], 'A', 'A-exemplos.zip'));
})().catch(e=>print('ERRO '+e+'\n'+e.stack));
JS
} > "$T/s.js"
out="$(timeout 60 gjs "$T/s.js" 2>&1)" || { echo "$out" >&2; echo "statement-samples: gjs falhou"; exit 1; }
grep -q '^ERRO' <<<"$out" && { echo "$out" >&2; exit 1; }
kv(){ sed -n "s/^.*\b$1=\([^ ]*\).*$/\1/p" <<<"$out" | head -1; }
check "$(kv n1)" 4 "4 botões (2 exemplos × entrada/saída); a nota não ganha botão"
check "$(kv n2)" 0 "2ª chamada é idempotente"
check "$(kv btns)" 4 "botões no DOM"
check "$(kv heads)" 4 "h3 marcados"
check "$(sed -n 's/^copied0=\(.*\)$/\1/p' <<<"$out")" '"3\n"' "copia com a quebra final reposta"
check "$(sed -n 's/^copied1=\(.*\)$/\1/p' <<<"$out")" '"3\n"' "não duplica a quebra quando já existe"
check "$(kv fallback_selected)" 1 "sem clipboard: seleciona o bloco"
check "$(kv dl)" 1 "downloadSamplesZip devolve o nº de exemplos"
if command -v python3 >/dev/null 2>&1; then
  sed -n 's/^zip_hex=//p' <<<"$out" | xxd -r -p > "$T/a.zip"
  res="$(python3 - "$T/a.zip" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); bad = z.testzip()
print('names=' + ','.join(z.namelist()) + ' bad=' + str(bad) + ' s2=' + repr(z.read('A/sample2.in').decode()))
PY
)"
  check "$(sed -n 's/^names=\([^ ]*\).*$/\1/p' <<<"$res")" "A/sample1.in,A/sample1.out,A/sample2.in" "zip abre no python com os 3 nomes"
  check "$(sed -n 's/^.* bad=\([^ ]*\).*$/\1/p' <<<"$res")" None "CRCs válidos (testzip)"
  check "$(sed -n "s/^.* s2=\(.*\)$/\1/p" <<<"$res")" "'7 8\\n'" "bytes do sample2 exatos"
fi
echo "statement-samples: $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
