# POST /contest/admin/teams?contest=<id>   (admin DO contest)
# Edição POR-USUÁRIO da identidade do TIME (o placar/badges/print leem do account.json).
# O NOME é campo ÚNICO: `fullname` (usuário de contest É o time). Duas operações:
#   {set:{<login>:{fullname?,univ_short?,univ_full?,country?,region?}, …}}
#     — `fullname` mescla em `.fullname` (vazio = ignorado; nome não fica em branco);
#       os demais mesclam no `.team` (valor vazio "" APAGA o campo; ausente não toca).
#       Login inexistente vira skipped.
#   {action:"materialize"}
#     — o "match de 1 clique": aplica teams-meta.json (regex→country/school/school_full) e
#       regions.json (regex→name) aos usuários SEM o campo correspondente, gravando
#       por-usuário. Campo já preenchido NUNCA é sobrescrito. Devolve o que preencheu.
# Contest com USERS_FROM (usuários compartilhados) → 409 shared_users (sem overlay local;
# esses contests seguem no teams-meta regex). Auditado (teams-set/teams-materialize).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

shared="$(grep -m1 '^USERS_FROM=' "$CONTESTSDIR/$contest/conf" 2>/dev/null | cut -d= -f2-)"
[[ -n "$shared" ]] && fail 409 "Contest com usuários compartilhados (users_from): use as regras regex (Aparência → teams-meta)" "shared_users"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
cdir="$CONTESTSDIR/$contest"

# ---------- {action:"materialize"} -------------------------------------------------------
if [[ "$(jq -r '.action // empty' <<<"$body")" == materialize ]]; then
  rules="$(jq -c '.rules // (if type=="array" then . else [] end)' "$cdir/teams-meta.json" 2>/dev/null)"
  [[ -n "$rules" ]] || rules='[]'
  # regiões achatadas (inclui subregions) -> [{name,regex}]
  regions="$(jq -c '[.. | objects | select(has("regex") and (.regex // "") != "") | {name:(.name // .regex), regex}]' \
    "$cdir/regions.json" 2>/dev/null)"
  [[ -n "$regions" ]] || regions='[]'
  filled='{}'; nfill=0
  while IFS= read -r d; do
    login="${d##*/}"
    case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.mon|.removed-users) continue;; esac
    [[ -f "$d/account.json" ]] || continue
    # jq: BINDA .regex antes do test ($l|test(.regex) leria .regex de $l — armadilha de
    # contexto de args); try/catch protege de regex inválida. 1ª regra/região que casa vence.
    delta="$(jq -c --arg l "$login" --argjson rules "$rules" --argjson regions "$regions" '
      (.team // {}) as $tm
      | ($rules   | map(.regex as $rr | select($rr != null and $rr != "" and (try ($l|test($rr;"i")) catch false))) | first // {}) as $r
      | ($regions | map(.regex as $rr | select(try ($l|test($rr;"i")) catch false)) | first // {}) as $g
      | ({}
         + (if ($tm.flag // "") == ""       and ($r.country // "") != ""     then {flag:$r.country} else {} end)
         + (if ($tm.univ_short // "") == "" and ($r.school // "") != ""      then {univ_short:$r.school} else {} end)
         + (if ($tm.univ_full // "") == ""  and ($r.school_full // "") != "" then {univ_full:$r.school_full} else {} end)
         + (if ($tm.region // "") == ""     and ($g.name // "") != ""        then {region:$g.name} else {} end))
      | with_entries(.value |= (tostring | gsub("[:\t\n\r]"; " ") | gsub("^ +| +$"; "")))
      | with_entries(select(.value != ""))' "$d/account.json" 2>/dev/null)"
    [[ -n "$delta" && "$delta" != '{}' ]] || continue
    account_team_merge "$contest" "$login" "$delta" || continue
    filled="$(jq -c --arg l "$login" --argjson d "$delta" '. + {($l): $d}' <<<"$filled")"
    (( nfill++ ))
  done < <(find "$cdir/users" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  audit_log_to "$contest" teams-materialize "preencheu=$nfill"
  ok_json '{materialized:$n, filled:$f}' --argjson n "$nfill" --argjson f "$filled"
  exit 0
fi

# ---------- {set:{login:{…}}} -------------------------------------------------------------
setj="$(jq -c '.set // {}' <<<"$body")"
jq -e 'type=="object" and length > 0' >/dev/null 2>&1 <<<"$setj" \
  || fail 422 "Informe set{login:{…}} ou action:materialize" "set_missing"
(( "$(jq 'length' <<<"$setj")" <= 5000 )) || fail 422 "Máximo de 5000 por lote" "too_many"

saved=0; declare -a SKIPPED=()
while IFS= read -r login; do
  fields="$(jq -c --arg l "$login" '.[$l]' <<<"$setj")"
  { valid_id "$login" && user_exists "$contest" "$login"; } || { SKIPPED+=("$login"); continue; }
  # nome (fullname) saneado; vazio = não mexe (o time não fica sem nome)
  full="$(jq -r '.fullname // ""' <<<"$fields")"
  full="${full//[$'\t\n\r']/ }"; full="${full//:/ }"
  full="$(printf '%s' "$full" | sed 's/^ *//; s/ *$//')"
  # campos de time PRESENTES entram (saneados); "" apaga; ausentes não tocam
  tm="$(jq -c '{univ_short:(if has("univ_short") then .univ_short else null end),
                univ_full:(if has("univ_full") then .univ_full else null end),
                flag:(if has("country") then .country else null end),
                region:(if has("region") then .region else null end)}
               | with_entries(select(.value != null))
               | with_entries(.value |= (tostring | gsub("[:\t\n\r]"; " ") | gsub("^ +| +$"; "")))' \
        <<<"$fields" 2>/dev/null)"
  [[ -n "$tm" ]] || tm='{}'
  [[ "$tm" != '{}' || -n "$full" ]] || { SKIPPED+=("$login"); continue; }
  account_merge "$contest" "$login" \
    '(if $fn != "" then .fullname = $fn else . end)
     | .team = (((.team // {}) + $tm) | with_entries(select(.value != "")))
     | if (.team|length)==0 then del(.team) else . end | .updated_at=$t' \
    --arg fn "$full" --argjson tm "$tm" --argjson t "$EPOCHSECONDS" || { SKIPPED+=("$login"); continue; }
  (( saved++ ))
done < <(jq -r 'keys[]' <<<"$setj")

audit_log_to "$contest" teams-set "salvos=$saved skipped=${#SKIPPED[@]}"
ok_json '{saved:$n, skipped:$s}' --argjson n "$saved" \
  --argjson s "$( ((${#SKIPPED[@]})) && printf '%s\n' "${SKIPPED[@]}" | jq -R . | jq -cs . || echo '[]')"
