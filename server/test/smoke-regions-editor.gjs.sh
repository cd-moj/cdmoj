#!/bin/bash
# smoke-regions-editor.gjs.sh — o editor de sedes (web/shared/contest-config/regions.js) NUNCA perde dados.
# O editor antigo devolvia, no modo simples, só {name,regex} dos nós COM regex: salvar apagava subregions,
# recortes `view` e sedes sem regex (árvore da Maratona virava lista plana; a de zz-virtual-demo sumia), e
# JSON avançado inválido caía calado na lista. Afirma:
#   • árvore que a lista não representa abre no JSON (lista bloqueada) e volta IDÊNTICA no getValue;
#   • na lista simples, sede SEM regex é mantida (casa pela sede gravada no time);
#   • JSON inválido: validate() diz o erro e getValue() devolve a última árvore válida (nunca [] nem lança);
#   • voltar do JSON p/ a lista com uma árvore que não cabe é recusado.
set -u
command -v gjs >/dev/null 2>&1 || { echo "regions-editor: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function N(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._ev={}; this.parentNode=null; this._text=''; }
N.prototype.append=function(){ for (const k of arguments) { if (k && typeof k==='object') { k.parentNode=this; this.children.push(k); } else if (k!=null) this.children.push({nodeType:3,text:String(k)}); } };
N.prototype.appendChild=function(k){ this.append(k); return k; };
N.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
N.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
N.prototype.fire=function(t){ for (const f of (this._ev[t]||[])) f({target:this, preventDefault(){}}); };
N.prototype.all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1) { o.push(c); o.push(...c.all()); } return o; };
Object.defineProperty(N.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(N.prototype,'innerHTML',{set(v){this.children=[]},get(){return ''}});
Object.defineProperty(N.prototype,'textContent',{set(v){this._text=String(v);this.children=[]},
  get(){ let t=this._text; for (const c of this.children) t+= c.nodeType===3 ? c.text : c.textContent; return t; }});
Object.defineProperty(N.prototype,'value',{set(v){this._v=String(v)},get(){ return this._v!==undefined ? this._v : (this.attrs.value||''); }});
globalThis.document={ createElement:(t)=>new N(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}) };
function T(pt){ return pt; }
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/shared/contest-config/regions.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const J=(x)=>JSON.stringify(x);
const shown=(n)=>n.style.display!=='none';
const find=(ed,tag,pred)=>ed.el.all().filter(n=>n.tagName===tag && (!pred || pred(n)));
// 1) árvore da Maratona (subregions + view + nó sem regex): abre no JSON, volta idêntica
const TREE=[{name:'Brasil',regex:'^br-',subregions:[{name:'DF',regex:'^br-df-'},{name:'GO'}]},{name:'Femininos',view:true,subregions:[{name:'F3',regex:'^f3'}]}];
const e1=makeRegionsEditor({initial:TREE});
const ta=find(e1,'textarea')[0];
ck('árvore que a lista não representa abre no JSON', shown(ta) && ta.value.includes('subregions'));
ck('aviso de lista bloqueada visível', e1.el.textContent.includes('só é editada no JSON'));
ck('getValue devolve a árvore IDÊNTICA', J(e1.getValue())===J(TREE), J(e1.getValue()));
ck('validate ok', e1.validate()==='');
// voltar p/ a lista com a árvore → recusado, segue no JSON
const tog=find(e1,'a')[0]; tog.fire('click');
ck('voltar p/ a lista com árvore que não cabe: recusado', shown(ta) && e1.el.textContent.includes('não cabe na lista simples'));
// JSON inválido: validate aponta, getValue devolve a última válida
ta.value='[{"name": "Brasil",';
ck('JSON inválido: validate diz o erro', /inválido/.test(e1.validate()));
ck('JSON inválido: getValue devolve a última árvore válida (nunca [])', J(e1.getValue())===J(TREE));
ta.value='{"name":"x"}';
ck('JSON que não é lista: validate recusa', /lista/.test(e1.validate()));
ta.value='[{"regex":"^a"}]';
ck('nó sem name: validate recusa', /sem "name"/.test(e1.validate()));
// 2) lista simples: sede SEM regex é mantida
const e2=makeRegionsEditor({initial:[{name:'DF',regex:'^df'},{name:'GO'}]});
ck('lista simples abre na lista (sem JSON)', !shown(find(e2,'textarea')[0]));
ck('sede sem regex mantida no getValue', J(e2.getValue())===J([{name:'DF',regex:'^df'},{name:'GO'}]), J(e2.getValue()));
// linha totalmente vazia some; regex sem nome ganha o nome da regex (compat)
const e3=makeRegionsEditor({initial:[{name:'',regex:''},{name:'',regex:'^x'}]});
ck('linha vazia some; regex sem nome usa a regex como nome', J(e3.getValue())===J([{name:'^x',regex:'^x'}]), J(e3.getValue()));
// 3) ida e volta lista → JSON → lista sem perda
const e4=makeRegionsEditor({initial:[{name:'A',regex:'^a'}]});
const t4=find(e4,'a')[0]; t4.fire('click');
const ta4=find(e4,'textarea')[0];
ck('lista → JSON mostra a lista', shown(ta4) && JSON.parse(ta4.value)[0].name==='A');
ta4.value='[{"name":"A","regex":"^a"},{"name":"B"}]'; t4.fire('click');
ck('JSON (que cabe) → lista: volta com a sede nova', !shown(ta4) && J(e4.getValue())===J([{name:'A',regex:'^a'},{name:'B'}]), J(e4.getValue()));
print(''); print('RESULT: '+pass+' passed, '+fail+' failed'); if (fail) imports.system.exit(1);
EOF
} > "$JS"
gjs "$JS"
