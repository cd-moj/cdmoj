#!/bin/bash
# smoke-users-convert-card.gjs.sh — o cartão "🔗 Contas compartilhadas" (web/contest/admin/users-convert.js),
# a interface da conversão de contas compartilhadas em próprias. Afirma, com a API simulada:
#   • contest não compartilhado: cartão escondido; compartilhado: aparece com "Ver prévia";
#   • a prévia pede dry_run e mostra os avisos traduzidos; "Converter" nasce DESABILITADO;
#   • antes da prova: habilita com ☐ "Entendi" e manda confirm:true + o plan_id da prévia;
#   • prova começada: só habilita com o id do contest digitado, que vai como confirm;
#   • 409 plan_changed: re-renderiza a prévia NOVA com o aviso (e usa o plan_id novo);
#   • resultado: senha do admin na tela, CSV só com quem tem senha, e o cartão NÃO some quando a lista
#     recarrega já sem o compartilhamento (as senhas só aparecem ali).
set -u
command -v gjs >/dev/null 2>&1 || { echo "users-convert-card: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ cat <<'EOF'
function N(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._ev={}; this.parentNode=null; this._text=''; }
N.prototype.append=function(){ for (const k of arguments) { if (k && typeof k==='object') { k.parentNode=this; this.children.push(k); } else if (k!=null) this.children.push({nodeType:3,text:String(k)}); } };
N.prototype.setAttribute=function(k,v){ this.attrs[k]=String(v); };
N.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
N.prototype.fire=function(t){ return Promise.all((this._ev[t]||[]).map(f=>f({target:this, preventDefault(){}}))); };
N.prototype.all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1) { o.push(c); o.push(...c.all()); } return o; };
Object.defineProperty(N.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(N.prototype,'innerHTML',{set(v){this.children=[]},get(){return ''}});
Object.defineProperty(N.prototype,'textContent',{set(v){this._text=String(v);this.children=[]},
  get(){ let t=this._text; for (const c of this.children) t+= c.nodeType===3 ? c.text : c.textContent; return t; }});
Object.defineProperty(N.prototype,'value',{set(v){this._v=String(v)},get(){ return this._v!==undefined ? this._v : (this.attrs.value||''); }});
globalThis.document={ createElement:(t)=>new N(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}) };
function T(pt){ return pt; }
class ApiError extends Error { constructor(s,m,c,d){ super(m); this.status=s; this.code=c; this.data=d||{}; } }
let CALLS=[], NEXT=[];                        // a API simulada: respostas enfileiradas, chamadas registradas
async function apiPost(path, body){ CALLS.push({path, body}); const r=NEXT.shift(); if (r instanceof Error) throw r; return r; }
let CSV=null; function downloadCsv(name, rows){ CSV={name, rows}; }
EOF
  strip "$WEB/shared/dom.js"; strip "$WEB/contest/admin/users-convert.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const shown=(n)=>n.style.display!=='none';
const vis=(n)=>{ for (let x=n; x; x=x.parentNode) if (x.style && x.style.display==='none') return false; return true; };
const btn=(c,txt)=>c.el.all().filter(n=>n.tagName==='button' && n.textContent.includes(txt) && vis(n))[0];
const inputs=(c,type)=>c.el.all().filter(n=>n.tagName==='input' && (!type || n.attrs.type===type));
const PREV=(phase,pid)=>({preview:{contest:'cv',phase,plan_id:pid,sessions_live:2,registration:true,
  counts:{individuals:5,teams:1,members_with_history:1,members_losing_login:1,orphans:0,admin_created:true,new_scoreboard_rows:2,resumed:0,
          from:{dir:4,session:1,access_log:1,registration:1}},
  samples:{individuals:['ana','bia'],teams:[{login:'time-azul',name:'Azul',members:['gil','hugo']}],members_with_history:[{login:'gil',team:'time-azul'}],members_losing_login:[]},
  admin:'prof.admin', warnings:(phase!=='before'?['live']:[]).concat(['team_members_lose_login','new_scoreboard_rows','admin_local_created'])}});
(async () => {
  let done=0; const c=makeConvertCard('cv', {onDone:()=>{done++;}});
  c.show(''); ck('não compartilhado: cartão escondido', !shown(c.el));
  c.show('treino'); ck('compartilhado: cartão com a fonte e "Ver prévia"', shown(c.el) && c.el.textContent.includes('(treino)') && !!btn(c,'Ver prévia'));
  // antes da prova
  NEXT.push(PREV('before','p1')); await btn(c,'Ver prévia').fire('click');
  ck('prévia pede dry_run', CALLS.length===1 && CALLS[0].body.dry_run===true && CALLS[0].path.includes('users-convert?contest=cv'));
  ck('avisos traduzidos (time vira UMA conta, 2 zerados, admin com senha NOVA)', c.el.textContent.includes('Cada time vira UMA conta') && c.el.textContent.includes('2 pessoa(s)') && c.el.textContent.includes('prof.admin ganha conta própria'));
  let go=btn(c,'Converter em contas próprias');
  ck('"Converter" nasce desabilitado', go && go.disabled===true);
  const [logout, ack]=inputs(c,'checkbox');
  ack.checked=true; await ack.fire('change');
  ck('☐ Entendi habilita', go.disabled===false);
  // 409 plan_changed → prévia nova com aviso
  NEXT.push(new ApiError(409,'mudou','plan_changed',{preview:PREV('before','p2').preview}));
  await go.onclick();
  ck('execução manda plan_id + confirm:true + logout_all:false', J(CALLS[1].body)===J({dry_run:false,plan_id:'p1',confirm:true,logout_all:false}), J(CALLS[1].body));
  ck('plan_changed: re-renderiza com o aviso da lista que mudou', c.el.textContent.includes('A lista mudou desde a prévia'));
  go=btn(c,'Converter em contas próprias'); const ack2=inputs(c,'checkbox')[1];
  ck('…e o botão novo volta desabilitado', go.disabled===true);
  ack2.checked=true; await ack2.fire('change');
  NEXT.push({converted:true, credentials:[{login:'ana',fullname:'Ana',kind:'individual',password:'abc1234'},{login:'gil',fullname:'Gil',kind:'member_disabled',team:'time-azul'},
    {login:'prof.admin',fullname:'Prof',kind:'admin',password:'adm9999'}], counts:{}, sessions_removed:0, registrations_archived:'var/r.json'});
  await go.onclick();
  ck('usa o plan_id NOVO', CALLS[2].body.plan_id==='p2', J(CALLS[2].body));
  ck('resultado: senha nova do admin na tela', c.el.textContent.includes('adm9999') && c.el.textContent.includes('Sua senha de admin'));
  await btn(c,'baixar credenciais').fire('click');
  ck('CSV só com quem tem senha (sem o membro desabilitado)', CSV && CSV.name==='cv-credenciais.csv' && CSV.rows.map(r=>r.login).join()==='ana,prof.admin', CSV && J(CSV.rows));
  ck('onDone chamado (a lista recarrega)', done===1);
  c.show(''); ck('lista recarregada sem o compartilhamento: o resultado FICA na tela', shown(c.el) && c.el.textContent.includes('adm9999'));
  ck('"Ver prévia" some depois de converter', !btn(c,'Ver prévia'));
  // prova começada: só o id digitado
  CALLS=[]; const c2=makeConvertCard('cv2'); c2.show('treino');
  NEXT.push(PREV('running','q1')); await btn(c2,'Ver prévia').fire('click');
  const go2=btn(c2,'Converter em contas próprias'); const typed=inputs(c2).filter(n=>n.attrs.placeholder==='cv2')[0];
  ck('prova começada: aviso live + campo do id (sem ☐ Entendi)', c2.el.textContent.includes('A prova já começou') && !!typed && inputs(c2,'checkbox').length===1);
  typed.value='cv'; await typed.fire('input'); ck('id errado não habilita', go2.disabled===true);
  typed.value=' cv2 '; await typed.fire('input'); ck('id certo habilita', go2.disabled===false);
  inputs(c2,'checkbox')[0].checked=true;
  NEXT.push({converted:true, credentials:[], counts:{}, sessions_removed:3});
  await go2.onclick();
  ck('confirm = o id digitado; logout_all marcado vai junto', CALLS[1].body.confirm==='cv2' && CALLS[1].body.logout_all===true, J(CALLS[1].body));
  ck('sessões encerradas no resultado', c2.el.textContent.includes('3 sessão(ões) encerrada(s)'));
  print(''); print('RESULT: '+pass+' passed, '+fail+' failed');
  imports.system.exit(fail>0?1:0);
})().catch(e=>{ print('ERRO: '+e+'\n'+e.stack); imports.system.exit(2); });
const J=(x)=>JSON.stringify(x);
EOF
} > "$JS"
gjs "$JS"
