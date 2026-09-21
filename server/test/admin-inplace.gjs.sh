#!/bin/bash
# admin-inplace.gjs.sh — os painéis do admin com timer atualizam EM LUGAR (regra da casa,
# CLAUDE.md › Frontend): `load()` duas vezes com o MESMO dado mantém a identidade dos nós do
# esqueleto e das caixas; dado novo troca SÓ a caixa cuja assinatura mudou. Roda os módulos ESM
# fora do browser com o gjs: DOM falso mínimo + dom.js + admin-ui.js inlinados + stubs de rede.
# Sem gjs no PATH: pula (rc 0) — é teste de dev, não de servidor.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"     # .../cdmoj
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "admin-inplace: gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }

prelude(){ cat <<'EOF'
// --- DOM mínimo ---------------------------------------------------------------------------
function FakeNode(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._text=''; this.dataset={}; }
FakeNode.prototype.append=function(){ for (const k of arguments) this.children.push(typeof k==='object'?k:{nodeType:3,text:String(k)}); };
FakeNode.prototype.appendChild=FakeNode.prototype.append;
FakeNode.prototype.setAttribute=function(k,v){ this.attrs[k]=v; };
FakeNode.prototype.addEventListener=function(){};
FakeNode.prototype.remove=function(){};
FakeNode.prototype.contains=function(n){ if(!n) return false; if(n===this) return true; return this.children.some(c=>c.nodeType===1 && c.contains(n)); };
// seletor mínimo: tags descendentes ("summary b"), uma tag ("textarea") ou [data-k="x"]
FakeNode.prototype._all=function(){ const out=[]; for (const c of this.children) { if (c.nodeType===1) { out.push(c); out.push(...c._all()); } } return out; };
FakeNode.prototype.querySelectorAll=function(sel){ const parts=sel.trim().split(/\s+/); let cand=[this]; for (const p of parts) { const next=[]; for (const n of cand) for (const d of n._all()) { const m=p.match(/^\[data-([a-z]+)="([^"]*)"\]$/); if (m ? d.dataset[m[1]]===m[2] : d.tagName===p) next.push(d); } cand=next; } return cand; };
FakeNode.prototype.querySelector=function(sel){ return this.querySelectorAll(sel)[0] || null; };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(FakeNode.prototype,'innerHTML',{set(v){this.children=[];this._html=v},get(){return this._html||''}});
Object.defineProperty(FakeNode.prototype,'textContent',{ set(v){this._text=String(v); this.children=[];},
  get(){ let t=this._text; for(const c of this.children) t+= c.nodeType===3?c.text:(c.textContent||''); return t; }});
Object.defineProperty(FakeNode.prototype,'hidden',{get(){return !!this._hidden},set(v){this._hidden=!!v}});
Object.defineProperty(FakeNode.prototype,'isConnected',{get(){return true}});
Object.defineProperty(FakeNode.prototype,'value',{get(){return this._v||''},set(v){this._v=String(v)}});
Object.defineProperty(FakeNode.prototype,'checked',{get(){return !!this._c},set(v){this._c=v}});
Object.defineProperty(FakeNode.prototype,'open',{get(){return !!this._open},set(v){this._open=!!v}});
Object.defineProperty(FakeNode.prototype,'selectedIndex',{get(){return 0}});
Object.defineProperty(FakeNode.prototype,'disabled',{get(){return !!this._d},set(v){this._d=v}});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}),
  createElementNS:(ns,t)=>new FakeNode(t), activeElement:null, body:new FakeNode('body') };
function T(pt,en){ return pt; }
globalThis.confirm=()=>false; globalThis.alert=()=>{}; globalThis.setInterval=(f,ms)=>1; globalThis.clearInterval=()=>{};
globalThis.setTimeout=(f)=>1; globalThis.clearTimeout=()=>{};
globalThis.location={hash:'', search:'', hostname:'x', origin:'https://c.x'}; globalThis.URL={createObjectURL:()=>'blob:x', revokeObjectURL:()=>{}}; globalThis.Blob=function(){};
globalThis.window={open:()=>null, addEventListener:()=>{}}; globalThis.fetch=async()=>({ok:false,status:500});
globalThis.URLSearchParams=class { constructor(){} get(){ return null; } toString(){ return ''; } };
document.getElementById=(id)=>new FakeNode('div');
const getToken=()=>''; const apiPost=async()=>({}); const mlinuxSections=()=>[el('div',{},'sec')]; const MLINUX_CSS='';
const initContestShell=async()=>({});
EOF
strip "$W/shared/dom.js"; strip "$W/shared/admin-ui.js"; }

check(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (got '$1', want '$2')" >&2; fi; }
run(){ # <nome> <módulo> <corpo js> [módulos extras…] -> imprime as linhas "k=v" do corpo
  local nome="$1" mod="$2" body="$3"; shift 3
  { prelude
    # módulos irmãos que o painel importa (ex.: sessions-common.js): entram antes, sem o `const enc` duplicado
    for x in "$@"; do strip "$W/contest/admin/$x" | sed '/^const enc = encodeURIComponent;$/d'; done
    local modpath="$W/contest/admin/$mod"; [[ "$mod" == */* ]] && modpath="$W/$mod"
    strip "$modpath"; printf '%s\n' "$body"; } > "$T/$nome.js"
  set -- "$nome"
  gjs "$T/$1.js" 2>"$T/$1.err" || { echo "gjs falhou em $1:" >&2; tail -5 "$T/$1.err" >&2; }
}
kv(){ grep "^$2=" "$T/$1.out" | cut -d= -f2-; }

# ---------------------------------------------------------------- Situação (status-tab) -----
run status status-tab.js '
let D={submissions:{pending:1,max_wait_s:12,response:{avg_s:5,p95_s:9},pending_list:[{login:"a",problem:"A",submitted_at:1,waiting_s:12}],per_problem:[{problem:"A",submits:3,pending:1,accepted:1}],recent:[{at:1,login:"a",problem:"A",verdict:"Accepted"}],timeline:[{t:1,submits:2,avg_wait_s:3}]},
       judges:{online:1,total:1,busy:0,queue_depth:0,list:[{host:"j1",online:true,state:"free",age_s:1,problems_count:2,langs:["c"]}],pool:[]}, routing:{shards:2,delivered_5m:3,workers:[{shard:0,alive_age_s:2,in_submit:1,in_results:1}]}, review:{}, window:50, now:1788000000};
let SESS={sessions:[{login:"a"}],alerts:[]}, TQ={requests:[]};
async function apiGet(p){ if(p.includes("/dashboard")) return JSON.parse(JSON.stringify(D)); if(p.includes("/sessions")) return SESS; if(p.includes("/queue")) return TQ; if(p.includes("report-publish")) return {published:false,job:null}; return {}; }
(async()=>{ const tab=makeStatusTab("c"); await tab.load(); const k0=[...tab.panel.children]; const cards0=k0[2].children[0], judges0=k0[6].children[0], pend0=k0[7].children[0];
  await tab.load(); const k1=[...tab.panel.children];
  print("same_skeleton="+k0.every((n,i)=>n===k1[i])); print("same_cards="+(k1[2].children[0]===cards0)); print("same_judges="+(k1[6].children[0]===judges0));
  D.submissions.pending_list=[]; await tab.load(); const k2=[...tab.panel.children];
  print("skeleton_after_change="+k0.every((n,i)=>n===k2[i])); print("pending_rebuilt="+(k2[7].children[0]!==pend0)); print("cards_kept="+(k2[2].children[0]===cards0)); print("judges_kept="+(k2[6].children[0]===judges0));
  print("nchildren="+k2.length);
})().catch(e=>print("ERRO "+e+"\n"+e.stack));' > "$T/status.out"
check "$(kv status same_skeleton)" true "status: esqueleto idêntico no 2º load"
check "$(kv status same_cards)" true "status: cards não refeitos sem mudança"
check "$(kv status same_judges)" true "status: juízes não refeitos sem mudança"
check "$(kv status skeleton_after_change)" true "status: esqueleto idêntico após dado novo"
check "$(kv status pending_rebuilt)" true "status: só a caixa de pendentes trocou"
check "$(kv status cards_kept)" true "status: cards ficaram (assinatura igual)"
check "$(kv status judges_kept)" true "status: juízes ficaram"

# ------------------------------------------------------------------- Staff (tasks.js) -------
run tasks tasks.js '
let Q={requests:[{id:"1",seq:1,kind:"print",status:"pending",time:1788000000,login:"a",fullname:"A",filename:"x.c"}]};
let SF={staff:[{login:"s1.staff",fullname:"S"}],regions:[{name:"Rio",regex:"^a"}],filters:{"s1.staff":["^a"]}};
async function apiGet(p){ if(p.includes("staff/queue")) return JSON.parse(JSON.stringify(Q)); if(p.includes("staff-filters")) return JSON.parse(JSON.stringify(SF)); if(p.includes("/teams")) return {teams:{}}; return {}; }
(async()=>{ const tab=makeTasksTab("c",{has:()=>true}); await tab.load();
  const sec=tab.panel.children[0]; const kids0=[...sec.children]; const cfg=kids0[kids0.length-1]; const cfgInner0=cfg.children[0];
  await tab.load(); const kids1=[...sec.children];
  print("same_skeleton="+kids0.every((n,i)=>n===kids1[i])); print("cfg_kept="+(cfg.children[0]===cfgInner0));
  // admin digitando: textarea suja + servidor mudou => a config NÃO é refeita
  function findTA(n,out){ if(!n||n.nodeType!==1) return; if(n.tagName==="textarea") out.push(n); (n.children||[]).forEach(c=>findTA(c,out)); }
  const tas=[]; findTA(cfg,tas); tas[0].value="^b\n^c"; SF.filters["s1.staff"]=["^z"]; await tab.load();
  print("cfg_kept_dirty="+(cfg.children[0]===cfgInner0)); print("ta_value="+tas[0].value.replace(/\n/g,"|"));
  // limpa a sujeira => próximo tick refaz com o dado novo
  tas[0].value=tas[0].dataset.orig; await tab.load(); print("cfg_rebuilt_clean="+(cfg.children[0]!==cfgInner0));
})().catch(e=>print("ERRO "+e+"\n"+e.stack));' > "$T/tasks.out"
check "$(kv tasks same_skeleton)" true "tasks: esqueleto idêntico no 2º load"
check "$(kv tasks cfg_kept)" true "tasks: config não refeita sem mudança"
check "$(kv tasks cfg_kept_dirty)" true "tasks: config NÃO refeita com textarea sujo (dado novo adiado)"
check "$(kv tasks ta_value)" '^b|^c' "tasks: o que o admin digitou ficou"
check "$(kv tasks cfg_rebuilt_clean)" true "tasks: config refeita depois que o textarea limpou"

# ---------------------------------------------------------------- mlinux (mlinux-tab) -------
run mlinux mlinux-tab.js '
let R={configured:true,url:"https://nb",can_admin:true,bind:{enabled:true,published:3,queued:0,log:{}},webhook:{installed:false,events:0},status:{running:true,phase:"1/3"},data:{collected_at:1,version:2,link:{mode:"ua",linked:1,present:1,coverage:100},window:{},contest:"c",global:{},by_node:{},sedes:[{id:"26x",name:"X",seen:1,machines:[{mac:"aa"}]}]}};
async function apiGet(p){ if(p.includes("/nutella")) return JSON.parse(JSON.stringify(R)); if(p.includes("/regions")) return []; return {}; }
(async()=>{ const tab=makeMlinuxTab("c"); await tab.load(); const k0=[...tab.panel.children]; const cfg0=k0[2].children[0], col0=k0[3].children[0], bnd0=k0[4].children[0], hk0=k0[5].children[0], cmd0=k0[6].children[0], pan0=k0[7].children[0];
  R.status.phase="2/3"; await tab.load(); const k1=[...tab.panel.children];
  print("same_skeleton="+k0.every((n,i)=>n===k1[i])); print("collect_changed="+(k1[3].children[0]!==col0)); print("cfg_kept="+(k1[2].children[0]===cfg0)); print("cmd_kept="+(k1[6].children[0]===cmd0)); print("pan_kept="+(k1[7].children[0]===pan0)); print("bind_kept="+(k1[4].children[0]===bnd0)); print("hook_kept="+(k1[5].children[0]===hk0));
  R.status={running:false,ok:true,finished_at:2}; R.data.collected_at=2; await tab.load(); const k2=[...tab.panel.children];
  print("pan_rebuilt_after_collect="+(k2[7].children[0]!==pan0)); print("cmd_kept2="+(k2[6].children[0]===cmd0));
  R.bind.published=4; await tab.load(); const k3=[...tab.panel.children];
  print("bind_changed="+(k3[4].children[0]!==bnd0)); print("pan_kept_on_bind="+(k3[7].children[0]===k2[7].children[0]));
  R.webhook={installed:true,events:2}; await tab.load(); const k4=[...tab.panel.children];
  print("hook_changed="+(k4[5].children[0]!==hk0)); print("bind_kept_on_hook="+(k4[4].children[0]===k3[4].children[0]));
})().catch(e=>print("ERRO "+e+"\n"+e.stack));' > "$T/mlinux.out"
check "$(kv mlinux same_skeleton)" true "mlinux: esqueleto idêntico durante a coleta"
check "$(kv mlinux collect_changed)" true "mlinux: caixa de coleta atualizou (fase)"
check "$(kv mlinux cfg_kept)" true "mlinux: config ficou"
check "$(kv mlinux cmd_kept)" true "mlinux: formulário de comando ficou"
check "$(kv mlinux pan_kept)" true "mlinux: panorama ficou durante a coleta"
check "$(kv mlinux pan_rebuilt_after_collect)" true "mlinux: panorama trocou quando a coleta terminou"
check "$(kv mlinux cmd_kept2)" true "mlinux: comando ficou mesmo com coleta nova"
check "$(kv mlinux bind_kept)" true "mlinux: cartão do vínculo ficou durante a coleta"
check "$(kv mlinux bind_changed)" true "mlinux: cartão do vínculo atualizou quando a contagem mudou"
check "$(kv mlinux pan_kept_on_bind)" true "mlinux: …sem reconstruir o panorama"
check "$(kv mlinux hook_kept)" true "mlinux: cartão do webhook ficou durante a coleta"
check "$(kv mlinux hook_changed)" true "mlinux: cartão do webhook atualizou quando instalou"
check "$(kv mlinux bind_kept_on_hook)" true "mlinux: …sem reconstruir o cartão do vínculo"

# ------------------------------------------------------------ Sessões (sessions-tab, slim) -------
run sessions sessions-tab.js '
let LA={login_enabled:true,sessions:{competitors:2,staff:0,privileged:1}};
let SE={sessions:[{login:"t1",ip:"10.0.0.1",mkey:"m:abcdef0123/b1",user_agent:"mlinux",login_at:100},{login:"t2",ip:"10.0.0.2",mkey:"ip:10.0.0.2",user_agent:"ff",login_at:200}]};
async function apiGet(p){ if(p.includes("logout-all")) return JSON.parse(JSON.stringify(LA)); if(p.includes("/sessions")) return JSON.parse(JSON.stringify(SE)); return {}; }
(async()=>{ const tab=makeSessionsTab("c",{has:()=>false}); await tab.load(); const k0=[...tab.panel.children];
  const mass0=k0[0].children[3].children[0]; const list0=k0[1].children[2].children[0]; const acc=k0[2]; acc.open=true;
  await tab.load(); const k1=[...tab.panel.children];
  print("same_skeleton="+k0.every((n,i)=>n===k1[i])); print("mass_kept="+(k1[0].children[3].children[0]===mass0)); print("list_kept="+(k1[1].children[2].children[0]===list0)); print("details_open="+k1[2].open);
  print("no_rounds_hint="+!mass0.textContent.includes("Rodadas"));
  LA.login_enabled=false; await tab.load(); const k2=[...tab.panel.children];
  print("mass_rebuilt="+(k2[0].children[3].children[0]!==mass0)); print("list_kept2="+(k2[1].children[2].children[0]===list0));
  SE.sessions.push({login:"t3",ip:"10.0.0.3",mkey:"ip:10.0.0.3",user_agent:"ff",login_at:300}); await tab.load(); const k3=[...tab.panel.children];
  print("list_rebuilt="+(k3[1].children[2].children[0]!==list0)); print("skeleton_stable="+k0.every((n,i)=>n===k3[i]));
})().catch(e=>print("ERRO "+e+"\n"+e.stack));' sessions-common.js > "$T/sessions.out"
check "$(kv sessions same_skeleton)" true "sessions: esqueleto idêntico no 2º load"
check "$(kv sessions mass_kept)" true "sessions: caixa sair-em-massa não refeita sem mudança"
check "$(kv sessions list_kept)" true "sessions: lista não refeita sem mudança"
check "$(kv sessions details_open)" true "sessions: <details> do log ficou aberto"
check "$(kv sessions no_rounds_hint)" true "sessions: sem módulo rodadas, sem dica de promover rodada"
check "$(kv sessions mass_rebuilt)" true "sessions: caixa trocou quando o login fechou"
check "$(kv sessions list_kept2)" true "sessions: lista ficou quando só o login mudou"
check "$(kv sessions list_rebuilt)" true "sessions: lista trocou com sessão nova"
check "$(kv sessions skeleton_stable)" true "sessions: esqueleto idêntico após 4 loads"

# ------------------------------------------------------------ Anomalias (anomalies-tab) ---------
run anomalies anomalies-tab.js '
let D={gate:{mode:"enforce",active:true,single_session:true},window:{start:1,end:2},computed_at:10,round:"r",counts:{sessions:2,teams_live:2,multi_session:1},
  anomalies:[{kind:"multi_session",severity:"bad",at:5,login:"t1",name:"T1",region:"X",machine:"m:a/1",detail:{sessions:2,keys:["m:a/1","m:b/2"]}}],events:[],teams:[{login:"t1",name:"T1",sessions:[{key:"m:a/1"},{key:"m:b/2"}],machines:[{key:"m:a/1",first:1,in:1}],flags:["multi_session"]}],machines:[],sites:[],channels:{logins:{web:1,cli:0,other:0},submissions:{web:1,cli:0,offline:0}}};
async function apiGet(p){ const d=JSON.parse(JSON.stringify(D)); d.computed_at=Date.now(); return d; }
(async()=>{ const tab=makeAnomaliesTab("c"); await tab.load(); const k0=[...tab.panel.children];
  const state0=k0[0].children[2].children[0], cards0=k0[0].children[3].children[0], tl0=k0[1].children[1].children[0], teams0=k0[2].children[1].children[0];
  await tab.load(); const k1=[...tab.panel.children];
  print("same_skeleton="+k0.every((n,i)=>n===k1[i])); print("state_kept="+(k1[0].children[2].children[0]===state0)); print("cards_kept="+(k1[0].children[3].children[0]===cards0));
  print("tl_kept="+(k1[1].children[1].children[0]===tl0)); print("teams_kept="+(k1[2].children[1].children[0]===teams0)); print("tl_visible="+!k1[1].hidden);
  D.counts.multi_session=2; D.anomalies.push({kind:"multi_session",severity:"bad",at:6,login:"t2",machine:"m:c/3",detail:{sessions:2,keys:["m:c/3","m:d/4"]}}); await tab.load(); const k2=[...tab.panel.children];
  print("cards_rebuilt="+(k2[0].children[3].children[0]!==cards0)); print("skeleton_stable="+k0.every((n,i)=>n===k2[i]));
  D.gate.active=false; await tab.load(); const k3=[...tab.panel.children]; print("tl_hidden_without_gate="+k3[1].hidden); print("skeleton_stable2="+k0.every((n,i)=>n===k3[i]));
})().catch(e=>print("ERRO "+e+"\n"+e.stack));' sessions-common.js > "$T/anomalies.out"
check "$(kv anomalies same_skeleton)" true "anomalies: esqueleto idêntico no 2º load"
check "$(kv anomalies state_kept)" true "anomalies: barra de estado não refeita (computed_at fora da assinatura)"
check "$(kv anomalies cards_kept)" true "anomalies: cards não refeitos sem mudança"
check "$(kv anomalies tl_kept)" true "anomalies: linha do tempo não refeita sem mudança"
check "$(kv anomalies teams_kept)" true "anomalies: tabela de times não refeita sem mudança"
check "$(kv anomalies tl_visible)" true "anomalies: linha do tempo visível com gate ativo"
check "$(kv anomalies cards_rebuilt)" true "anomalies: cards trocaram com anomalia nova"
check "$(kv anomalies skeleton_stable)" true "anomalies: esqueleto idêntico após dado novo"
check "$(kv anomalies tl_hidden_without_gate)" true "anomalies: linha do tempo escondida sem gate"
check "$(kv anomalies skeleton_stable2)" true "anomalies: esqueleto idêntico ao desligar o gate"

# ------------------------------------------------------------ Clarifications (página) ------------
run clar contest/clarification/clarification.js '
let D={can_answer:true,can_edit:true,me:"ch.cjudge",clarifications:[
  {id:"a1",time:10,problem:"A",login:"alice",asker_name:"Alice",question:"linha1\nlinha2",public:false,answer:"",answered_by:"",answer_claim:null},
  {id:"b2",time:20,problem:"general",login:"bob",asker_name:"Bob",question:"q2",public:true,answer:"resp",answered_by:"j.judge",answer_claim:null},
  {id:"c3",time:30,problem:"B",login:"",question:"",public:true,broadcast:true,answer:"aviso",answered_by:"j.judge",answer_claim:null}]};
async function apiGet(p){ if(p.includes("/clarifications")) return JSON.parse(JSON.stringify(D)); if(p.includes("/problems")) return {problems:[{short_name:"A"},{short_name:"B"}]}; return {}; }
(async()=>{ await refresh(); const k0=[...listBody.children]; const secA=k0[2], secB=k0[3];
  // respondidas vêm da mais nova p/ a mais antiga: c3 (aviso, t=30) antes de b2 (t=20)
  const cardA0=secA.body.children[0], cardC0=secB.body.children[0], cardB0=secB.body.children[1];
  print("open_first="+(secA.body.children.length===1 && cardA0.children[0].attrs["class"].startsWith("clar")));
  print("done_count="+secB.body.children.length);
  print("asker_shown="+cardA0.textContent.includes("alice"));
  print("notice_no_title="+!cardC0.textContent.includes("P:"));
  secB.open=false;
  await refresh(); const k1=[...listBody.children];
  print("same_skeleton="+k0.every((n,i)=>n===k1[i]));
  print("cards_kept="+(secA.body.children[0]===cardA0 && secB.body.children[0]===cardC0 && secB.body.children[1]===cardB0));
  print("details_kept="+(secB.open===false));
  const inner0=cardA0.children[0];
  D.clarifications[1].answer="resp2"; await refresh();
  const innerC0=cardC0.children[0];
  print("only_changed_rebuilt="+(cardA0.children[0]===inner0 && cardC0.children[0]===innerC0 && secB.body.children[1]===cardB0 && cardB0.textContent.includes("resp2")));
  // a1 respondida: sai da fila e entra em respondidas (o nó do cartão é o MESMO, só muda de seção)
  D.clarifications[0].answer="ok"; await refresh();
  print("moved_same_node="+(secB.body.children.includes(cardA0) && secA.body.children.length===1 && secA.body.children[0].attrs["class"]==="muted small"));
})().catch(e=>print("ERRO "+e+"\n"+e.stack));' > "$T/clar.out"
check "$(kv clar open_first)" true "clar: abertas = só a sem resposta"
check "$(kv clar done_count)" 2 "clar: respondidas + aviso = 2"
check "$(kv clar asker_shown)" true "clar: chefe vê o login de quem perguntou"
check "$(kv clar notice_no_title)" true "clar: aviso sem assunto não mostra P:"
check "$(kv clar same_skeleton)" true "clar: esqueleto idêntico no 2º load"
check "$(kv clar cards_kept)" true "clar: cartões não refeitos sem mudança"
check "$(kv clar details_kept)" true "clar: <details> fechado ficou fechado"
check "$(kv clar only_changed_rebuilt)" true "clar: só o cartão que mudou foi refeito"
check "$(kv clar moved_same_node)" true "clar: cartão respondido muda de seção com o mesmo nó"

grep -h "^ERRO" "$T"/*.out >&2 || true
echo "admin-inplace: PASS=$PASS FAIL=$FAIL"; exit $(( FAIL>0 ))
