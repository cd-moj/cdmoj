# GET /treino/problem-stats?id=<problemid>
# Estatísticas de submissão de UM problema do treino: métricas gerais, distribuição de
# veredictos, por-linguagem (submissões/aceitos/solvers distintos), editores declarados
# pelos solvers, e a lista de avatares de solvers com perfil público.
# Resultado é CACHEADO em var/problem-stats/<id>.json (TTL PROBLEM_STATS_TTL_MIN).
id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing problem id" "id_missing"
valid_id "$id" || fail 400 "Invalid problem id" "id_invalid"
T="$CONTESTSDIR/treino"
[[ -f "$T/var/jsons/$id.json" ]] || fail 404 "Problem not found" "problem_notfound"

CACHE="$T/var/problem-stats/$id.json"
# cache no servidor (TTL), mas no navegador sempre revalida (evita resposta velha)
printf 'Status: 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-cache, must-revalidate\r\n\r\n'
if [[ -f "$CACHE" ]] && [[ -z "$(find "$CACHE" -mmin +"${PROBLEM_STATS_TTL_MIN:-10}" 2>/dev/null)" ]]; then
  cat "$CACHE"; exit 0
fi

set +o noglob
PASSWD="$T/passwd"
title="$(jq -r '.title // ""' "$T/var/jsons/$id.json" 2>/dev/null)"

# linhas do problema (campo 3 == id). Pode ser vazio. emit_history_stream unifica store-v2/legado.
plines="$(emit_history_stream treino | awk -F: -v p="$id" '$3==p' 2>/dev/null)"

core="$(printf '%s\n' "$plines" | jq -R 'select(length>0)|split(":")|{user:(.[1]//""), lang:(.[3]//"?"), verdict:(.[4]//"")}' \
  | jq -s '
      def vc: if startswith("Accepted") then "Accepted"
              elif startswith("Wrong") then "Wrong Answer"
              elif startswith("Time Limit") then "Time Limit Exceeded"
              elif (startswith("Runtime") or startswith("Possible Runtime")) then "Runtime Error"
              elif (startswith("Compilation") or startswith("Language")) then "Compilation Error"
              else "Outro" end;
      # canonicaliza a linguagem: minúsculas + sem espaços, e funde variantes
      # equivalentes (CPP/C++/CC/CXX/HPP -> cpp, H -> c) para não duplicar linha.
      def canon: (ascii_upcase | gsub("\\s";"")) as $u
        | ({"C++":"cpp","CC":"cpp","CXX":"cpp","HPP":"cpp","H":"c"}[$u]) // ($u | ascii_downcase);
      (map(.lang |= canon)) as $s
      | ($s|length) as $total
      | ($s|map(.user)|unique) as $att
      | ($s|map(select(.verdict|startswith("Accepted"))|.user)|unique) as $solv
      | {
          total_submissions: $total,
          distinct_attempted: ($att|length),
          distinct_solved: ($solv|length),
          acceptance_rate: (if $total>0 then (($s|map(select(.verdict|startswith("Accepted")))|length)/$total) else 0 end),
          avg_submissions_per_user: (if ($att|length)>0 then ($total/($att|length)) else 0 end),
          verdicts: ($s|map(.verdict|vc)|group_by(.)|map({verdict:.[0], count:length})|sort_by(-.count)),
          by_language: ($s|group_by(.lang)|map({
              lang:.[0].lang, submissions:length,
              accepted:(map(select(.verdict|startswith("Accepted")))|length),
              solvers:(map(select(.verdict|startswith("Accepted"))|.user)|unique|length)
            })|sort_by(-.submissions)),
          solvers: $solv
        }')"

# editores declarados pelos solvers + avatares de quem é público
declare -A EDC; declare -a AV; pubcount=0
while IFS= read -r u; do
  [[ -z "$u" ]] && continue
  pf="$T/var/profiles/$u.json"; fe=""; pub=1
  if [[ -f "$pf" ]]; then
    fe="$(jq -r '.favorite_editor // ""' "$pf" 2>/dev/null)"
    [[ "$(jq -r 'if .public==false then "n" else "y" end' "$pf" 2>/dev/null)" == "n" ]] && pub=0
  fi
  [[ -n "$fe" ]] && EDC["$fe"]=$(( ${EDC["$fe"]:-0} + 1 ))
  if (( pub )); then
    ((pubcount++))
    if (( ${#AV[@]} < 200 )); then
      nm="$(awk -F: -v x="$u" '$1==x{print $3; exit}' "$PASSWD")"
      hp="$([[ -f "$T/var/profiles/$u.png" ]] && echo true || echo false)"
      AV+=("$(jq -cn --arg l "$u" --arg n "$nm" --argjson hp "$hp" '{login:$l, name:$n, has_photo:$hp}')")
    fi
  fi
done < <(jq -r '.solvers[]?' <<<"$core")

edjson="$(for k in "${!EDC[@]}"; do jq -cn --arg e "$k" --argjson c "${EDC[$k]}" '{editor:$e, count:$c}'; done | jq -cs 'sort_by(-.count)')"
[[ -z "$edjson" ]] && edjson='[]'
avjson="$( ((${#AV[@]})) && printf '%s\n' "${AV[@]}" | jq -cs '.' || echo '[]')"

mkdir -p "$T/var/problem-stats"
jq -n --arg id "$id" --arg title "$title" --argjson core "$core" \
   --argjson editors "$edjson" --argjson avatars "$avjson" --argjson pub "$pubcount" \
  '{success:true, problem_id:$id, title:$title}
   + ($core | del(.solvers))
   + {editors:$editors, solvers_public_count:$pub, solver_avatars:$avatars,
      generated_at: '"$EPOCHSECONDS"'}' > "$CACHE.tmp" 2>/dev/null \
  && mv -f "$CACHE.tmp" "$CACHE"
cat "$CACHE"
