#!/bin/bash
# smoke-sites-model.gjs.sh — o modelo do painel de sedes em três modos (web/contest/admin/sites-model.js):
#   • regra → regex no subconjunto seguro (rgNorm aceita), com escape do texto do usuário;
#   • ida e volta BYTE A BYTE: toSimple/fromSimple e toRules/fromRules reproduzem a regex de cada nó;
#   • `rule` velha (que não gera mais a regex do nó) é DESCARTADA — relê a regex ou o nó não cabe;
#   • o encaixe: badgetest cabe no Simples; grupos › sedes no Intermediário; recorte/subregião funda/regex
#     livre só no Avançado (e as árvores reais, com MOJ_REGIONS_EXTRA, idem);
#   • renomear sede reescreve as atribuições GRAVADAS com o nome velho e devolve o delta.
set -u
command -v gjs >/dev/null 2>&1 || { echo "sites-model: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
EXTRA='[]'
if [[ -n "${MOJ_REGIONS_EXTRA:-}" && -d "$MOJ_REGIONS_EXTRA" ]]; then
  EXTRA="$(for f in "$MOJ_REGIONS_EXTRA"/*.json; do jq -c --arg n "$(basename "$f" .json)" '{name:$n, tree:.}' "$f"; done | jq -cs .)"
fi
{ strip "$WEB/shared/regions-match.js"; strip "$WEB/contest/admin/sites-model.js"
  printf 'const EXTRA=%s;\n' "$EXTRA"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const J=(x)=>JSON.stringify(x);
// regra → regex
ck('começa/contém/termina/lista', ruleRegex({t:'starts',v:['ctba']})==='^ctba' && ruleRegex({t:'contains',v:['sp','rj']})==='(sp|rj)'
  && ruleRegex({t:'ends',v:'x9'})==='x9$' && ruleRegex({t:'list',v:'a1, b2'})==='^(a1|b2)$');
ck('várias regras: (r1)|(r2), cada uma ancorada', rulesRegex([{t:'starts',v:['a']},{t:'ends',v:['z']}])==='(^a)|(z$)');
ck('texto do usuário escapado e aceito pelo rgNorm', ruleRegex({t:'starts',v:['a.b(c)']})==='^a\\.b\\(c\\)' && rgNorm(ruleRegex({t:'starts',v:['a.b(c)']})).err===null);
ck('texto não-ASCII: ruleError diz non_ascii', ruleError({t:'starts',v:['são']})==='non_ascii');
// SIMPLES
const BADGE=[{name:'Curitiba',regex:'^ctba'},{name:'Porto Alegre',regex:'^poa'},{name:'Só nome'}];
ck('badgetest cabe no Simples', fitSimple(BADGE)==='' && simplestMode(BADGE)==='simple');
const S=toSimple(BADGE);
ck('toSimple: prefixos', J(S)===J([{name:'Curitiba',prefixes:['ctba']},{name:'Porto Alegre',prefixes:['poa']},{name:'Só nome',prefixes:[]}]));
const back=fromSimple(S);
ck('ida e volta Simples reproduz a regex byte a byte (e sede sem regex fica sem)', back[0].regex==='^ctba' && back[1].regex==='^poa' && back[2].regex===undefined);
ck('vários prefixos → ^(a|b) e volta', fromSimple([{name:'X',prefixes:'aa, bb'}])[0].regex==='^(aa|bb)' && J(toSimple(fromSimple([{name:'X',prefixes:'aa,bb'}]))[0].prefixes)===J(['aa','bb']));
ck('não cabe no Simples: recorte / subregião / regex livre / regra que não é prefixo',
  fitSimple([{name:'V',view:true}])==='has_view' && fitSimple([{name:'P',subregions:[{name:'S'}]}])==='has_subregions'
  && fitSimple([{name:'R',regex:'^team[0-9]'}])==='regex_free' && fitSimple([{name:'E',regex:'x$'}])==='rules_not_prefix');
// INTERMEDIÁRIO
const RT=[{name:'Sul',subregions:[{name:'Curitiba',regex:'^ctba'},{name:'POA',regex:'(^poa)|(rs$)'}]},{name:'Avulsa',regex:'^(t1|t2)$'}];
ck('grupos › sedes cabem no Intermediário (não no Simples)', fitRules(RT)==='' && fitSimple(RT)==='has_subregions' && simplestMode(RT)==='rules');
const M=toRules(RT);
ck('toRules: grupo, regras compostas e lista', M[0].group && M[0].sites[1].rules.length===2 && M[0].sites[1].rules[1].t==='ends' && M[1].rules[0].t==='list', J(M));
const RB=fromRules(M);
ck('ida e volta Intermediário reproduz TODAS as regex byte a byte', RB[0].subregions[0].regex==='^ctba' && RB[0].subregions[1].regex==='(^poa)|(rs$)' && RB[1].regex==='^(t1|t2)$', J(RB));
ck('não cabe no Intermediário: grupo com regex / 3 níveis / recorte',
  fitRules([{name:'G',regex:'^g',subregions:[{name:'s'}]}])==='group_regex' && fitRules([{name:'A',subregions:[{name:'B',subregions:[{name:'C'}]}]}])==='too_deep'
  && fitRules([{name:'V',view:true}])==='has_view');
// rule velha
const stale={name:'X', regex:'^novo', rule:[{t:'starts',v:['velho']}]};
ck('rule VELHA (não gera mais a regex) é descartada e a regex relida', J(nodeRules(stale))===J([{t:'starts',v:['novo']}]));
ck('rule velha + regex que não relê: o nó não cabe', nodeRules({name:'X',regex:'^a[0-9]',rule:[{t:'starts',v:['a']}]})===null);
// renomear
const explicit=new Map([['t1','Curitiba'],['t2','curitiba '],['t3','POA']]), pending=new Map([['t4','Curitiba']]);
const moved=renameAssignments(explicit, pending, 'Curitiba', 'CWB');
ck('renomear: gravadas (caixa/espaço não importam) e pendentes passam p/ o nome novo; o delta diz quem', J(moved.sort())===J(['t1','t2','t4']) && pending.get('t1')==='CWB' && pending.get('t4')==='CWB' && !pending.has('t3'));
// árvores reais (fora do repo)
EXTRA.forEach((x)=>ck('real '+x.name+': só no Avançado (motivo '+fitSimple(x.tree)+'/'+fitRules(x.tree)+')', simplestMode(x.tree)==='tree'));
print(''); print('RESULT: '+pass+' passed, '+fail+' failed'); imports.system.exit(fail>0?1:0);
EOF
} > "$JS"
gjs "$JS"
