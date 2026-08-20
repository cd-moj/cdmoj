# lib/langs.sh — whitelist de LINGUAGENS de um problema: resolução da cadeia + canonicalização.
# FONTE ÚNICA: a listagem (/contest/problems) e o ENFORCEMENT (/submit, /contest/offline-submit)
# usam as MESMAS funções — se divergirem, a UI oferece o que a API recusa (ou vice-versa).
# A whitelist é FORÇADA pela API (regra da casa: acesso é da API, nunca só da interface);
# o filtro do dropdown na web é só conveniência.

# _lang_canon <token> -> id canônico minúsculo (mesma tabela do acervo: problem-stats,
# write_meta): variantes de C++ fundem em cpp, H em c, PY3/PY2 legado em py.
_lang_canon(){ local t; t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    c++|cc|cxx|hpp) printf 'cpp';;
    h)              printf 'c';;
    py3|py2)        printf 'py';;
    *)              printf '%s' "$t";;
  esac; }

# PLATFORM_LANGS — as linguagens que a PLATAFORMA roda (espelho de mojtools/lang/, menos o
# alias py3). É o CHÃO da whitelist: lista efetiva vazia significa "estas", nunca "qualquer
# extensão" — foi assim que um `.exe` (binário!) entrou na fila e ficou pendente para sempre
# (incidente 2026-08-19). Linguagem exótica continua possível: o problema/contest declara
# `languages` EXPLÍCITO (com o toolchain no pacote), e lista explícita é soberana.
: "${PLATFORM_LANGS:=apl c cpp cs go hs java js kt ml pas pl py riscv rs sh spim}"
platform_langs_json(){ printf '%s\n' $PLATFORM_LANGS | jq -R . | jq -cs .; }

# effective_problem_langs <contest> <problem_id> -> array JSON ([] = PLATFORM_LANGS p/ o
# enforcement; a listagem também trata [] como "as da plataforma").
# Cadeia mais-específico-vence (a MESMA da listagem do contest):
#   1. override por-problema no contest (problem-langs.json)
#   2. whitelist do contest (LANGUAGES do conf)
#   3. default do PACOTE (var/jsons{,-private}/<id>.json .languages)
#   4. [] = as linguagens da plataforma (PLATFORM_LANGS)
# O conf é sourced em SUBSHELL (não vaza globais p/ o handler chamador).
# memória POR REQUISIÇÃO: o override do contest e a whitelist do conf são os MESMOS para todos
# os problemas, mas a função era chamada dentro do laço do /contest/problems — relia o arquivo e
# re-sourceava o conf 12 vezes (3 processos por problema). O cache vive só neste processo, então
# não há invalidação a fazer: a próxima requisição relê.
declare -gA _EPL=()
effective_problem_langs(){
  local contest="$1" pid="$2" plangs="" clangs="" pjf
  if [[ -z "${_EPL[pj:$contest]+x}" ]]; then
    _EPL[pj:$contest]="$(<"$CONTESTSDIR/$contest/problem-langs.json")" 2>/dev/null || _EPL[pj:$contest]='{}'
    [[ -n "${_EPL[pj:$contest]}" ]] || _EPL[pj:$contest]='{}'
    _EPL[cl:$contest]="$( ( LANGUAGES=""
               load_contest_conf "$contest" >/dev/null 2>&1
               [[ -n "$LANGUAGES" ]] && printf '%s\n' $LANGUAGES | grep -v '^$' | jq -R . | jq -cs . ) 2>/dev/null)"
  fi
  plangs="$(jq -c --arg id "$pid" '.[$id] // empty' <<<"${_EPL[pj:$contest]}" 2>/dev/null)"
  if [[ -n "$plangs" && "$plangs" != null ]]; then printf '%s' "$plangs"; return 0; fi
  clangs="${_EPL[cl:$contest]}"
  if [[ -n "$clangs" && "$clangs" != '[]' ]]; then printf '%s' "$clangs"; return 0; fi
  pjf="$CONTESTSDIR/treino/var/jsons/$pid.json"
  [[ -f "$pjf" ]] || pjf="$CONTESTSDIR/treino/var/jsons-private/$pid.json"
  plangs="$(jq -c '.languages // []' "$pjf" 2>/dev/null)"
  [[ -n "$plangs" && "$plangs" != null ]] || plangs='[]'
  printf '%s' "$plangs"
}

# lang_allowed <langs-json-array> <ext-ou-FILETYPE> -> 0 se permitido ([]/vazio = todas).
# Compara CANÔNICO dos dois lados: x.py3 passa em ["py"]; ids exóticos comparam literal.
lang_allowed(){
  local langs="$1" ext="$2" c
  # lista vazia = o CHÃO da plataforma (nunca "qualquer extensão" — ver PLATFORM_LANGS acima)
  [[ -z "$langs" || "$langs" == '[]' || "$langs" == null ]] && langs="$(platform_langs_json)"
  c="$(_lang_canon "$ext")"
  jq -e --arg c "$c" 'map( ascii_downcase
      | (if .=="c++" or .=="cc" or .=="cxx" or .=="hpp" then "cpp"
         elif .=="h" then "c"
         elif .=="py3" or .=="py2" then "py" else . end) )
    | (index($c) != null)' >/dev/null 2>&1 <<<"$langs"
}
