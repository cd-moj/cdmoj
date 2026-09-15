#!/bin/bash
# smoke-statement-chips.gjs.sh — os chips de idioma do enunciado (web/shared/statement-langs.js)
# VOLTAM ao idioma de partida. O clique decide "já está ativo?" pelo DOM, não pelo parâmetro
# inicial: comparar com `cur` congelado matava o chip do idioma inicial depois de qualquer troca
# (PT→ES→EN funcionava; voltar a PT não — relato do Ribas, 15/09/2026). Roda o módulo fora do
# browser com o gjs (DOM falso mínimo com classList + eventos). Sem gjs: pula (rc 0).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "statement-chips: gjs ausente — pulando"; exit 0; }
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
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'classList',{get(){ const s=this._cls; return { contains:(c)=>s.has(c), toggle:(c,on)=>{ if(on===undefined) on=!s.has(c); on?s.add(c):s.delete(c); return on; }, add:(c)=>s.add(c), remove:(c)=>s.delete(c) }; }});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}) };
globalThis.localStorage={ _m:{}, getItem(k){ return k in this._m ? this._m[k] : null; }, setItem(k,v){ this._m[k]=String(v); } };
globalThis.location={search:''}; globalThis.URLSearchParams=class{ constructor(){} get(){ return null; } };
function T(pt,en){ return pt; } function getLang(){ return 'pt'; }
JS
  strip "$W/shared/dom.js"; strip "$W/shared/statement-langs.js"
  cat <<'JS'
// o padrão das telas (problema.js): o callback lembra, marca o ativo e mostra
let cur = pickStmtLang(['pt','en','es'], 'pt'); const seen=[cur];
const chips = makeStmtLangChips(['pt','en','es'], cur, (l) => { cur = l; rememberStmtLang(l); setChipsActive(chips, l); seen.push(l); });
const chip = (l) => chips.querySelectorAll('.stmt-chip').find((b) => b.dataset.lang === l);
const active = () => chips.querySelectorAll('.stmt-chip').filter((b) => b.classList.contains('active')).map((b)=>b.dataset.lang).join(',');
print('start=' + cur + ' active0=' + active());
chip('es').click(); print('after_es=' + cur + ' active_es=' + active());
chip('en').click(); print('after_en=' + cur + ' active_en=' + active());
chip('pt').click(); print('after_pt=' + cur + ' active_pt=' + active());
chip('pt').click(); print('repeat_pt=' + seen.join('>'));
print('remembered=' + localStorage.getItem('moj_stmt_lang'));
print('chips_pt_only=' + makeStmtLangChips(['pt'], 'pt', ()=>{}).children.length);
JS
} > "$T/chips.js"
out="$(gjs "$T/chips.js" 2>&1)" || { echo "$out" >&2; echo "statement-chips: gjs falhou"; exit 1; }
kv(){ sed -n "s/^.*\b$1=\([^ ]*\).*$/\1/p" <<<"$out" | head -1; }
check "$(kv start)" pt "começa em PT (default)"
check "$(kv active0)" pt "chip PT ativo no início"
check "$(kv after_es)" es "PT→ES troca"
check "$(kv active_es)" es "só o ES fica ativo"
check "$(kv after_en)" en "ES→EN troca"
check "$(kv after_pt)" pt "EN→PT VOLTA ao idioma de partida"
check "$(kv active_pt)" pt "chip PT ativo de novo"
check "$(kv repeat_pt)" "pt>es>en>pt" "clicar no ativo não dispara de novo"
check "$(kv remembered)" pt "última escolha lembrada no localStorage"
check "$(kv chips_pt_only)" 0 "um idioma só = sem chips"
echo "statement-chips: $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
