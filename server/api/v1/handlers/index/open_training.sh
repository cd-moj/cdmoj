# GET /index/open_training
# Do history do treino (users/*/history) monta:
#   top_users (top10 por nº de problemas resolvidos, Accepted distinto por problema),
#   recent_solved (últimos 5 Accepted), most_solved_week (mais resolvidos desde domingo).
# -> {success:true, top_users, recent_solved, most_solved_week, search_problems_url}
emit_json 200 OK
set +o noglob

TREINO="$CONTESTSDIR/treino"
QDIR="$TREINO/var/questoes"

# materializa o history no formato global (7 campos) num temp — toda a lógica abaixo
# (grep/awk sobre $HIST) opera no stream fanned-out de users/*/history.
HIST="$(mktemp)"; trap '[[ -n "$HIST" ]] && rm -f "$HIST"' EXIT
emit_history_stream treino > "$HIST"

if [[ ! -s "$HIST" ]]; then
  jq -cn '{success:true, top_users:[], recent_solved:[], most_solved_week:[], most_solved_prev_week:[], most_used_editor_prev_week:{top:null,total:0,ranking:[]}, search_problems_url:"/treino"}'
  exit 0
fi

_title(){ # título do problema (probid usa '#'); fallback = o próprio id
  local p="$1"
  [[ -f "$QDIR/$p/title" ]] && { cat "$QDIR/$p/title"; return; }
  printf '%s' "${p/\#/.}"
}

# --- recent_solved: últimos 5 Accepted (mais recentes primeiro) -----------
declare -a V
while IFS=: read -r relat user prob lang resp epoch md5; do
  [[ -z "$user" ]] && continue
  name="$(user_fullname_of treino "$user")"
  V+=( "$(jq -cn --arg pid "$prob" --arg title "$(_title "$prob")" \
      --arg user "$user" --arg name "$name" --argjson at "${epoch:-0}" \
      --arg url "/treino/problema/?id=${prob//\#/%23}" \
      '{problem_id:$pid, problem_title:$title,
        user:{username:$user, name:$name}, solved_at:$at, url:$url}')" )
done <<< "$(grep -F 'Accepted' "$HIST" | tail -n5 | tac)"

# --- most_solved_week: por problema, submissões desde o último domingo -----
LASTWEEK="$(date --date='last-sunday' +%s 2>/dev/null || echo 0)"
declare -a R
while read -r total prob; do
  [[ -z "$prob" ]] && continue
  R+=( "$(jq -cn --arg pid "$prob" --arg title "$(_title "$prob")" \
      --argjson n "$total" --arg url "/treino/problema/?id=${prob//\#/%23}" \
      '{problem_id:$pid, problem_title:$title, solved_count:$n, url:$url}')" )
done <<< "$(awk -F: -v s="$LASTWEEK" '$6>=s && $5 ~ /Accepted/ {print $3}' "$HIST" \
            | sort | uniq -c | sort -rn | head -n5 | awk '{print $1, $2}')"

# --- most_solved_prev_week: RESOLVEDORES distintos por problema na SEMANA PASSADA
# (janela [domingo retrasado, último domingo) ). Cada usuário conta 1x por problema.
PREVSTART=$(( LASTWEEK > 0 ? LASTWEEK - 604800 : 0 ))
declare -a RP
while read -r total prob; do
  [[ -z "$prob" ]] && continue
  RP+=( "$(jq -cn --arg pid "$prob" --arg title "$(_title "$prob")" \
      --argjson n "$total" --arg url "/treino/problema/?id=${prob//\#/%23}" \
      '{problem_id:$pid, problem_title:$title, solved_count:$n, url:$url}')" )
done <<< "$(awk -F: -v ps="$PREVSTART" -v ws="$LASTWEEK" \
            '$6>=ps && $6<ws && $5 ~ /Accepted/ { k=$3 SUBSEP $2; if(!(k in seen)){seen[k]=1; cnt[$3]++} }
             END{ for(p in cnt) print cnt[p], p }' "$HIST" \
            | sort -rn | head -n5)"

# --- most_used_editor_prev_week: editor mais usado nas submissões ACEITAS da semana
# passada. var/editor-log = epoch:subid:login:editor; casa o subid com o aceito do
# history (web -> "web"; arquivo -> editor declarado). Só tem dado a partir de agora.
EDLOG="$TREINO/var/editor-log"
EDITOR_RANK="$(
  { [[ -s "$EDLOG" ]] && awk -F: -v ps="$PREVSTART" -v ws="$LASTWEEK" '
      FNR==NR { ed[$2]=$4; next }                              # editor-log: subid -> editor
      $6>=ps && $6<ws && $5 ~ /Accepted/ { sid=$7; if(sid in ed) cnt[ed[sid]]++ }
      END { for(e in cnt) printf "%s\t%d\n", e, cnt[e] }' "$EDLOG" "$HIST" 2>/dev/null \
      | sort -t$'\t' -k2,2rn; true; } \
  | jq -R -s 'split("\n") | map(select(length>0) | split("\t") | {editor:.[0], count:(.[1]|tonumber)})'
)"
[[ -n "$EDITOR_RANK" ]] || EDITOR_RANK='[]'

# --- top_users: top10 por problemas distintos resolvidos -------------------
declare -a U
while read -r total user; do
  [[ -z "$user" ]] && continue
  name="$(user_fullname_of treino "$user")"
  read_profile treino "$user"
  U+=( "$(jq -cn --arg user "$user" --arg name "$name" --arg fe "$FAVORITE_EDITOR" --argjson n "$total" \
      '{username:$user, name:$name, favorite_editor:$fe, solved_count:$n}')" )
done <<< "$(awk -F: '$5 ~ /Accepted/ {print $2 ":" $3}' "$HIST" \
            | sort -u | cut -d: -f1 | sort | uniq -c | sort -rn | head -n10 \
            | awk '{print $1, $2}')"

jarr(){ if (( $# == 0 )); then printf '[]'; else printf '%s\n' "$@" | jq -cs .; fi; }

jq -cn \
  --argjson top_users "$(jarr "${U[@]}")" \
  --argjson recent_solved "$(jarr "${V[@]}")" \
  --argjson most_solved_week "$(jarr "${R[@]}")" \
  --argjson most_solved_prev_week "$(jarr "${RP[@]}")" \
  --argjson editor_rank "$EDITOR_RANK" \
  '{success:true, top_users:$top_users, recent_solved:$recent_solved,
    most_solved_week:$most_solved_week, most_solved_prev_week:$most_solved_prev_week,
    most_used_editor_prev_week: ($editor_rank | {top:(.[0] // null), total:(map(.count)|add // 0), ranking:.}),
    search_problems_url:"/treino"}'
