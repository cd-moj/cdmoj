# lib/params.sh — parse QUERY_STRING em PARAMS[] (URL-decoded).
declare -A PARAMS
_parse_query() {
  local q="$1" pair k v IFS='&'
  for pair in $q; do
    [[ -z "$pair" ]] && continue
    if [[ "$pair" == *=* ]]; then k="${pair%%=*}"; v="${pair#*=}"; else k="$pair"; v=""; fi
    PARAMS["$(urldecode "$k")"]="$(urldecode "$v")"
  done
}
_parse_query "${QUERY_STRING:-}"
param(){ printf '%s' "${PARAMS[$1]:-}"; }
