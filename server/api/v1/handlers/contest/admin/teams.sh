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
  # a SEDE derivada pela regra ÚNICA (lib/regions.sh: a regex mais FUNDA — antes a 1ª em pré-ordem, e o
  # pai vencia a folha: teamsp01 era carimbado "Brasil"), carregada UMA vez; só vale p/ quem não tem gravada
  source "$_LIBDIR/regions.sh"
  declare -A SITE=()
  if m="$(rg_map "$contest" 2>/dev/null)"; then
    while IFS=$'\t' read -r l nm; do [[ -n "$l" ]] && SITE[$l]="$nm"; done < <(
      jq -Rrn --slurpfile n "$cdir/var/regions-nodes.json" \
        'inputs | split("\t") | select(.[3] == "r" or .[3] == "p") | "\(.[0])\t\($n[0][.[1] | tonumber].name)"' "$m" 2>/dev/null)
  fi
  filled='{}'; nfill=0
  while IFS= read -r d; do
    login="${d##*/}"
    case "$login" in *.admin|*.judge|*.cjudge|*.staff|*.cstaff|*.mon|*.animeitor|.removed-users) continue;; esac
    [[ -f "$d/account.json" ]] || continue
    # jq: BINDA .regex antes do test ($l|test(.regex) leria .regex de $l — armadilha de
    # contexto de args); try/catch protege de regex inválida. 1ª regra/região que casa vence.
    delta="$(jq -c --arg l "$login" --argjson rules "$rules" --arg site "${SITE[$login]:-}" '
      (.team // {}) as $tm
      | ($rules   | map(.regex as $rr | select($rr != null and $rr != "" and (try ($l|test($rr;"i")) catch false))) | first // {}) as $r
      | {name: $site} as $g
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
  # nome/sigla/bandeira/sede mudaram: o placar e os caches preguiçosos se refazem (sem isto o placar seguia com os
  # dados velhos até o próximo veredicto — auditoria do painel, 03/10/2026; molde do user_rename/perfil)
  (( nfill > 0 )) && touch "$cdir/var/.score-dirty" 2>/dev/null
  audit_log_to "$contest" teams-materialize "preencheu=$nfill"
  ok_json '{materialized:$n, filled:$f}' --argjson n "$nfill" --argjson f "$filled"
  exit 0
fi

# ---------- {set:{login:{…}}} -------------------------------------------------------------
setj="$(jq -c '.set // {}' <<<"$body")"
jq -e 'type=="object" and length > 0' >/dev/null 2>&1 <<<"$setj" \
  || fail 422 "Informe set{login:{…}} ou action:materialize" "set_missing"
(( "$(jq 'length' <<<"$setj")" <= 5000 )) || fail 422 "Máximo de 5000 por lote" "too_many"

saved=0; declare -a SKIPPED=(); ADJ='[]'
_nm_jq="$NAME_CLEAN_JQ"
while IFS= read -r login; do
  fields="$(jq -c --arg l "$login" '.[$l]' <<<"$setj")"
  { valid_id "$login" && user_exists "$contest" "$login"; } || { SKIPPED+=("$login"); continue; }
  # nome (fullname) saneado; vazio = não mexe (o time não fica sem nome)
  full="$(jq -r '.fullname // ""' <<<"$fields")"
  fraw="$full"; name_clean full "$full"     # ':' vira '∶' (o placar TXT separa por ':'); avisa em `adjusted`
  fadj=$NAME_CLEAN_COLON
  # campos de time PRESENTES entram (saneados); "" apaga; ausentes não tocam
  tm="$(jq -c '{univ_short:(if has("univ_short") then .univ_short else null end),
                univ_full:(if has("univ_full") then .univ_full else null end),
                flag:(if has("country") then .country else null end),
                region:(if has("region") then .region else null end)}
               | with_entries(select(.value != null))
               | with_entries(.key as $k | .value |= (tostring
                   | if ($k == "univ_short" or $k == "univ_full") then '"$_nm_jq"' else (gsub("[:\t\n\r]"; " ") | gsub("^ +| +$"; "")) end))' \
        <<<"$fields" 2>/dev/null)"
  [[ -n "$tm" ]] || tm='{}'
  [[ "$tm" != '{}' || -n "$full" ]] || { SKIPPED+=("$login"); continue; }
  account_merge "$contest" "$login" \
    '(if $fn != "" then .fullname = $fn else . end)
     | .team = (((.team // {}) + $tm) | with_entries(select(.value != "")))
     | if (.team|length)==0 then del(.team) else . end | .updated_at=$t' \
    --arg fn "$full" --argjson tm "$tm" --argjson t "$EPOCHSECONDS" || { SKIPPED+=("$login"); continue; }
  (( saved++ ))
  (( fadj )) && ADJ="$(jq -c --arg l "$login" --arg f "$fraw" --arg t "$full" '. + [{login:$l, field:"fullname", from:$f, to:$t}]' <<<"$ADJ")"
done < <(jq -r 'keys[]' <<<"$setj")

(( saved > 0 )) && { mkdir -p "$CONTESTSDIR/$contest/var"; touch "$CONTESTSDIR/$contest/var/.score-dirty" 2>/dev/null; }
audit_log_to "$contest" teams-set "salvos=$saved skipped=${#SKIPPED[@]}"
ok_json '{saved:$n, skipped:$s, adjusted:$a}' --argjson n "$saved" --argjson a "$ADJ" \
  --argjson s "$( ((${#SKIPPED[@]})) && printf '%s\n' "${SKIPPED[@]}" | jq -R . | jq -cs . || echo '[]')"
