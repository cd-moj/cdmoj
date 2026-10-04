#!/bin/bash
# smoke-problem-titles.gjs.sh — os chips de TÍTULO do problema (web/shared/problem-titles.js, 03/10/2026): o nome do
# problema no contest é um só; quando o problema tem título em mais de um idioma, os chips PT·EN·ES preenchem o
# campo com o título daquele idioma. `autoTitle` é o gêmeo da regra do servidor (cc_prob_title: o título no idioma
# da prova, senão o PT). Roda o módulo fora do browser com o gjs (DOM falso mínimo). Sem gjs: pula (rc 0).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "problem-titles: gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
check(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (got '$1', want '$2')" >&2; fi; }
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.dataset={}; this._ev={}; this._cls=new Set(); }
FakeNode.prototype.append=function(){ for (const k of arguments) this.children.push(typeof k==='object'?k:{nodeType:3,text:String(k)}); };
FakeNode.prototype.setAttribute=function(k,v){ if(k==='class'){ this._cls=new Set(String(v).split(/\s+/).filter(Boolean)); } this.attrs[k]=v; };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
FakeNode.prototype.click=function(){ for (const f of (this._ev.click||[])) f({}); };
FakeNode.prototype._all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1){ o.push(c); o.push(...c._all()); } return o; };
FakeNode.prototype.querySelectorAll=function(sel){ const cls=sel.replace(/^\./,''); return this._all().filter(n=>n._cls.has(cls)); };
FakeNode.prototype.text=function(){ return this.children.map(c=>c.nodeType===1?c.text():c.text).join(''); };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'classList',{get(){ const s=this._cls; return { contains:(c)=>s.has(c), toggle:(c,on)=>{ if(on===undefined) on=!s.has(c); on?s.add(c):s.delete(c); return on; }, add:(c)=>s.add(c), remove:(c)=>s.delete(c) }; }});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}) };
globalThis.localStorage={ _m:{}, getItem(k){ return k in this._m ? this._m[k] : null; }, setItem(k,v){ this._m[k]=String(v); } };
globalThis.location={search:''}; globalThis.URLSearchParams=class{ constructor(){} get(){ return null; } };
function T(pt,en){ return pt; } function getLang(){ return 'pt'; }
JS
  strip "$W/shared/dom.js"; strip "$W/shared/statement-langs.js"; strip "$W/shared/problem-titles.js"
  cat <<'JS'
const tri = {pt:'Corrida de Robôs', en:'Robot Race', es:'Carrera de Robots'};
print('opts=' + titleOptions({es:'B', pt:'A', xx:'Z', en:''}).map(([l,v])=>l+':'+v).join(','));
print('choice_tri=' + hasTitleChoice(tri) + ' choice_same=' + hasTitleChoice({pt:'Pizza', en:'Pizza'}) + ' choice_none=' + hasTitleChoice(undefined));
print('auto_es=' + autoTitle(tri,'es','x').replace(/ /g,'_') + ' auto_noES=' + autoTitle({pt:'Pontes', en:'Bridges'},'es','x')
  + ' auto_none=' + autoTitle(undefined,'en','org#id'));
// o padrão das telas: o campo de nome + os chips; o clique preenche, digitar o título de um idioma marca o chip
const field = { value: '' };
const chips = makeTitleChips(tri, () => field.value, (v) => { field.value = v; });
const chip = (l) => chips.querySelectorAll('.stmt-chip').find((b) => b.dataset.lang === l);
const active = () => chips.querySelectorAll('.stmt-chip').filter((b) => b.classList.contains('active')).map((b)=>b.dataset.lang).join(',') || '-';
print('n=' + chips.querySelectorAll('.stmt-chip').length + ' active0=' + active());
chip('es').click(); print('field_es=' + field.value.replace(/ /g,'_') + ' active_es=' + active());
chip('pt').click(); print('field_pt=' + field.value.replace(/ /g,'_') + ' active_pt=' + active());
field.value = 'Robot Race'; chips.repaint(); print('typed_en=' + active());
field.value = 'Outro'; chips.repaint(); print('typed_custom=' + active());
print('nochips_same=' + makeTitleChips({pt:'Pizza', en:'Pizza'}, ()=>'', ()=>{}).children.length
  + ' nochips_none=' + makeTitleChips(undefined, ()=>'', ()=>{}).children.length);
const line = titlesLine(tri); print('line=' + (line && line.text ? line.text().replace(/ /g,'_') : 'vazio'));
print('line_none=' + (titlesLine({pt:'Soma'}) === '' ? 'vazio' : 'algo'));
JS
} > "$T/t.js"
out="$(gjs "$T/t.js" 2>&1)" || { echo "$out" >&2; echo "problem-titles: gjs falhou"; exit 1; }
kv(){ sed -n "s/^.*\b$1=\([^ ]*\).*$/\1/p" <<<"$out" | head -1; }
check "$(kv opts)" "pt:A,es:B" "opções na ordem pt·en·es, só idiomas válidos e não vazios"
check "$(kv choice_tri)" true "três títulos distintos = há escolha"
check "$(kv choice_same)" false "tradução com o MESMO título = sem escolha"
check "$(kv choice_none)" false "sem titles = sem escolha"
check "$(kv auto_es)" "Carrera_de_Robots" "automático no idioma da prova (gêmeo do cc_prob_title)"
check "$(kv auto_noES)" "Pontes" "sem título no idioma da prova = o PT"
check "$(kv auto_none)" "org#id" "sem títulos = o fallback"
check "$(kv n)" 3 "um chip por idioma"
check "$(kv active0)" "-" "campo vazio: nenhum chip ativo"
check "$(kv field_es)" "Carrera_de_Robots" "chip ES preenche o nome"
check "$(kv active_es)" es "…e fica ativo"
check "$(kv field_pt)" "Corrida_de_Robôs" "chip PT troca o nome"
check "$(kv active_pt)" pt "…e só ele fica ativo"
check "$(kv typed_en)" en "digitar o título EN marca o chip EN (repaint)"
check "$(kv typed_custom)" "-" "nome próprio: nenhum chip ativo"
check "$(kv nochips_same)" 0 "títulos iguais: sem chips"
check "$(kv nochips_none)" 0 "sem titles: sem chips"
check "$(kv line)" "🌐_PT_Corrida_de_Robôs_·_EN_Robot_Race_·_ES_Carrera_de_Robots" "linha da lista do banco"
check "$(kv line_none)" vazio "um título só: sem linha"
echo "problem-titles: $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
