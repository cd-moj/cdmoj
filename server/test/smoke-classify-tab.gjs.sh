#!/bin/bash
# smoke-classify-tab.gjs.sh — o painel Evento › Classificação (web/contest/admin/classify-tab.js) rodando fora do
# browser (gjs + DOM falso): relação agrupada pela ordem do estágio (manual 🛠, retirado ✂), as ações de override
# vão p/ o estágio CERTO (inclusive vindo do modo "nova etapa" com o id de um estágio que já existe), contest sem
# estágio abre em "nova etapa", motor sem formulário usa o editor JSON semeado. Sem gjs: pula.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; TD="$(mktemp -d)"; trap 'rm -rf "$TD"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "classify-tab: gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
check(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (got '$1', want '$2')" >&2; fi; }
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
{ cat <<'JS'
function FakeNode(tag){ this.tagName=tag; this.nodeType=1; this.children=[]; this.attrs={}; this.style={}; this._text=''; this.dataset={}; this.ev={}; }
FakeNode.prototype.append=function(){ for (const k of arguments) this.children.push(k!==null&&typeof k==='object'?k:{nodeType:3,text:String(k)}); };   // como o DOM: null vira o texto "null"
FakeNode.prototype.appendChild=FakeNode.prototype.append;
FakeNode.prototype.setAttribute=function(k,v){ this.attrs[k]=v; };
FakeNode.prototype.addEventListener=function(k,f){ this.ev[k]=f; };
FakeNode.prototype._all=function(){ const out=[]; for (const c of this.children) { if (c.nodeType===1) { out.push(c); out.push(...c._all()); } } return out; };
FakeNode.prototype.find=function(tag, pred){ return this._all().filter((n)=>n.tagName===tag && (!pred || pred(n))); };
Object.defineProperty(FakeNode.prototype,'className',{set(v){this.attrs['class']=v},get(){return this.attrs['class']||''}});
Object.defineProperty(FakeNode.prototype,'innerHTML',{set(v){this.children=[];this._html=v},get(){return this._html||''}});
Object.defineProperty(FakeNode.prototype,'textContent',{ set(v){this._text=String(v); this.children=[];},
  get(){ let t=this._text; for(const c of this.children) t+= c.nodeType===3?c.text:(c.textContent||''); return t; }});
Object.defineProperty(FakeNode.prototype,'value',{get(){return this._v||''},set(v){this._v=String(v)}});
globalThis.document={ createElement:(t)=>new FakeNode(t), createTextNode:(t)=>({nodeType:3,text:String(t),textContent:String(t)}) };
let LANG='pt'; function T(pt,en,es){ return pt; } function uiLocale(){ return 'pt-BR'; }
let PROMPT='desistiu'; globalThis.prompt=()=>PROMPT; globalThis.confirm=()=>true;
let GET=null; const POSTS=[];
async function apiGet(){ return JSON.parse(JSON.stringify(GET)); }
let PREVIEW = null;
async function apiPost(p, body){ POSTS.push(body); return body.action === 'preview' && PREVIEW ? JSON.parse(JSON.stringify(PREVIEW)) : {}; }
JS
  strip "$W/shared/dom.js"; strip "$W/shared/admin-ui.js"; strip "$W/contest/score/score-classified.js"
  strip "$W/contest/admin/classify-result.js"; strip "$W/contest/admin/classify-tab.js"
  cat <<'JS'
const L = { regra1:{pt:'Regra 1 — melhores gerais', short:{pt:'regra 1'}}, regra2:{pt:'Regra 2 — vagas por sede'}, manual:{pt:'Promoção manual (comitê)'} };
const BR = { id:'sbc-fase1', name:{pt:'SBC 1ª fase → Final Brasileira'}, stage:'final-br', form:'br', defaults:{name:'Final Brasileira', chip:'Final BR'}, vias:['regra1','regra2','regra4'] };
const JS_ = { id:'x-json', name:{pt:'Motor JSON'}, stage:'pda', form:'json', defaults:{name:'PDA', chip:'PDA'}, seed:{N:40, regions:{br:'Brasil'}} };
const FB = { id:'final-br', status:'published', name:'Final Brasileira', chip:'Final BR', labels:L, via_order:['regra1','regra2','regra4','manual'],
  config:{algorithm:'sbc-fase1', r1:3, sedes:{'SP, Capital':2}}, result:{warnings:[{code:'female_prefix_match', data:{logins:['teamsp01']}}]},
  overrides:[{id:'ov-1',op:'withdraw',login:'teamrj02',reason:'desistiu'},{id:'ov-2',op:'add',login:'teamam02',reason:'regra 3'},{id:'ov-3',op:'exclude',login:'teamsp04',reason:'inelegível'}],
  relation:[{login:'teamsp01',team:'USP',via:'regra1',place:1},{login:'teamrj02',team:'UFF',via:'regra2',place:9,withdrawn:{id:'ov-1',reason:'desistiu'}},
            {login:'teamam02',team:'UFAM',via:'manual',manual:true,override:'ov-2',reason:'regra 3'},{login:'teamxx',team:'X',via:'viaNova',place:20},{login:'ext:lugia',team:'Lugia',via:'viaNova'}] };
const txt = (n) => n.textContent;
const val = (n) => (n._v != null ? n.value : (n.attrs.value || ''));   // el() grava value como atributo
(async () => {
  // 1) contest com dois estágios
  GET = { stages:[FB, {id:'pda', status:'draft', name:'PDA', relation:[], overrides:[]}], algorithms:[BR, JS_], vias:L, manual_vias:['manual','lista','reserva'] };
  const tab = makeClassifyTab('cb'); await tab.load();
  const p = tab.panel;
  const h4 = p.find('h4').map(txt);
  print('groups=' + h4.filter((t) => / — \d+$/.test(t)).join('|'));
  const rows = p.find('tr').map(txt);
  print('manual_row=' + rows.some((t) => t.includes('UFAM') && t.includes('🛠 regra 3')));
  print('withdrawn_row=' + rows.some((t) => t.includes('UFF') && t.includes('✂ retirado: desistiu')));
  print('warn=' + p.find('li').map(txt).some((t) => t.includes('PREFIXO') && t.includes('teamsp01')));
  print('overrides_n=' + (p.find('summary').map(txt).find((t) => t.includes('Overrides')) || ''));
  print('br_form=' + p.find('textarea').length);
  // ✂ na linha do teamsp01 → withdraw no estágio final-br com o motivo do prompt
  const cut = p.find('button', (b) => txt(b) === '✂')[0];
  cut.ev.click(); await null; await null;
  print('post1=' + JSON.stringify(POSTS[0]));
  // time de fora do placar: só ✂ (sem ⊘), e o withdraw vai por `ext`
  const extRow = p.find('tr', (r) => txt(r).includes('Lugia'))[0];
  const extBtns = extRow.find('button').map(txt);
  print('ext_btns=' + extBtns.join(''));
  POSTS.length = 0; extRow.find('button')[0].ev.click(); await null; await null;
  print('post_ext=' + JSON.stringify(POSTS[0]));
  // 2) seletor → "nova etapa": os dois estágios padrão já existem ⇒ id em branco, sem ações de override
  const sel = p.find('select')[0]; sel.value = '__new'; sel.onchange();
  let fid = p.find('input', (n) => n.attrs.placeholder === 'id')[0];
  print('newid_empty=' + (fid && val(fid) === ''));
  print('new_mode_no_actions=' + (p.find('button', (b) => txt(b).includes('Promover à mão')).length === 0));
  fid.value = 'nova1'; fid.oninput(); fid.onchange();
  const algSel = p.find('select')[1]; algSel.value = 'x-json'; algSel.onchange();
  let ta = p.find('textarea')[0];
  print('json_seed=' + (ta && JSON.parse(ta.value).N === 40 && JSON.parse(ta.value).algorithm === 'x-json'));
  print('typed_kept=' + val(p.find('input', (n) => n.attrs.placeholder === 'id')[0]));
  // id de um estágio que já existe (pda, sem motor) ⇒ vira ESSE estágio, levando o motor escolhido
  fid = p.find('input', (n) => n.attrs.placeholder === 'id')[0];
  fid.value = 'pda'; fid.oninput(); fid.onchange();
  print('collapsed_sel=' + p.find('select')[0].value);
  ta = p.find('textarea')[0];
  print('pda_json=' + (ta && JSON.parse(ta.value).algorithm === 'x-json'));
  POSTS.length = 0; PROMPT = '';
  const addBtn = p.find('button', (b) => txt(b).includes('Promover à mão'))[0];
  const reason = p.find('input', (n) => (n.attrs.placeholder || '').startsWith('motivo'))[0];
  const login = p.find('input', (n) => n.attrs.placeholder === 'login')[0];
  login.value = 'teamsp02'; reason.value = 'regra 3';
  p.find('select', (n) => n.children.some((o) => o.attrs && o.attrs.value === 'reserva'))[0].value = 'manual';   // o browser já começa na 1ª opção
  addBtn.ev.click(); await null; await null;
  print('post2=' + JSON.stringify(POSTS[0]));
  // 2b) estágio de motor com lista de espera: botão "promover o próximo" + detalhes (geo, lista)
  const PDA = { id:'latam-pda', name:{pt:'LATAM PDA'}, stage:'pda', form:'json', waitlist:true, seed:{N:40} };
  GET = { stages:[{ id:'pda', status:'draft', name:'PDA', chip:'PDA', config:{algorithm:'latam-pda', N:12},
    result:{ blocks:[{id:'p1', slots:6, used:6}], geo:{schools_latam:18, remaining:3, overflow:0, regions:[{code:'mx', name:'México', schools:4, q:12, nslots:0, fraction_prev:0, fraction:0.6667, extra:1, slots:1, filled:1, fraction_out:0}]},
      fractions_out:{no:0.3333}, waitlist:[{pos:1, tier:'mx', login:'teammxmx05', team:'UANL 1', place:23}],
      awards:{champion:[{login:'a1', team:'Alfa', place:1}], medals:{gold:[{login:'a1', team:'Alfa', place:1}]}, regional:[{region:'br', title:'Campeones Brasileños', login:'b1', team:'Beta', place:2}]} },
    relation:[], overrides:[] }], algorithms:[BR, PDA], vias:L, manual_vias:['manual','lista','reserva'] };
  POSTS.length = 0; PROMPT = 'vaga do UTN';
  const tab3 = makeClassifyTab('lar'); await tab3.load();
  const nxt = tab3.panel.find('button', (b) => txt(b).includes('Promover o próximo'))[0];
  print('next_btn=' + !!nxt);
  nxt.ev.click(); await null; await null;
  print('post3=' + JSON.stringify(POSTS[0]));
  const all = txt(tab3.panel);
  // a PRÉVIA (sem unused, sem overrides: os nós condicionais são null) não pode escrever "null"
  PREVIEW = { preview:{ total:1, blocks:[{id:'p1', slots:6, used:1}], warnings:[{code:'geo_unfilled', data:{region:'so', slots:1, filled:0}}], via_order:['p1'] },
    relation:[{login:'teambrbr01', team:'USP 1', via:'p1', place:1}], overrides:[] };
  const prevBtn = tab3.panel.find('button', (b) => txt(b).includes('Prever classificados'))[0];
  prevBtn.ev.click(); for (let k = 0; k < 6; k++) await null;
  const ptxt = txt(tab3.panel);
  print('preview=' + (ptxt.includes('Prévia — 1') && ptxt.includes('região SO') && ptxt.includes('Blocos e vagas')));
  print('no_null_text=' + !txt(tab3.panel).includes('null') + ',' + !txt(tab.panel).includes('null'));
  print('details=' + (all.includes('Representação geográfica') && all.includes('México') && all.includes('Lista de espera — 1') && all.includes('{"fractions_prev":{"no":0.3333}}')));
  print('awards=' + (all.includes('Prêmios (informativo)') && all.includes('Alfa (#1)') && all.includes('Campeones Brasileños')));
  // 2c) motor manual: o placar com "Promover" na linha; o motivo (opcional) abre na própria linha
  const MAN = { id:'manual', name:{pt:'Manual'}, stage:'proxima-fase', form:'manual', reason_optional:true, defaults:{name:'Próxima fase'} };
  const mstage = (rel) => ({ id:'seletiva', status:'draft', name:'Maratona SBC', chip:'SBC', config:{algorithm:'manual', slots:2},
    result:{ ranking:[{place:1, login:'alfa', team:'Alfa', univ:'UNB', total:3, penalty:6}, {place:2, login:'beta', team:'Beta', univ:'UNB', total:2, penalty:5},
      {place:3, login:'gama', team:'Gama', univ:'UNB', total:2, penalty:9}] }, relation:rel, overrides:[] });
  GET = { stages:[mstage([{login:'beta', team:'Beta', via:'manual', manual:true, override:'ov-1', reason:''}])], algorithms:[BR, MAN], vias:L, manual_vias:['manual','lista','reserva'] };
  POSTS.length = 0;
  const tab4 = makeClassifyTab('sel'); await tab4.load();
  const m = tab4.panel;
  print('man_count=' + m.find('b').map(txt).some((t) => t === 'Promovidos: 1 de 2'));
  const alfaRow = m.find('tr', (r) => txt(r).includes('Alfa') && txt(r).includes('UNB'))[0];
  print('beta_done=' + m.find('tr', (r) => txt(r).includes('Beta') && txt(r).includes('✓ promovido')).length);
  alfaRow.find('button', (b) => txt(b).includes('Promover'))[0].ev.click();
  const why = alfaRow.find('input')[0]; why.value = 'campeã da seletiva';
  alfaRow.find('button', (b) => txt(b) === '✔')[0].ev.click(); for (let k = 0; k < 4; k++) await null;
  print('post_man=' + JSON.stringify(POSTS[0]));
  print('man_form=' + m.find('label').map(txt).some((t) => t.startsWith('Quantos times serão promovidos')) + ',' + m.find('label').map(txt).some((t) => t.startsWith('Próxima fase')));
  // cheio: 2 de 2 ⇒ sem botão de promover
  GET = { stages:[mstage([{login:'beta', via:'manual', manual:true, override:'ov-1'}, {login:'alfa', via:'manual', manual:true, override:'ov-2'}])], algorithms:[BR, MAN], vias:L, manual_vias:['manual'] };
  const tab5 = makeClassifyTab('sel'); await tab5.load();
  print('full_btns=' + tab5.panel.find('button', (b) => txt(b).includes('⬆ Promover')).length + ',' + txt(tab5.panel).includes('todas as vagas preenchidas'));
  // 3) contest sem estágio: abre em "nova etapa" com o formulário BR
  GET = { stages:[], algorithms:[BR, JS_], vias:L, manual_vias:['manual'] };
  const tab2 = makeClassifyTab('cb'); await tab2.load();
  print('empty_sel=' + tab2.panel.find('select')[0].value + ' empty_ta=' + tab2.panel.find('textarea').length);
})().catch((e) => print("ERR=" + e + " @ " + (e.stack || "").split("\n").slice(0,3).join(" / ")));
JS
} > "$TD/t.js"
out="$(gjs "$TD/t.js" 2>&1)" || { echo "$out" >&2; echo "classify-tab: gjs falhou"; exit 1; }
[[ -z "${DEBUG:-}" ]] || echo "$out" >&2
kv(){ sed -n "s/^$1=//p" <<<"$out" | head -1; }
check "$(kv groups)" "Regra 1 — melhores gerais — 1|Regra 2 — vagas por sede — 0|Promoção manual (comitê) — 1|viaNova — 2" "grupos na ordem do estágio; retirado não conta; via sem rótulo pelo id"
check "$(kv ext_btns)" "✂" "time externo: só retirar"
check "$(kv post_ext)" '{"stage":"final-br","action":"withdraw","reason":"desistiu","ext":"lugia"}' "retirar time externo vai por ext"
check "$(kv manual_row)" true "linha manual com 🛠 e o motivo"
check "$(kv withdrawn_row)" true "linha retirada com ✂ e o motivo"
check "$(kv warn)" true "aviso do motor traduzido pelo código"
check "$(kv overrides_n)" "🛠 Overrides manuais — 3" "lista de overrides"
check "$(kv br_form)" 2 "motor BR: o formulário (sedes + supersedes)"
check "$(kv post1)" '{"stage":"final-br","action":"withdraw","reason":"desistiu","login":"teamsp01"}' "✂ = withdraw no estágio certo"
check "$(kv newid_empty)" true "nova etapa com os padrões já existentes: id em branco"
check "$(kv new_mode_no_actions)" true "modo nova etapa: sem ações de override"
check "$(kv json_seed)" true "motor sem formulário: editor JSON com a semente"
check "$(kv typed_kept)" nova1 "trocar o motor não apaga o id digitado"
check "$(kv collapsed_sel)" pda "id de estágio existente no modo nova etapa = esse estágio"
check "$(kv pda_json)" true "estágio sem motor leva o motor escolhido"
check "$(kv post2)" '{"stage":"pda","action":"add","via":"manual","reason":"regra 3","login":"teamsp02"}' "add vai p/ o estágio selecionado (não o anterior)"
check "$(kv next_btn)" true "motor com lista de espera: botão promover o próximo"
check "$(kv post3)" '{"stage":"pda","action":"promote_next","reason":"vaga do UTN"}' "promote_next com o motivo, no estágio"
check "$(kv preview)" true "prévia: avisos formatados, blocos"
check "$(kv no_null_text)" "true,true" "nenhum \"null\" na tela"
check "$(kv details)" true "detalhes: geo, lista de espera, frações p/ o ano seguinte"
check "$(kv awards)" true "detalhes: prêmios do Mundial (informativo)"
check "$(kv man_count)" true "manual: promovidos k de N"
check "$(kv beta_done)" 1 "manual: o promovido aparece marcado no placar"
check "$(kv post_man)" '{"stage":"seletiva","action":"add","login":"alfa","reason":"campeã da seletiva"}' "manual: promover pela linha, com o motivo do campo"
check "$(kv man_form)" "true,true" "manual: formulário com o nº de vagas e a próxima fase"
check "$(kv full_btns)" "0,true" "manual: vagas cheias = sem botão, com o aviso"
check "$(kv empty_sel)" "__new empty_ta=2" "sem estágio: abre em nova etapa com o formulário BR"
echo "classify-tab: $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
