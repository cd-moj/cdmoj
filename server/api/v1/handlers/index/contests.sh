# GET /index/contests?page=N
# Varre contests/*/conf e classifica por CONTEST_START/END vs agora:
#   open (start<=now<end), upcoming (start>now), closed (end<=now, paginado, 20/pág).
# -> {success:true, open:[...], upcoming:[...], closed:{items,page,per_page,total}}
emit_json 200 OK
set +o noglob

PAGE="$(param page)"; [[ "$PAGE" =~ ^[0-9]+$ ]] || PAGE=1
(( PAGE < 1 )) && PAGE=1
PERPAGE=20
# all=1 -> devolve TODOS os encerrados (sem paginar). Usado pela página de arquivo
# (/contests/) p/ navegar o histórico completo, que na home vinha truncado em 20.
ALL="$(param all)"; ALLMODE=0
case "$ALL" in 1|true|all) ALLMODE=1;; esac
NOW="$EPOCHSECONDS"

# Para cada contest emite "<start> <status> <json>" (status: r/u/e). Pula treino e *.admin.
LINES="$(
  for d in "$CONTESTSDIR"/*/; do
    c="${d%/}"; id="${c##*/}"
    [[ "$id" == treino ]] && continue
    [[ -f "$c/conf" ]] || continue
    (
      CONTEST_START=""; CONTEST_END=""; CONTEST_NAME=""; PROBS=()
      source "$c/conf" 2>/dev/null
      [[ -n "$CONTEST_START" && -n "$CONTEST_END" ]] || exit 0
      if   (( CONTEST_END   <= NOW )); then st=e
      elif (( CONTEST_START >  NOW )); then st=u
      else st=r; fi
      obj="$(jq -cn --arg id "$id" --arg title "$CONTEST_NAME" \
        --argjson start "$CONTEST_START" --argjson end "$CONTEST_END" \
        --argjson pcount "$(( ${#PROBS[@]} / 5 ))" \
        --arg url "/contest/?c=$id" --arg score "/contest/score/?c=$id" \
        '{id:$id, title:$title, start_time:$start, end_time:$end,
          problems_count:$pcount, url:$url, scoreboard_url:$score}')"
      printf '%s\t%s\t%s\n' "$CONTEST_START" "$st" "$obj"
    )
  done | sort -t$'\t' -k1,1rn
)"

# separa por status; closed paginado em memória
declare -a OPEN UP CLOSED
while IFS=$'\t' read -r start st obj; do
  [[ -z "$st" ]] && continue
  case "$st" in
    r) OPEN+=("$obj");;
    u) UP+=("$obj");;
    e) CLOSED+=("$obj");;
  esac
done <<< "$LINES"

TOTAL="${#CLOSED[@]}"
(( ALLMODE )) && { PAGE=1; PERPAGE=$TOTAL; }
FROM=$(( (PAGE-1) * PERPAGE ))
declare -a CPAGE
for (( i=FROM; i<FROM+PERPAGE && i<TOTAL; i++ )); do CPAGE+=("${CLOSED[$i]}"); done

jarr(){ if (( $# == 0 )); then printf '[]'; else printf '%s\n' "$@" | jq -cs .; fi; }

jq -cn \
  --argjson open "$(jarr "${OPEN[@]}")" \
  --argjson upcoming "$(jarr "${UP[@]}")" \
  --argjson items "$(jarr "${CPAGE[@]}")" \
  --argjson page "$PAGE" --argjson per_page "$PERPAGE" --argjson total "$TOTAL" \
  '{success:true, open:$open, upcoming:$upcoming,
    closed:{items:$items, page:$page, per_page:$per_page, total:$total}}'
