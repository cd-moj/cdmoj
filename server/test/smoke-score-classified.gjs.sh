#!/bin/bash
# smoke-score-classified.gjs.sh — chips de classificação do placar ao vivo (web/contest/score/score-classified.js):
# um chip POR ESTÁGIO (o time na Final BR e na PDA mostra os dois), texto do servidor (chip + rótulo curto da
# via no idioma da interface), via sem rótulo aparece pelo id (nunca some), `ext:` filtrado, rascunho marcado.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
W="$ROOT/web"; TD="$(mktemp -d)"; trap 'rm -rf "$TD"' EXIT
command -v gjs >/dev/null 2>&1 || { echo "score-classified: gjs ausente — pulando"; exit 0; }
PASS=0; FAIL=0
check(){ if [[ "$1" == "$2" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: $3 (got '$1', want '$2')" >&2; fi; }
for L in pt es; do
  { printf "let LANG = '%s';\n" "$L"
    cat <<'JS'
function T(pt, en, es) { if (LANG === 'es') return es != null ? es : (en != null ? en : pt); if (LANG === 'en') return en != null ? en : pt; return pt; }
JS
    sed '/^import /d; s/^export //' "$W/contest/score/score-classified.js"
    cat <<'JS'
const lab = { regra1: { pt: 'Regra 1 — melhores gerais', en: 'Rule 1', es: 'Regla 1', short: { pt: 'regra 1', en: 'rule 1', es: 'regla 1' } },
              p1: { pt: 'Desempenho', en: 'Performance', es: 'Desempeño' } };
const resp = { stages: [
  { id: 'final-br', name: 'Final Brasileira', venue: 'Uberlândia', when: 'nov', chip: 'Final BR', labels: lab,
    teams: { teamsp01: { via: 'regra1', sede: 'SP' }, teamrj01: { via: 'viaNova', sede: '' } } },
  { id: 'pda', name: 'Campeonato LATAM', chip: 'PDA', labels: lab, draft: true,
    teams: { teamsp01: { via: 'p1', sede: '' }, 'ext:lugia': { via: 'manual' } } } ] };
const m = classifiedMap(resp);
print('n_sp01=' + m.teamsp01.length);
print('chips=' + m.teamsp01.map((c) => c.chip).join('|'));
print('via0=' + m.teamsp01[0].via);
print('via1=' + m.teamsp01[1].via);
print('draft1=' + m.teamsp01[1].draft + ' draft0=' + m.teamsp01[0].draft);
print('stage0=' + m.teamsp01[0].stage);
print('unknown=' + m.teamrj01[0].via);
print('ext=' + (m['ext:lugia'] ? 'sim' : 'nao'));
print('vazio=' + classifiedMap({ stages: [] }) + ' nulo=' + classifiedMap(null));
JS
  } > "$TD/c-$L.js"
  out="$(gjs "$TD/c-$L.js" 2>&1)" || { echo "$out" >&2; echo "score-classified: gjs falhou"; exit 1; }
  kv(){ sed -n "s/^$1=//p" <<<"$out" | head -1; }
  check "$(kv n_sp01)" 2 "[$L] um chip por estágio"
  check "$(kv chips)" "Final BR|PDA" "[$L] chip vem do servidor"
  check "$(kv unknown)" viaNova "[$L] via sem rótulo aparece pelo id"
  check "$(kv ext)" nao "[$L] ext: filtrado"
  check "$(kv vazio)" "null nulo=null" "[$L] sem estágio = null"
  check "$(kv draft1)" "true draft0=false" "[$L] rascunho por estágio"
  check "$(kv stage0)" "Final Brasileira, Uberlândia — nov" "[$L] tooltip do estágio"
  if [[ "$L" == pt ]]; then
    check "$(kv via0)" "regra 1" "[pt] rótulo CURTO"; check "$(kv via1)" "Desempenho" "[pt] rótulo sem short"
  else
    check "$(kv via0)" "regla 1" "[es] rótulo curto em espanhol"; check "$(kv via1)" "Desempeño" "[es] rótulo sem short em espanhol"
  fi
done
echo "score-classified: $PASS ok, $FAIL falhas"; [[ $FAIL -eq 0 ]]
