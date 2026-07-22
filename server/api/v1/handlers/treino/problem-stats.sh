# GET /treino/problem-stats?id=<problemid>
# Estatísticas de submissão de UM problema do treino: métricas gerais, distribuição de
# veredictos, por-linguagem (submissões/aceitos/solvers distintos), editores declarados
# pelos solvers, e a lista de avatares de solvers com perfil público.
# Cache var/problem-stats/<id>.json invalidado POR EVENTO: var/.score-dirty (toda submissão
# julgada o toca) mais novo que o cache = há dado novo; sem submissão nova, o cache vale p/
# SEMPRE (dado idêntico). Piso de 2 min segura o custo sob rajada de submissões; flock
# serializa a regeneração (sem stampede num problema popular).
id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing problem id" "id_missing"
valid_id "$id" || fail 400 "Invalid problem id" "id_invalid"
T="$CONTESTSDIR/treino"
[[ -f "$T/var/jsons/$id.json" ]] || fail 404 "Problem not found" "problem_notfound"

CACHE="$T/var/problem-stats/$id.json"
DIRTY="$T/var/.score-dirty"
_pshdr(){ printf 'Status: 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-cache, must-revalidate\r\n\r\n'; }
_psfresh(){ [[ -f "$CACHE" ]] && { [[ ! "$DIRTY" -nt "$CACHE" ]] \
            || [[ -z "$(find "$CACHE" -mmin +2 2>/dev/null)" ]]; }; }
if _psfresh; then _pshdr; cat "$CACHE"; exit 0; fi
mkdir -p "$T/var/problem-stats"
exec 8>>"$CACHE.lock"; flock 8
if _psfresh; then _pshdr; cat "$CACHE"; exit 0; fi   # outro request regenerou na espera

set +o noglob
title="$(jq -r '.title // ""' "$T/var/jsons/$id.json" 2>/dev/null)"

# linhas do problema (campo 3 == id). Pode ser vazio. emit_history_stream unifica store-v2/legado.
plines="$(emit_history_stream treino | awk -F: -v p="$id" '$3==p' 2>/dev/null)"

# O sub_epoch (campo 6) alimenta as séries temporais; datas/horas no fuso do público-alvo
# (TZ p/ o strflocaltime do jq). Uma passada só; buckets fixos saem prontos p/ o front.
core="$(printf '%s\n' "$plines" | jq -R 'select(length>0)|split(":")|{user:(.[1]//""), lang:(.[3]//"?"), verdict:(.[4]//""), epoch:((.[5]//"0")|(tonumber? // 0))}' \
  | TZ=America/Sao_Paulo jq -s '
      def vc: if startswith("Accepted") then "Accepted"
              elif startswith("Wrong") then "Wrong Answer"
              elif startswith("Time Limit") then "Time Limit Exceeded"
              elif (startswith("Runtime") or startswith("Possible Runtime")) then "Runtime Error"
              elif (startswith("Compilation") or startswith("Language")) then "Compilation Error"
              else "Outro" end;
      # canonicaliza a linguagem: minúsculas + sem espaços, e funde variantes
      # equivalentes (CPP/C++/CC/CXX/HPP -> cpp, H -> c, PY3/PY2 legado -> py).
      def canon: (ascii_upcase | gsub("\\s";"")) as $u
        | ({"C++":"cpp","CC":"cpp","CXX":"cpp","HPP":"cpp","H":"c","PY3":"py","PY2":"py"}[$u]) // ($u | ascii_downcase);
      def acc: (.verdict|startswith("Accepted"));
      def triesb: if .<=1 then "1" elif .==2 then "2" elif .==3 then "3"
                  elif .<=5 then "4-5" elif .<=10 then "6-10" else ">10" end;
      def t2sb: if .<3600 then "<1h" elif .<86400 then "1h-1d"
                elif .<604800 then "1d-1sem" else ">1sem" end;
      def med: sort | (if length==0 then null else .[((length-1)/2)|floor] end);
      (map(.lang |= canon)) as $s
      | ($s|length) as $total
      | ($s|map(.user)|unique) as $att
      | ($s|map(select(acc)|.user)|unique) as $solv
      | ($s|map(select(.epoch>0))|sort_by(.epoch)) as $ss
      | ($ss|map(.epoch|strflocaltime("%Y-%m-%d"))|group_by(.)|map({key:(.[0]), value:length})|from_entries) as $daily
      # por resolvedor: quantas tentativas até o 1º AC e quanto tempo da 1ª sub ao AC
      | ($s|group_by(.user)|map(
            (sort_by(.epoch)) as $u
            | ($u|map(acc)|index(true)) as $i
            | select($i != null)
            | {user:($u[0].user), tries:($i+1), t2s:(($u[$i].epoch)-($u[0].epoch)), ac_epoch:($u[$i].epoch)}
        )) as $si
      | {
          total_submissions: $total,
          distinct_attempted: ($att|length),
          distinct_solved: ($solv|length),
          acceptance_rate: (if $total>0 then (($s|map(select(acc))|length)/$total) else 0 end),
          avg_submissions_per_user: (if ($att|length)>0 then ($total/($att|length)) else 0 end),
          verdicts: ($s|map(.verdict|vc)|group_by(.)|map({verdict:(.[0]), count:length})|sort_by(-.count)),
          by_language: ($s|group_by(.lang)|map({
              lang:(.[0].lang), submissions:length,
              accepted:(map(select(acc))|length),
              solvers:(map(select(acc)|.user)|unique|length)
            })|sort_by(-.submissions)),
          daily: $daily,
          monthly: ($ss|group_by(.epoch|strflocaltime("%Y-%m"))|map({
              m:(.[0].epoch|strflocaltime("%Y-%m")), subs:length,
              ac:(map(select(acc))|length)
            })),
          dow_hour: ($ss|group_by(.epoch|strflocaltime("%w:%H"))|map({
              dow:((.[0].epoch|strflocaltime("%w"))|tonumber),
              hour:((.[0].epoch|strflocaltime("%H"))|tonumber),
              n:length
            })),
          first_ac_epochs: ($si|map(.ac_epoch)|map(select(.>0))|sort),
          tries: (["1","2","3","4-5","6-10",">10"]|map(. as $b | {bucket:$b, n:($si|map(select((.tries|triesb)==$b))|length)})),
          tries_median: ($si|map(.tries)|med),
          time_to_solve: (["<1h","1h-1d","1d-1sem",">1sem"]|map(. as $b | {bucket:$b, n:($si|map(select(.ac_epoch>0)|.t2s)|map(select(.>=0))|map(select((.|t2sb)==$b))|length)})),
          t2s_median: ($si|map(select(.ac_epoch>0)|.t2s)|map(select(.>=0))|med),
          facts: {
            first_sub_epoch: (if ($ss|length)>0 then ($ss[0].epoch) else null end),
            last_sub_epoch: (if ($ss|length)>0 then ($ss[-1].epoch) else null end),
            peak_day: (($daily|to_entries|max_by(.value)) as $p | if $p == null then null else {date:($p.key), n:($p.value)} end),
            first_solver: (($si|map(select(.ac_epoch>0))|sort_by(.ac_epoch)|.[0]) as $f
              | if $f == null then null else {epoch:($f.ac_epoch), login:($f.user)} end)
          },
          solvers: $solv
        }')"

# editores declarados pelos solvers + avatares de quem é público
declare -A EDC; declare -a AV; pubcount=0
# 1º a resolver: o login/nome só saem no JSON se a conta for PÚBLICA (senão fica só a data)
fsl="$(jq -r '.facts.first_solver.login // ""' <<<"$core")"; fspub=false; fsname=""
while IFS= read -r u; do
  [[ -z "$u" ]] && continue
  pf="$T/users/$u/account.json"; fe=""; pub=1
  if [[ -f "$pf" ]]; then
    fe="$(jq -r '.favorite_editor // ""' "$pf" 2>/dev/null)"
    [[ "$(jq -r 'if .public==false then "n" else "y" end' "$pf" 2>/dev/null)" == "n" ]] && pub=0
  fi
  [[ -n "$fe" ]] && EDC["$fe"]=$(( ${EDC["$fe"]:-0} + 1 ))
  if (( pub )); then
    [[ -n "$fsl" && "$u" == "$fsl" ]] && { fspub=true; fsname="$(jq -r '.fullname // ""' "$pf" 2>/dev/null)"; }
    ((pubcount++))
    if (( ${#AV[@]} < 200 )); then
      nm="$(jq -r '.fullname // ""' "$pf" 2>/dev/null)"
      hp="$([[ -f "$T/users/$u/photo.png" ]] && echo true || echo false)"
      AV+=("$(jq -cn --arg l "$u" --arg n "$nm" --argjson hp "$hp" '{login:$l, name:$n, has_photo:$hp}')")
    fi
  fi
done < <(jq -r '.solvers[]?' <<<"$core")

edjson="$(for k in "${!EDC[@]}"; do jq -cn --arg e "$k" --argjson c "${EDC[$k]}" '{editor:$e, count:$c}'; done | jq -cs 'sort_by(-.count)')"
[[ -z "$edjson" ]] && edjson='[]'
avjson="$( ((${#AV[@]})) && printf '%s\n' "${AV[@]}" | jq -cs '.' || echo '[]')"

jq -n --arg id "$id" --arg title "$title" --argjson core "$core" \
   --argjson editors "$edjson" --argjson avatars "$avjson" --argjson pub "$pubcount" \
   --argjson fspub "$fspub" --arg fsname "$fsname" \
  '{success:true, problem_id:$id, title:$title}
   + ($core | del(.solvers)
      | (if (.facts.first_solver != null) then
           (if $fspub then (.facts.first_solver.name = $fsname)
            else (.facts.first_solver = {epoch: (.facts.first_solver.epoch)}) end)
         else . end))
   + {editors:$editors, solvers_public_count:$pub, solver_avatars:$avatars,
      generated_at: '"$EPOCHSECONDS"'}' > "$CACHE.tmp" 2>/dev/null \
  && mv -f "$CACHE.tmp" "$CACHE"
[[ -f "$CACHE" ]] || fail 500 "Falha ao montar as estatísticas" "stats_failed"
_pshdr; cat "$CACHE"
