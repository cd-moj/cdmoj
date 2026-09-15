#!/bin/bash
# smoke-lang-toggle.gjs.sh — os botões PT · EN (web/shared/lang-toggle.js) em página estática:
# clicar troca o LANG (setLang persist), reaplica o i18n-dom (data-en ⇄ PT capturado, reversível),
# grava em localStorage e carimba ?lang= na URL (o link copiado carrega o idioma e o reload não
# desfaz o clique). Roda o módulo real fora do browser com o gjs. Sem gjs: pula (rc 0).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "lang-toggle: gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
check(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (got '$1', want '$2')" >&2; fi; }
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.dataset={}; this._ev={}; this._cls=new Set(); this._text=''; }
FakeNode.prototype.append=function(){ for (const k of arguments) this.children.push(typeof k==='object'?k:{nodeType:3,text:String(k)}); };
FakeNode.prototype.setAttribute=function(k,v){ if(k==='class') this._cls=new Set(String(v).split(/\s+/).filter(Boolean)); this.attrs[k]=v; };
FakeNode.prototype.getAttribute=function(k){ return k in this.attrs ? this.attrs[k] : null; };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
FakeNode.prototype.click=function(){ for (const f of (this._ev.click||[])) f({}); };
FakeNode.prototype._all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1){ o.push(c); o.push(...c._all()); } return o; };
FakeNode.prototype.querySelectorAll=function(sel){ const m=sel.match(/^\[([a-z-]+)\]$/); if (m) return this._all().filter(n=>m[1] in n.attrs); const cls=sel.replace(/^\./,''); return this._all().filter(n=>n._cls.has(cls)); };
FakeNode.prototype.querySelector=function(sel){ return this.querySelectorAll(sel)[0]||null; };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'classList',{get(){ const s=this._cls; return { contains:(c)=>s.has(c), toggle:(c,on)=>{ if(on===undefined) on=!s.has(c); on?s.add(c):s.delete(c); return on; }, add:(c)=>s.add(c), remove:(c)=>s.delete(c) }; }});
Object.defineProperty(FakeNode.prototype,'textContent',{ set(v){this._text=String(v); this.children=[];}, get(){ let t=this._text; for(const c of this.children) t+= c.nodeType===3?c.text:(c.textContent||''); return t; }});
Object.defineProperty(FakeNode.prototype,'innerHTML',{ set(v){this._html=v; this.children=[];}, get(){ return this._html||''; }});
const root=new FakeNode('html'); const listeners={};
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}), documentElement:root, title:'MOJ — o competidor',
  querySelectorAll:(s)=>root.querySelectorAll(s), querySelector:(s)=>root.querySelector(s),
  addEventListener:(t,f)=>{ (listeners[t]=listeners[t]||[]).push(f); }, dispatchEvent:(e)=>{ for (const f of (listeners[e.type]||[])) f(e); return true; } };
globalThis.CustomEvent=class{ constructor(type,init){ this.type=type; this.detail=init&&init.detail; } };
globalThis.navigator={ language:'pt-BR' };
globalThis.localStorage={ _m:{}, getItem(k){ return k in this._m ? this._m[k] : null; }, setItem(k,v){ this._m[k]=String(v); } };
globalThis.location={ href:'https://moj.example/contest/ajuda/competidor.html?lang=en', search:'?lang=en', reload(){ globalThis.RELOADED=(globalThis.RELOADED||0)+1; } };
globalThis.history={ replaceState(_s,_t,u){ location.href=String(u); location.search=String(u).replace(/^[^?]*/,''); } };
globalThis.URLSearchParams=class{ constructor(s){ this.m={}; String(s||'').replace(/^\?/,'').split('&').filter(Boolean).forEach(p=>{ const [k,v]=p.split('='); this.m[decodeURIComponent(k)]=decodeURIComponent(v||''); }); }
  get(k){ return k in this.m ? this.m[k] : null; } has(k){ return k in this.m; } set(k,v){ this.m[k]=String(v); } toString(){ return Object.entries(this.m).map(([k,v])=>k+'='+encodeURIComponent(v)).join('&'); } };
globalThis.URL=class{ constructor(h){ const i=h.indexOf('?'); this.base=i<0?h:h.slice(0,i); this.searchParams=new URLSearchParams(i<0?'':h.slice(i)); } toString(){ const q=this.searchParams.toString(); return this.base+(q?'?'+q:''); } };
JS
  strip "$W/shared/i18n.js"; strip "$W/shared/dom.js"; strip "$W/shared/i18n-dom.js"; strip "$W/shared/lang-toggle.js"
  cat <<'JS'
// a página: um <span data-en> e um <html data-en-doctitle>, como nos tutoriais
root.setAttribute('data-en-doctitle','MOJ — the competitor');
const span=new FakeNode('span'); span.setAttribute('data-en','Getting in'); span.textContent='Entrar'; root.append(span);
i18nDOM();   // 1ª aplicação: a página abriu com ?lang=en
print('start=' + getLang() + ' text0=' + span.textContent + ' title0=' + document.title + ' stored0=' + localStorage.getItem('moj_lang'));
const tog=mkLangToggle({ reload:false }); const btn=(l)=>tog.children.find(b=>b.dataset.lang===l);
const active=()=>tog.children.filter(b=>b.classList.contains('active')).map(b=>b.dataset.lang).join(',');
print('active0=' + active());
btn('pt').click(); print('after_pt=' + getLang() + ' text_pt=' + span.textContent + ' title_pt=' + document.title + ' url_pt=' + location.href + ' stored_pt=' + localStorage.getItem('moj_lang') + ' active_pt=' + active() + ' reloads=' + (globalThis.RELOADED||0));
btn('en').click(); print('after_en=' + getLang() + ' text_en=' + span.textContent + ' url_en=' + location.href + ' active_en=' + active());
btn('en').click(); print('noop_en=' + getLang());
// modo header (reload): a URL com ?lang= acompanha o clique, senão o reload desfaria a escolha
const tog2=mkLangToggle({ reload:true }); tog2.children.find(b=>b.dataset.lang==='pt').click();
print('hdr=' + getLang() + ' hdr_url=' + location.href + ' reloads=' + (globalThis.RELOADED||0));
JS
} > "$T/lt.js"
out="$(gjs "$T/lt.js" 2>&1)" || { echo "$out" >&2; echo "lang-toggle: gjs falhou"; exit 1; }
kv(){ sed -n "s/^.*\b$1=\([^ ]*\).*$/\1/p" <<<"$out" | head -1; }
check "$(kv start)" en "?lang=en força EN"
check "$(kv text0)" "Getting" "texto estático em EN (data-en)"
check "$(kv stored0)" en "?lang= grava a escolha"
check "$(kv active0)" en "botão EN ativo"
check "$(kv after_pt)" pt "clicar PT troca o LANG"
check "$(kv text_pt)" Entrar "texto volta ao PT capturado (reversível)"
check "$(kv title_pt)" "MOJ" "título do documento volta ao PT"
check "$(kv url_pt)" "https://moj.example/contest/ajuda/competidor.html?lang=pt" "?lang= acompanha o clique"
check "$(kv stored_pt)" pt "escolha gravada"
check "$(kv active_pt)" pt "botão PT ativo"
check "$(kv reloads)" 0 "em lugar: sem reload"
check "$(kv after_en)" en "clicar EN troca de novo"
check "$(kv text_en)" "Getting" "texto em EN de novo"
check "$(kv url_en)" "https://moj.example/contest/ajuda/competidor.html?lang=en" "URL em en"
check "$(kv noop_en)" en "clicar no ativo não faz nada"
check "$(kv hdr)" pt "header: troca"
check "$(kv hdr_url)" "https://moj.example/contest/ajuda/competidor.html?lang=pt" "header: ?lang= presente acompanha"
check "$(sed -n 's/^.*hdr_url.* reloads=\([0-9]*\).*$/\1/p' <<<"$out")" 1 "header: recarrega"
echo "lang-toggle: $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
