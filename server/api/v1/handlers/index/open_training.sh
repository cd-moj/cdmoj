# GET /index/open_training
# Do contests/treino/controle/history monta:
#   top_users (top10 por nº de problemas resolvidos, Accepted distinto por problema),
#   recent_solved (últimos 5 Accepted), most_solved_week (mais resolvidos desde domingo).
# -> {success:true, top_users, recent_solved, most_solved_week, search_problems_url}
emit_json 200 OK
set +o noglob

TREINO="$CONTESTSDIR/treino"
HIST="$TREINO/controle/history"
QDIR="$TREINO/var/questoes"

if [[ ! -f "$HIST" ]]; then
  jq -cn '{success:true, top_users:[], recent_solved:[], most_solved_week:[], search_problems_url:"/treino"}'
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
  name="$(awk -F: -v u="$user" '$1==u{print $3; exit}' "$TREINO/passwd")"
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

# --- top_users: top10 por problemas distintos resolvidos -------------------
declare -a U
while read -r total user; do
  [[ -z "$user" ]] && continue
  name="$(awk -F: -v u="$user" '$1==u{print $3; exit}' "$TREINO/passwd")"
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
  '{success:true, top_users:$top_users, recent_solved:$recent_solved,
    most_solved_week:$most_solved_week, search_problems_url:"/treino"}'
