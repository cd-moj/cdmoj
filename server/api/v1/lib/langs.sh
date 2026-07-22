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

# effective_problem_langs <contest> <problem_id> -> array JSON ([] = todas as linguagens).
# Cadeia mais-específico-vence (a MESMA da listagem do contest):
#   1. override por-problema no contest (problem-langs.json)
#   2. whitelist do contest (LANGUAGES do conf)
#   3. default do PACOTE (var/jsons{,-private}/<id>.json .languages)
#   4. [] = todas (sem restrição)
# O conf é sourced em SUBSHELL (não vaza globais p/ o handler chamador).
effective_problem_langs(){
  local contest="$1" pid="$2" plangs="" clangs="" pjf
  plangs="$(jq -c --arg id "$pid" '.[$id] // empty' "$CONTESTSDIR/$contest/problem-langs.json" 2>/dev/null)"
  if [[ -n "$plangs" && "$plangs" != null ]]; then printf '%s' "$plangs"; return 0; fi
  clangs="$( ( LANGUAGES=""
               load_contest_conf "$contest" >/dev/null 2>&1
               [[ -n "$LANGUAGES" ]] && printf '%s\n' $LANGUAGES | grep -v '^$' | jq -R . | jq -cs . ) 2>/dev/null)"
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
  [[ -z "$langs" || "$langs" == '[]' || "$langs" == null ]] && return 0
  c="$(_lang_canon "$ext")"
  jq -e --arg c "$c" 'map( ascii_downcase
      | (if .=="c++" or .=="cc" or .=="cxx" or .=="hpp" then "cpp"
         elif .=="h" then "c"
         elif .=="py3" or .=="py2" then "py" else . end) )
    | (index($c) != null)' >/dev/null 2>&1 <<<"$langs"
}
