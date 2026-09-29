#!/bin/bash
# smoke-score-regions.gjs.sh — o filtro de SEDE do placar ao vivo e da participação virtual
# (web/contest/score/score-filters.js) usa a regra única de sedes (web/shared/regions-match.js):
#   • o time está no nó pela sede GRAVADA (t._region) ou pela regex mais funda; pai = soma dos filhos
#     (antes: a regex do próprio nó OU o nome gravado — o país sem regex não via ninguém);
#   • sede gravada fora da árvore vira opção no fim (órfã) e fica pendurada no nó da regex;
#   • a sede guardada no navegador ({name, regex CRUA}) é resolvida p/ a opção (regex normalizada);
#   • sede guardada sem opção correspondente cai no casamento antigo (nunca some o filtro calado);
#   • 2000 times × ~200 nós: a pertença é calculada UMA vez (memo) — renderizar de novo é barato.
set -u
command -v gjs >/dev/null 2>&1 || { echo "score-regions: gjs ausente — pulando"; exit 0; }
WEB="$(cd "$(dirname "$(readlink -f "$0")")/../../web" && pwd)"
strip(){ sed -E '/^import /d; s/^export (async )?(function|const|let|class) /\1\2 /; /^export \{/d' "$1"; }
JS="$(mktemp --suffix=.js)"; trap 'rm -f "$JS"' EXIT
{ echo 'function flagName(c){ return c; }'
  strip "$WEB/shared/regions-match.js"; strip "$WEB/contest/score/score-filters.js"
  cat <<'EOF'
let pass=0, fail=0; const ck=(m,ok,d)=>{ if (ok) { print('  ok: '+m); pass++; } else { print('  FAIL: '+m+' :: '+(d||'')); fail++; } };
const TREE=[{name:'Brasil',subregions:[{name:'Sudeste',regex:'^team(sp|rj)',subregions:[{name:'SP',regex:'^teamsp\\d'},{name:'RJ',regex:'^teamrj'}]},{name:'DF'}]},
            {name:'Femininos',view:true,regex:'^teamsp01$'},{name:'Argentina',regex:'^teamar'}];
const teams=[{username:'teamsp01'},{username:'teamsp02'},{username:'teamrj01'},{username:'teambsb1',_region:'df'},{username:'teamar1',_region:'Córdoba'},{username:'outro'}];
const rops=regionOptions(TREE, teams);
const opt=(n)=>rops.find((o)=>o.name===n);
const who=(n)=>teams.filter((t)=>regionMatch(t, opt(n))).map((t)=>t.username).join(',');
ck('opções = a árvore em pré-ordem + a órfã no fim', rops.map((o)=>o.name).join('|')==='Brasil|Sudeste|SP|RJ|DF|Femininos|Argentina|Córdoba', rops.map((o)=>o.name).join('|'));
ck('Brasil (SEM regex) soma os filhos: SP, RJ e DF (gravada "df")', who('Brasil')==='teamsp01,teamsp02,teamrj01,teambsb1', who('Brasil'));
ck('Sudeste = SP + RJ; SP pela regex \\\\d normalizada', who('Sudeste')==='teamsp01,teamsp02,teamrj01' && who('SP')==='teamsp01,teamsp02', who('SP'));
ck('recorte Femininos pela regex', who('Femininos')==='teamsp01');
ck('órfã "Córdoba" (gravada fora da árvore) pendura na Argentina (regex)', who('Córdoba')==='teamar1' && who('Argentina')==='teamar1', who('Argentina'));
const saved={name:'SP', regex:'^teamsp\\d'};                                   // regex CRUA, como ficou no localStorage
const r=regionResolve(rops, saved);
ck('sede guardada com a regex crua é resolvida p/ a opção (com a pertença)', r && r.name==='SP' && r._mem instanceof Set && r._mem.has('teamsp02'));
const gone={name:'Sumiu', regex:'^teamrj'};
ck('sede guardada sem opção: regionResolve null e o casamento antigo (regex) segue valendo', regionResolve(rops, gone)===null && regionMatch({username:'teamrj01'}, gone) && !regionMatch({username:'teamsp01'}, gone));
ck('rowFilter com a opção filtra por pertença', teams.filter(rowFilter({region: opt('Brasil')})).length===4);
// custo: 2000 times × ~200 nós — o memo faz a 2ª chamada ser de graça
const BIG=[]; for (let p=0;p<20;p++) BIG.push({name:'P'+p, regex:'^t'+p+'x', subregions:[...Array(9).keys()].map((s)=>({name:'P'+p+'-'+s, regex:'^t'+p+'x'+s}))});
const bt=[]; for (let i=0;i<2000;i++) bt.push({username:'t'+(i%20)+'x'+(i%9)+'_'+i});
let t0=Date.now(); const o1=regionOptions(BIG, bt); const dt1=Date.now()-t0;
t0=Date.now(); const o2=regionOptions(BIG, bt); const dt2=Date.now()-t0;
ck('2000 times × 200 nós: 1ª vez em '+dt1+' ms (< 1500), a 2ª (memo) em '+dt2+' ms (< 50)', dt1<1500 && dt2<50 && o1.length===200 && o1[0]._mem.size===100, dt1+'/'+dt2);
print(''); print('RESULT: '+pass+' passed, '+fail+' failed'); imports.system.exit(fail>0?1:0);
EOF
} > "$JS"
gjs "$JS"
