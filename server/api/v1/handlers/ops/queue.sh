# GET /ops/queue   (Bearer, admin) -> JSON
# Tamanho da fila por contest: conta arquivos de spool em $SPOOLDIR cujo nome é
# <contest>:<time>:...  Ignora temporários (.in.*). (substitui o /onqueue do bot)
require_admin

emit_json 200 OK
set +o noglob

declare -A COUNT
total=0
if [[ -d "$SPOOLDIR" ]]; then
  shopt -s nullglob
  for f in "$SPOOLDIR"/*; do
    base="${f##*/}"
    [[ "$base" == .* || "$base" == .in.* ]] && continue
    [[ "$base" == *:* ]] || continue
    c="${base%%:*}"
    COUNT["$c"]=$(( ${COUNT["$c"]:-0} + 1 ))
    (( total++ ))
  done
  shopt -u nullglob
fi

# monta {contest: n, ...}
if (( ${#COUNT[@]} == 0 )); then
  perc='{}'
else
  perc="$(for c in "${!COUNT[@]}"; do
            jq -cn --arg c "$c" --argjson n "${COUNT[$c]}" '{($c): $n}'
          done | jq -cs 'add')"
fi

jq -cn --argjson by "$perc" --argjson total "$total" \
  '{success:true, total:$total, by_contest:$by}'
