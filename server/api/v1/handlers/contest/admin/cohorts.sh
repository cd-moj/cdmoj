# GET/POST /contest/admin/cohorts?contest=<c>
# COORTES de placar: times oficiais × CONVIDADOS (extra-oficiais / "CCL"). Motor em
# lib/cohorts.sh; o placar de cada visão é gerado por server/score/build.sh.
# Leitura: admin ou juiz-chefe. Escrita: só admin (muda quem vê quem).
#
# GET  -> {cohorts:[…], results_released, views:[…], counts:{<id>:n}, unassigned:[login…]}
# POST {action}:
#   add        {id,name?,regex?,public?,unranked?,sees?[]}
#   set        {id, …}                — mesma forma; `default:true` move a marca de default
#   rm         {id}                   — recusa se for a default ou se houver time nela
#   assign     {login, cohort}        — grava .team.cohort (""/null solta o time p/ a regra)
#   materialize                       — carimba .team.cohort em quem hoje casa só por regex
#   release    {on:bool}              — o "liberamos tudo": todos passam a ver todos
require_auth_contest "$(param contest)"
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/cohorts.sh"

cdir="$CONTESTSDIR/$contest"

# _ch_counts -> {"<cohort>":n,…} + lista de quem NÃO tem .team.cohort explícito.
# Um jq por conta seria um fork por time: resolve tudo numa passada, como o sc_users.
_ch_counts_file(){  # <out-json>
  local out="$1" chj
  chj="$(jq -c '{cohorts:[ .cohorts[] | {id, regex, default} ]}' <<<"$(ch_get "$contest")")"
  { find "$cdir/users" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
      | xargs -0 -r jq -r --argjson CH "$chj" '
          (.login // "") as $l
          | select($l | test("\\.(admin|judge|cjudge|staff|cstaff|mon)$") | not)
          | (((.team.cohort // "") as $c
              | if $c != "" then $c
                else ((first($CH.cohorts[] | .regex as $rr
                             | select($rr != "" and (try ($l|test($rr;"i")) catch false)) | .id))
                      // (first($CH.cohorts[] | select(.default) | .id)) // "") end)) as $coh
          | [$coh, $l, ((.team.cohort // "") != "")] | @tsv' ; } \
    | jq -Rs --arg dummy x '
        [ (./"\n")[] | select(length > 0) | (./"\t") ]
        | { counts: (map(.[0]) | group_by(.) | map({key:.[0], value:length}) | from_entries),
            explicit: (map(select(.[2] == "true") | .[1])),
            byregex: (map(select(.[2] != "true") | .[1])) }' > "$out" 2>/dev/null
  [[ -s "$out" ]] || printf '{"counts":{},"explicit":[],"byregex":[]}' > "$out"
}

if [[ "$REQUEST_METHOD" == GET ]]; then
  is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
  cf="$(mktemp)"; _ch_counts_file "$cf"
  views="$(ch_views "$contest" | jq -Rc '[inputs]' 2>/dev/null)"; [[ -n "$views" ]] || views='["public"]'
  body="$(jq -cn --argjson j "$(ch_get "$contest")" --slurpfile c "$cf" --argjson v "$views" '
    ($c[0] // {}) as $C
    | {success:true, cohorts:($j.cohorts // []), results_released:($j.results_released == true),
       views:$v, counts:($C.counts // {}),
       by_regex_only:($C.byregex // []) }')"
  rm -f "$cf"
  [[ -n "$body" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
  emit_json 200 OK; printf '%s\n' "$body"; exit 0
fi

require_method POST
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
bodyf="$(read_body_file)"
jq -e . "$bodyf" >/dev/null 2>&1 || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // ""' "$bodyf")"
j="$(ch_get "$contest")"

# _ch_regex_ok <regex> — precisa COMPILAR (regra quebrada silenciaria as outras no gate),
# mesma validação do time-overrides.sh
_ch_regex_ok(){ [[ -z "$1" ]] && return 0; jq -n --arg r "$1" '"x" | test($r)' >/dev/null 2>&1; }

case "$action" in
  add|set)
    id="$(jq -r '.id // ""' "$bodyf")"
    ch_valid_id "$id" || fail 422 "id inválido (a-z, 0-9, - e _; até 24)" "id_invalid"
    exists=false
    jq -e --arg i "$id" 'any(.cohorts[]; .id == $i)' <<<"$j" >/dev/null 2>&1 && exists=true
    [[ "$action" == add && "$exists" == true ]] && fail 409 "já existe a coorte '$id'" "id_taken"
    [[ "$action" == set && "$exists" != true ]] && fail 404 "coorte não encontrada" "cohort_notfound"
    (( $(jq '(.cohorts // []) | length' <<<"$j") < 8 )) || [[ "$action" == set ]] \
      || fail 422 "máximo de 8 coortes" "too_many"
    rx="$(jq -r '.regex // ""' "$bodyf")"
    _ch_regex_ok "$rx" || fail 422 "regex inválida: $rx" "regex_invalid"
    (( ${#rx} <= 200 )) || fail 422 "regex muito longa" "regex_long"
    cur='{}'
    [[ "$exists" == true ]] && cur="$(jq -c --arg i "$id" 'first(.cohorts[] | select(.id == $i))' <<<"$j")"
    new="$(jq -c --argjson cur "$cur" --arg i "$id" --slurpfile b "$bodyf" '
      ($b[0]) as $B
      | $cur + {id:$i}
      + (if ($B|has("name"))     then {name:($B.name|tostring)} else {} end)
      + (if ($B|has("regex"))    then {regex:($B.regex|tostring)} else {} end)
      + (if ($B|has("public"))   then {public:($B.public == true)} else {} end)
      + (if ($B|has("unranked")) then {unranked:($B.unranked == true)} else {} end)
      + (if ($B|has("default"))  then {default:($B.default == true)} else {} end)
      + (if ($B|has("sees"))     then {sees:[($B.sees // [])[] | tostring]} else {} end)
      | .name = (if (.name // "") == "" then .id else .name end)
      | .public = (.public != false) | .unranked = (.unranked == true)
      | .sees = (.sees // []) | .default = (.default == true)' <<<'null')"
    [[ -n "$new" ]] || fail 500 "falha ao montar a coorte" "build_fail"
    if [[ "$exists" == true ]]; then
      j="$(jq -c --arg i "$id" --argjson n "$new" '.cohorts = [ .cohorts[] | if .id == $i then $n else . end ]' <<<"$j")"
    else
      j="$(jq -c --argjson n "$new" '.cohorts = ((.cohorts // []) + [$n])' <<<"$j")"
    fi
    # a marca de `default` é ÚNICA (e alguém tem de tê-la: senão login sem regra fica órfão)
    if jq -e --argjson n "$new" '$n.default' >/dev/null 2>&1 <<<'null'; then
      j="$(jq -c --arg i "$id" '.cohorts = [ .cohorts[] | .default = (.id == $i) ]' <<<"$j")"
    fi
    jq -e 'any(.cohorts[]; .default)' <<<"$j" >/dev/null 2>&1 \
      || j="$(jq -c '.cohorts = ([.cohorts[0] + {default:true}] + .cohorts[1:])' <<<"$j")"
    ch_save "$contest" "$j"
    touch "$cdir/var/.score-dirty" 2>/dev/null || true   # o placar depende das coortes
    audit_log_to "$contest" "cohorts-$action" "id=$id"
    ok_json '{saved:true, cohorts:$c}' --argjson c "$(jq -c '.cohorts' <<<"$j")"
    ;;
  rm|remove)
    id="$(jq -r '.id // ""' "$bodyf")"
    jq -e --arg i "$id" 'any(.cohorts[]; .id == $i)' <<<"$j" >/dev/null 2>&1 \
      || fail 404 "coorte não encontrada" "cohort_notfound"
    jq -e --arg i "$id" 'any(.cohorts[]; .id == $i and .default)' <<<"$j" >/dev/null 2>&1 \
      && fail 409 "a coorte default não pode ser removida" "is_default"
    cf="$(mktemp)"; _ch_counts_file "$cf"
    n="$(jq -r --arg i "$id" '(.counts[$i] // 0)' "$cf")"; rm -f "$cf"
    (( ${n//[^0-9]/} == 0 )) || fail 409 "$n time(s) ainda estão nesta coorte" "cohort_in_use"
    j="$(jq -c --arg i "$id" '.cohorts = [ .cohorts[] | select(.id != $i) ]
         | .cohorts = [ .cohorts[] | .sees = [ (.sees // [])[] | select(. != $i) ] ]' <<<"$j")"
    ch_save "$contest" "$j"
    rm -f "$cdir/var/placar-view-$id.txt" "$cdir/var/placar-view-$id-full.txt" 2>/dev/null
    touch "$cdir/var/.score-dirty" 2>/dev/null || true
    audit_log_to "$contest" cohorts-rm "id=$id"
    ok_json '{removed:true}'
    ;;
  assign)
    login="$(jq -r '.login // ""' "$bodyf")"; co="$(jq -r '.cohort // ""' "$bodyf")"
    valid_id "$login" || fail 422 "login inválido" "login_invalid"
    user_exists "$contest" "$login" || fail 404 "conta não encontrada" "user_notfound"
    [[ -z "$co" ]] || jq -e --arg i "$co" 'any(.cohorts[]; .id == $i)' <<<"$j" >/dev/null 2>&1 \
      || fail 422 "coorte inexistente" "cohort_notfound"
    if [[ -z "$co" ]]; then
      account_merge "$contest" "$login" '.team = ((.team // {}) | del(.cohort)) | .updated_at=$t' \
        --argjson t "$EPOCHSECONDS" || fail 500 "falha ao gravar" "write_fail"
    else
      account_team_merge "$contest" "$login" "$(jq -cn --arg c "$co" '{cohort:$c}')" \
        || fail 500 "falha ao gravar" "write_fail"
    fi
    touch "$cdir/var/.score-dirty" 2>/dev/null || true
    audit_log_to "$contest" cohorts-assign "login=$login cohort=${co:-(regra)}"
    ok_json '{saved:true, login:$l, cohort:$c}' --arg l "$login" --arg c "$co"
    ;;
  materialize)
    # carimba .team.cohort em quem hoje só casa por REGEX — o mesmo espírito do materialize
    # de sedes (aba Times): a regra vira dado, e mudar o regex depois não remaneja ninguém.
    cf="$(mktemp)"; _ch_counts_file "$cf"
    n=0
    while IFS= read -r login; do
      [[ -n "$login" ]] || continue
      co="$(ch_of "$contest" "$login")"; [[ -n "$co" ]] || continue
      account_team_merge "$contest" "$login" "$(jq -cn --arg c "$co" '{cohort:$c}')" && ((n++))
    done < <(jq -r '.byregex[]?' "$cf")
    rm -f "$cf"
    touch "$cdir/var/.score-dirty" 2>/dev/null || true
    audit_log_to "$contest" cohorts-materialize "carimbados=$n"
    ok_json '{materialized:$n}' --argjson n "${n:-0}"
    ;;
  release)
    on=true; jq -e '.on == false' "$bodyf" >/dev/null 2>&1 && on=false
    j="$(jq -c --argjson on "$on" '.results_released=$on' <<<"$j")"
    ch_save "$contest" "$j"
    touch "$cdir/var/.score-dirty" 2>/dev/null || true
    audit_log_to "$contest" cohorts-release "on=$on"
    ok_json '{results_released:$on}' --argjson on "$on"
    ;;
  *) fail 400 "action inválida" "action_invalid";;
esac
