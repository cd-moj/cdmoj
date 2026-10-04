#!/bin/bash
# smoke-settings-groups.gjs.sh — Central › Regras agrupa o editor de configurações por ÍNDICE dos filhos
# (web/contest/admin/settings-tab.js GROUPS × web/shared/contest-config/settings-editor.js). Tirar ou pôr
# um campo no meio do editor desloca tudo e o campo cai na seção errada, sem erro nenhum (SHOWCODE em
# 18/09, ALLOWLATEUSER em 28/09 — os dois renumeraram à mão). Afirma, montando o editor de verdade:
#   • todo filho do editor está em exatamente UMA seção (nenhum sobra p/ "Outras opções", nenhum repete);
#   • os campos-âncora caem na seção certa (login/secreto/gate na de acesso, log/editor na do time,
#     veredicto manual/linguagens/pool no julgamento, anônimo/penalidade/balões no placar, fuso na janela);
#   • o "auto-cadastro (late users)" não existe mais;
#   • PRIORIDADE (01/10/2026): editável no admin sem Super, travada quando é Super, só vai ao servidor quando muda;
#     na criação, Super só p/ o super-admin do treino;
#   • FUSO: as sugestões são todos os fusos do navegador, o dele em 1º (o organizador do Chile não achava o dele).
set -u
command -v gjs >/dev/null 2>&1 || { echo "settings-groups: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
# GROUPS do settings-tab.js: [{label (pt), idx}] — lido do fonte (o array mora dentro do closure da aba)
GROUPS_JSON="$(python3 - "$WEB/contest/admin/settings-tab.js" <<'PY'
import re, sys, json
s = open(sys.argv[1]).read()
blk = s[s.index('const GROUPS = () => ['):]; blk = blk[:blk.index('];')]
out = [{'label': m.group(1), 'idx': [int(x) for x in m.group(2).split(',') if x.strip()]}
       for m in re.finditer(r"label: T\('([^']*)'.*?idx: \[([0-9, ]*)\]", blk)]
print(json.dumps(out))
PY
)"
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function N(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this.dataset={}; this._ev={}; this.parentNode=null; this._text=''; }
N.prototype.append=function(){ for (const k of arguments) { if (k && typeof k==='object') { k.parentNode=this; this.children.push(k); } else if (k!=null) this.children.push({nodeType:3,text:String(k)}); } };
N.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
N.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
Object.defineProperty(N.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(N.prototype,'innerHTML',{set(v){this.children=[]},get(){return ''}});
Object.defineProperty(N.prototype,'textContent',{set(v){this._text=String(v);this.children=[]},
  get(){ let t=this._text; for (const c of this.children) t+= c.nodeType===3 ? c.text : c.textContent; return t; }});
Object.defineProperty(N.prototype,'value',{set(v){this._v=String(v)},get(){ return this._v!==undefined ? this._v : (this.attrs.value||''); }});
globalThis.document={ createElement:(t)=>new N(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}) };
function T(pt){ return pt; }
const makeLangPicker=()=>({ el:Object.assign(new N('div'),{_text:'[lang-picker]'}), get:()=>[] });
const makeJudgePicker=()=>({ el:Object.assign(new N('div'),{_text:'[judge-picker]'}), get:()=>[] });
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/shared/contest-config/util.js"; strip "$WEB/shared/contest-config/settings-editor.js"
  printf 'const GROUPS=%s;\n' "$GROUPS_JSON"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const ed=makeSettingsEditor({ value:{}, mode:'admin', contestMode:'icpc' });
const kids=ed.el.children;
ck('GROUPS lido do settings-tab.js (5 seções)', GROUPS.length===5, JSON.stringify(GROUPS));
const all=GROUPS.flatMap(g=>g.idx), seen=new Set(all);
ck('nenhum índice repetido', seen.size===all.length);
const orphan=[...kids.keys()].filter(i=>!seen.has(i));
ck('todo filho do editor está numa seção (nada sobra p/ "Outras opções"; '+kids.length+' filhos)', orphan.length===0,
   'sobram: '+orphan.map(i=>i+'='+kids[i].textContent.slice(0,40)).join(' | '));
ck('nenhum índice aponta além do editor', all.every(i=>i<kids.length), 'max='+Math.max(...all)+' filhos='+kids.length);
const sec=(txt)=>{ const i=[...kids.keys()].find(k=>kids[k].textContent.includes(txt)); const g=GROUPS.find(g=>g.idx.includes(i)); return g ? g.label : ('(índice '+i+' sem seção)'); };
const want=[['Login habilitado','Acesso'],['SUPER SECRETO','Acesso'],['Gate de login por substring','Acesso'],
  ['ver o log de julgamento','O que o time vê'],['Editor de código no browser','O que o time vê'],['pedidos de impressão','O que o time vê'],
  ['Veredicto manual','Julgamento'],['Nº de juízes que validam','Julgamento'],['Linguagens permitidas','Julgamento'],['Máquinas de juiz','Julgamento'],
  ['Placar anônimo','Placar'],['Penalidade','Placar'],['Placar completo','Placar'],['Balões durante o freeze','Placar'],['Célula "resolveu"','Placar'],
  ['Fuso horário da prova','Identidade'],['Abertura do login','Identidade'],['Prioridade no julgamento','Julgamento']];
for (const [txt, g] of want) { const got=sec(txt); ck('"'+txt+'" → '+g, got.includes(g), got); }
ck('o "auto-cadastro (late users)" não existe mais', !ed.el.textContent.includes('auto-cadastro') && ed.getValue().allow_late===undefined);
// PRIORIDADE (01/10/2026): editável no modo admin, sem Super; Super travada; só vai no getValue() quando MUDA
const sels=(e)=>{ const out=[]; const walk=(n)=>{ for (const c of (n.children||[])) { if (c.tagName==='select') out.push(c); walk(c); } }; walk(e.el); return out; };
const prioSel=(e)=>sels(e).find((x)=>x.children.some((o)=>o.attrs && o.attrs.value==='prova'));
const opts=(x)=>x.children.map((o)=>o.attrs.value);
let e2=makeSettingsEditor({ value:{ priority:'lista-publica', priority_set:false }, mode:'admin', contestMode:'icpc' });
let ps=prioSel(e2);
ck('admin: "não definida" + as três de baixo, sem Super', ps && JSON.stringify(opts(ps))==='["","lista-publica","lista-privada","prova"]', ps && JSON.stringify(opts(ps)));
ck('admin: sem mudar, o getValue() não leva prioridade', !('priority' in e2.getValue()));
ps.value='lista-publica';
ck('admin: escolher Lista pública (antes não definida) conta como mudança', e2.getValue().priority==='lista-publica');
e2=makeSettingsEditor({ value:{ priority:'prova', priority_set:true }, mode:'admin', contestMode:'icpc' }); ps=prioSel(e2);
ck('admin: definida = sem a opção "não definida"', JSON.stringify(opts(ps))==='["lista-publica","lista-privada","prova"]' && ps.value==='prova');
ck('admin: igual à salva não vai', !('priority' in e2.getValue()));
ps.value='lista-privada'; ck('admin: mudou → vai', e2.getValue().priority==='lista-privada');
e2=makeSettingsEditor({ value:{ priority:'super', priority_set:true, priority_locked:true }, mode:'admin', contestMode:'icpc' });
const sup=sels(e2).find((x)=>x.children.some((o)=>o.attrs && o.attrs.value==='super'));
ck('admin em Super: campo travado, só Super, aviso do super-admin', sup && sup.disabled===true && JSON.stringify(opts(sup))==='["super"]' && e2.el.textContent.includes('só ele a muda'));
ck('admin em Super: o getValue() nunca leva prioridade', !('priority' in e2.getValue()));
const cr=(cs)=>prioSel(makeSettingsEditor({ value:{}, mode:'create', contestMode:'icpc', canSuper:cs }));
ck('criação: Super só com canSuper (super-admin do treino)', !opts(cr(false)).includes('super') && opts(cr(true)).includes('super'));
// TCP 2026 (03/10/2026): na CRIAÇÃO não há padrão — "— escolha —" e o assistente não cria sem escolher
const ec=makeSettingsEditor({ value:{}, mode:'create', contestMode:'icpc' }); const pc=prioSel(ec);
ck('criação: começa em "— escolha —" (sem padrão)', pc && opts(pc)[0]==='' && pc.value==='' && ec.getValue().priority==='', pc && JSON.stringify(opts(pc)));
ck('criação: escolher Prova vai no getValue()', (pc.value='prova', ec.getValue().priority==='prova'));
const ed2=makeSettingsEditor({ value:{ priority:'prova' }, mode:'create', contestMode:'icpc' });
ck('criação a partir de template/duplicação: a prioridade da origem vem marcada', prioSel(ed2).value==='prova' && ed2.getValue().priority==='prova');
// FUSO (03/10/2026): sugestões = todos os fusos do navegador, o do próprio navegador em 1º (gjs roda com TZ=America/Santiago)
const tzs=tzSuggestions('America/Belem');
ck('fuso: o do navegador vem em 1º (America/Santiago)', tzs[0]==='America/Santiago', tzs.slice(0,3).join(','));
ck('fuso: o salvo vem logo depois e sem repetir', tzs[1]==='America/Belem' && tzs.filter((z)=>z==='America/Belem').length===1);
ck('fuso: a lista traz todos (centenas, com Mexico_City e Lima)', tzs.length>300 && tzs.includes('America/Mexico_City') && tzs.includes('America/Lima'), String(tzs.length));
const dl=(e)=>{ let f=null; const walk=(n)=>{ for (const c of (n.children||[])) { if (c.tagName==='datalist') f=c; walk(c); } }; walk(e.el); return f; };
const d1=dl(makeSettingsEditor({ value:{ tz:'America/Belem' }, mode:'admin', contestMode:'icpc' }));
ck('editor: o datalist usa essas sugestões', d1 && d1.children[0].attrs.value==='America/Santiago' && d1.children.length===tzs.length);
const sv=Intl.supportedValuesOf; Intl.supportedValuesOf=undefined;
const old=tzSuggestions('');
ck('navegador sem Intl.supportedValuesOf: lista curta das Américas, com Santiago', old.includes('America/Santiago') && old.includes('America/Mexico_City') && old.length<60, String(old.length));
Intl.supportedValuesOf=sv;
// DATAS/IDIOMA/FUSO só vão quando MUDAM (auditoria do painel, 03/10/2026): o campo tem precisão de MINUTO e
// mandar de volta início/fim/freeze com segundos os arredondava a cada Salvar; LOCALE ausente virava `pt` gravado
const dts=(e)=>{ const o=[]; const walk=(n)=>{ for (const c of (n.children||[])) { if (c.tagName==='input' && c.attrs.type==='datetime-local') o.push(c); walk(c); } }; walk(e.el); return o; };
const BS=1791000045, BE=1791010046, BF=1791007209;
const e3=makeSettingsEditor({ value:{ start:BS, end:BE, freeze:BF, login_start:0, locale:'es', locale_set:true, tz:'America/Santiago' }, mode:'admin', contestMode:'icpc' });
let v3=e3.getValue();
ck('datas sem mexer voltam com os SEGUNDOS (não arredonda)', v3.start===BS && v3.end===BE, JSON.stringify([v3.start, v3.end]));
ck('freeze/idioma/fuso sem mexer não vão', !('freeze' in v3) && !('locale' in v3) && !('tz' in v3) && !('login_start' in v3), JSON.stringify(v3));
const [iS, iE, iL, iF]=dts(e3);
iF.value='2026-10-03T22:00'; v3=e3.getValue();
ck('freeze mexido vai (e no minuto escolhido)', v3.freeze===dtToEpoch('2026-10-03T22:00'));
iF.value=''; ck('freeze apagado vai como 0', e3.getValue().freeze===0);
iL.value='2026-10-03T08:00'; e3.commit(e3.getValue()); iL.value='';
ck('commit: abertura gravada e apagada na MESMA visita manda o 0', e3.getValue().login_start===0);
const e4=makeSettingsEditor({ value:{ locale:'pt', locale_set:false }, mode:'admin', contestMode:'icpc' });
const ls4=sels(e4).find((x)=>x.children.some((o)=>o.attrs && o.attrs.value==='es') && x.children.some((o)=>o.attrs && o.attrs.value===''));
ck('idioma ausente: "automático" marcado e não vai no getValue()', ls4 && ls4.value==='' && !('locale' in e4.getValue()));
ls4.value='es'; ck('escolher um idioma vai', e4.getValue().locale==='es');
print(''); print('RESULT: '+pass+' passed, '+fail+' failed');
imports.system.exit(fail>0?1:0);
EOF
} > "$JS"
TZ=America/Santiago gjs "$JS"
