#!/bin/bash
# smoke-treino-admin-sessions.gjs.sh — a aba Sessões do painel do treino (web/treino/admin/sessions-tab.js) e o cartão
# de confirmação (confirmDanger, web/shared/admin-ui.js), 16/10/2026: um clique tinha deslogado 1.310 contas. Prende:
#   · a própria conta e as de papel NÃO têm caixa de seleção ("você"/"papel");
#   · admin comum: sem Travar, sem deslogar-por-IP; mais de 20 selecionados = botão travado com o motivo;
#   · a seleção é LIMPA quando a busca muda;
#   · 2+ contas: pede a prévia (dry_run) e abre o cartão; o botão só habilita com o número certo; a execução manda
#     plan_id + confirm; plan_changed refaz o cartão com a prévia nova;
#   · o super-admin vê Travar e o ⏏ do IP, e passa de 20.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "treino-admin-sessions(gjs): gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
check(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (got '$1', want '$2')" >&2; fi; }
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.dataset={}; this.style={}; this._ev={}; this._cls=new Set(); this._text=''; }
FakeNode.prototype.append=function(){ for (const k of arguments) { if (k==null||k==='') continue; this.children.push(typeof k==='object'?k:{nodeType:3,text:String(k)}); } };
FakeNode.prototype.appendChild=FakeNode.prototype.append;
FakeNode.prototype.setAttribute=function(k,v){ if(k==='class') this._cls=new Set(String(v).split(/\s+/).filter(Boolean)); this.attrs[k]=v; };
FakeNode.prototype.getAttribute=function(k){ return k in this.attrs ? this.attrs[k] : null; };
FakeNode.prototype.addEventListener=function(t,f){ (this._ev[t]=this._ev[t]||[]).push(f); };
FakeNode.prototype.fire=function(t){ for (const f of (this._ev[t]||[])) f({}); };
FakeNode.prototype.remove=function(){ if (this.parent) this.parent.children=this.parent.children.filter(c=>c!==this); };
FakeNode.prototype.focus=function(){};
FakeNode.prototype._all=function(){ const o=[]; for (const c of this.children) if (c.nodeType===1){ c.parent=this; o.push(c); o.push(...c._all()); } return o; };
FakeNode.prototype.querySelectorAll=function(sel){ if (sel[0]==='.') { const cls=sel.slice(1); return this._all().filter(n=>n._cls.has(cls)); } return this._all().filter(n=>n.tagName===sel); };
FakeNode.prototype.querySelector=function(sel){ return this.querySelectorAll(sel)[0]||null; };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.setAttribute('class',v)},get(){return [...this._cls].join(' ')}});
Object.defineProperty(FakeNode.prototype,'classList',{get(){ const s=this._cls; return { contains:(c)=>s.has(c), toggle:(c,on)=>{ if(on===undefined) on=!s.has(c); on?s.add(c):s.delete(c); return on; }, add:(c)=>s.add(c), remove:(c)=>s.delete(c) }; }});
Object.defineProperty(FakeNode.prototype,'textContent',{ set(v){this._text=String(v); this.children=[];}, get(){ let t=this._text; for(const c of this.children) t+= c.nodeType===3?c.text:(c.textContent||''); return t; }});
Object.defineProperty(FakeNode.prototype,'innerHTML',{ set(v){this._html=v; this.children=[];}, get(){ return this._html||''; }});
Object.defineProperty(FakeNode.prototype,'value',{get(){return this._v||''},set(v){this._v=String(v)}});
Object.defineProperty(FakeNode.prototype,'checked',{get(){return !!this._c},set(v){this._c=v}});
Object.defineProperty(FakeNode.prototype,'disabled',{get(){return !!this._d},set(v){this._d=v}});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t)}), getElementById:()=>new FakeNode('div'), activeElement:null, body:new FakeNode('body') };
globalThis.location={ reload(){}, hash:'', search:'' }; globalThis.confirm=()=>true; globalThis.alert=()=>{};
globalThis.localStorage={ getItem:()=>null, setItem(){} }; globalThis.navigator={language:'pt-BR'};
Object.defineProperty(FakeNode.prototype,'hidden',{get(){return !!this._h},set(v){this._h=v}});
const T=(pt)=>pt; const uiLocale=()=>'pt-BR'; const getToken=()=>'t';   // fmtDate vem do admin-ui.js
const avatarEl=(login,name)=>{ const n=new FakeNode('img'); n.setAttribute('alt',name||login); return n; };
const NOW=1792100000;
const SESS=[{login:'adm.admin',name:'Eu',ip:'1.1.1.1'},{login:'juiz.judge',name:'Juiz',ip:'1.1.1.2'}];
for (let i=1;i<=25;i++) SESS.push({login:'al'+String(i).padStart(2,'0'), name:'Aluno '+i, ip:'10.0.0.'+i, login_at:NOW});
const POSTS=[]; let NEXT=null;
const apiGet=async()=>({count:SESS.length, sessions:SESS});
const apiPost=async(path,body)=>{ POSTS.push({path, body}); if (NEXT) { const f=NEXT; NEXT=null; return f(body); }
  if (body.dry_run) return {preview:true, plan_id:'pid1', need:(body.logins||[]).length, sessions_count:(body.logins||[]).length, sample:body.logins||[], skipped_count:0, skipped_by_reason:{}};
  return {logged_out:true, users_count:(body.logins||[1]).length, sessions_removed:1}; };
JS
  strip "$W/shared/dom.js"
  strip "$W/shared/admin-ui.js"
  strip "$W/treino/admin/sessions-tab.js"
  cat <<'JS'
const tick = async () => { for (let i = 0; i < 30; i++) await Promise.resolve(); };
const btns = (p, t) => p.querySelectorAll('button').filter((b) => b.textContent.startsWith(t));
const boxes = (p) => p.querySelectorAll('input').filter((i) => i.attrs.type === 'checkbox' && (i.attrs['aria-label'] || '').startsWith('selecionar'));
(async () => {
  // ---- admin comum
  const tab = makeSessionsTab({ isSuper: false, me: 'adm.admin' }); await tab.load(); await tick();
  const p = tab.panel, txt = p.textContent;
  print('caixas=' + boxes(p).length + ' voce=' + txt.includes('você') + ' papel=' + txt.includes('papel'));
  print('sem_travar=' + (btns(p, 'Travar').length === 0) + ' sem_ip=' + (btns(p, '⏏').length === 0));
  const selAll = p.querySelectorAll('input').find((i) => i.attrs.type === 'checkbox' && (i.attrs.title || '').startsWith('Selecionar'));
  selAll.checked = true; selAll.fire('change');
  const bulk = btns(p, 'Deslogar selecionados')[0];
  print('todos25=' + bulk.textContent.includes('(25)') + ' travado=' + bulk.disabled + ' motivo=' + p.textContent.includes('super-admin da plataforma'));
  const search = p.querySelectorAll('input').find((i) => i.attrs.type === 'search');
  search.value = 'al0'; search.fire('input');
  print('busca_limpa=' + (btns(p, 'Deslogar selecionados')[0].textContent === 'Deslogar selecionados'));
  search.value = ''; search.fire('input');
  boxes(p).slice(0, 3).forEach((c) => { c.checked = true; c.fire('change'); });
  btns(p, 'Deslogar selecionados')[0]._ev.click[0](); await tick();
  print('dry_run=' + (POSTS.length === 1 && POSTS[0].body.dry_run === true && POSTS[0].body.logins.length === 3));
  const card = p.querySelectorAll('.danger-confirm')[0];
  const go = card.querySelectorAll('button').find((b) => b.textContent === 'Deslogar');
  const inp = card.querySelectorAll('input')[0];
  print('cartao=' + !!card + ' go_inicial_desab=' + ('disabled' in go.attrs));
  inp.value = '2'; inp.fire('input'); const errado = go.disabled;
  inp.value = '3'; inp.fire('input'); const certo = !go.disabled;
  print('numero_errado_desab=' + errado + ' numero_certo_hab=' + certo);
  // o servidor diz que mudou: o cartão se refaz com a prévia nova
  NEXT = () => { const e = new Error('mudou'); e.code = 'plan_changed'; e.data = { preview: { preview: true, plan_id: 'pid2', need: 4, sessions_count: 4, sample: ['al01'], skipped_count: 0 } }; throw e; };
  go._ev.click[0](); await tick();
  const card2 = p.querySelectorAll('.danger-confirm')[0];
  print('refeito=' + (card2.textContent.includes('Digite 4') && card2.textContent.includes('mudou desde a prévia')));
  const go2 = card2.querySelectorAll('button').find((b) => b.textContent === 'Deslogar'); const inp2 = card2.querySelectorAll('input')[0];
  inp2.value = '4'; inp2.fire('input'); go2._ev.click[0](); await tick();
  const last = POSTS[POSTS.length - 1].body;
  print('executou=' + (last.plan_id === 'pid2' && last.confirm === 4 && !last.dry_run));
  // prévia com 0 afetados (ninguém com sessão aberta): "Nada a fazer", sem campo nem botão de executar
  const z = confirmDanger({ title: 'x', verb: 'Deslogar', preview: { plan_id: 'p0', need: 0, sessions_count: 0, sample: [] }, run: async () => { throw new Error('não devia rodar'); } });
  print('zero=' + (z.textContent.includes('Nada a fazer') && z.querySelectorAll('input').length === 0 && !z.querySelectorAll('button').some((b) => b.textContent === 'Deslogar')));
  // ---- super-admin
  const st = makeSessionsTab({ isSuper: true, me: 'sup.admin' }); await st.load(); await tick();
  print('super_travar=' + (btns(st.panel, 'Travar').length > 0) + ' super_ip=' + (btns(st.panel, '⏏').length > 0));
  const sa = st.panel.querySelectorAll('input').find((i) => i.attrs.type === 'checkbox' && (i.attrs.title || '').startsWith('Selecionar'));
  sa.checked = true; sa.fire('change');
  const sb = btns(st.panel, 'Deslogar selecionados')[0];
  print('super_25=' + sb.textContent.includes('(25)') + ' super_hab=' + !sb.disabled);
})().catch((e) => { print('ERRO ' + e + '\n' + (e.stack || '')); });
JS
} > "$T/s.js"
out="$(timeout 60 gjs "$T/s.js" 2>&1)" || { echo "$out" >&2; echo "treino-admin-sessions(gjs): gjs falhou"; exit 1; }
grep -q '^ERRO' <<<"$out" && { echo "$out" >&2; exit 1; }
kv(){ sed -n "s/^.*\b$1=\([^ ]*\).*$/\1/p" <<<"$out" | head -1; }
check "$(kv caixas)" 25 "só os 25 alunos têm caixa (você e o juiz não)"
check "$(kv voce)" true "a própria conta marcada 'você'"
check "$(kv papel)" true "conta de papel marcada 'papel'"
check "$(kv sem_travar)" true "admin comum: sem Travar"
check "$(kv sem_ip)" true "admin comum: sem deslogar-por-IP"
check "$(kv todos25)" true "'visíveis' seleciona os 25 alunos"
check "$(kv travado)" true "25 > 20: o botão trava p/ admin comum"
check "$(kv motivo)" true "…com o motivo na tela"
check "$(kv busca_limpa)" true "mudar a busca LIMPA a seleção"
check "$(kv dry_run)" true "2+ contas: pede a prévia (dry_run) primeiro"
check "$(kv cartao)" true "abre o cartão de confirmação"
check "$(kv go_inicial_desab)" true "o botão nasce desabilitado"
check "$(kv numero_errado_desab)" true "número errado: segue desabilitado"
check "$(kv numero_certo_hab)" true "número certo: habilita"
check "$(kv refeito)" true "plan_changed: o cartão se refaz com a prévia nova"
check "$(kv executou)" true "executa com plan_id + confirm"
check "$(kv zero)" true "prévia com 0 afetados: 'Nada a fazer', sem pedir para digitar 0"
check "$(kv super_travar)" true "super: vê Travar"
check "$(kv super_ip)" true "super: vê o ⏏ do IP"
check "$(kv super_25)" true "super: seleciona os 25 alunos (contas de papel fora também p/ ele)"
check "$(kv super_hab)" true "super: passa de 20"
echo "treino-admin-sessions(gjs): $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
