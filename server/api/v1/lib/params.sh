# lib/params.sh — parse QUERY_STRING em PARAMS[] (URL-decoded).
declare -A PARAMS
# dieta 2026-08-30: o decode era `PARAMS[$(urldecode k)]=$(urldecode v)` — 2 forks POR
# PARÂMETRO em TODA requisição. printf -v decodifica na variável, zero processos.
_urld_to() { local -n _o="$1"; local s="${2//+/ }"; printf -v _o '%b' "${s//%/\\x}"; }
_parse_query() {
  local q="$1" pair k v dk dv IFS='&'
  for pair in $q; do
    [[ -z "$pair" ]] && continue
    if [[ "$pair" == *=* ]]; then k="${pair%%=*}"; v="${pair#*=}"; else k="$pair"; v=""; fi
    _urld_to dk "$k"; _urld_to dv "$v"
    PARAMS["$dk"]="$dv"
  done
}
_parse_query "${QUERY_STRING:-}"
param(){ printf '%s' "${PARAMS[$1]:-}"; }
