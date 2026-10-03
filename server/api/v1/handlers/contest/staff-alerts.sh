# GET /contest/staff-alerts?contest=<id>   (Bearer: .judge, .cjudge, .admin, .mon)
# CONTAGENS do que espera a organização, p/ o alerta GLOBAL (som + banner) que segue o juiz, o chefe e o
# admin em QUALQUER página do contest (web/shared/staff-alert.js). Pedido do juiz-chefe do TCP 2026
# (03/10/2026): clarification nova só aparecia p/ quem estava na aba de clarifications.
#   clar   {open, unclaimed, last}   — abertas (sem resposta); sem dono (reserva ausente ou vencida);
#                                       `last` = a pergunta aberta mais nova (detecta chegada mesmo se
#                                       outra foi respondida entre dois polls)
#   review {manual, quorum, needing, mine_todo, mine_last, conflicts}
#            needing   = fora de "liberado", sem conflito e abaixo do quórum (só com MANUAL_VERDICT=1)
#            mine_todo = dessas, as que ESTE login ainda pode votar (não votou; avalia ou há vaga) —
#                        a mesma regra do review/claim.sh
#            conflicts = a contagem do review/conflicts.sh (só chefe/admin; null p/ o juiz comum)
# `.mon` responde clarifications, mas não vota: recebe `review:null`. Só números — nenhum login de quem
# perguntou ou votou (o anonimato do review/list e do clarifications vale aqui).
# Chamada a cada 8–12 s pela aba LÍDER de cada navegador (uma por navegador, não por aba). O porteiro
# serve o mesmo cálculo sem fork (r_staff_alerts) — mexeu numa, mexa na outra (smoke-staff-alerts.sh
# compara as duas).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_judge || is_mon || fail 403 "Apenas juiz, juiz-chefe, admin ou .mon" "staff_alerts_forbidden"
source "$_LIBDIR/review.sh"

now="$EPOCHSECONDS"; me="$SESSION_LOGIN"; cdir="$CONTESTSDIR/$contest"

# clarifications: UMA passada (rv_scan é genérico: lê *.json de um diretório num jq só e, com arquivo
# corrompido, refaz um a um — um zero mudo seria a pior falha de um alerta)
clar="$(rv_scan "$cdir/clarifications" \
  'select(type == "object" and ((.answer // "") | length) == 0)
   | {t: ((.time // 0) | if type == "number" then . else 0 end),
      free: ((.answer_claim // null) == null or ((.answer_claim.expires_at // 0) < $now))}' \
  --argjson now "$now" \
  | jq -cs '{open: length, unclaimed: (map(select(.free)) | length), last: ((map(.t) | max) // 0)}')"
[[ -n "$clar" ]] || clar='{"open":0,"unclaimed":0,"last":0}'

review=null
if is_judge; then
  manual=false; [[ "$(conf_value "$contest" MANUAL_VERDICT)" == 1 ]] && manual=true
  q="$(conf_value "$contest" REVIEW_JUDGES)"; q="${q//[^0-9]/}"; [[ "$q" =~ ^[1-5]$ ]] || q=2   # = rv_quorum
  chief="$(is_admin_or_chief && echo true || echo false)"
  review="$(rv_scan "$cdir/review" "$(rv_expire_filter)
      | $(rv_recompute)
      | ((.votes // []) | length) as \$vn
      | ((.status // \"open\") != \"released\" and (.conflict != true) and \$vn < \$q) as \$need
      | { conflict: (.conflict == true), need: \$need, t: ((.created_at // 0) | if type == \"number\" then . else 0 end),
          mine: (\$need and (any((.votes // [])[]; .by == \$me) | not)
                 and (any((.claimants // [])[]; .by == \$me) or (((.claimants // []) | length) < \$q))) }" \
    --argjson now "$now" --argjson q "$q" --arg me "$me" \
    | jq -cs --argjson manual "$manual" --argjson q "$q" --argjson chief "$chief" '
        {manual: $manual, quorum: $q,
         needing:   (if $manual then (map(select(.need)) | length) else 0 end),
         mine_todo: (if $manual then (map(select(.mine)) | length) else 0 end),
         mine_last: (if $manual then ((map(select(.mine) | .t) | max) // 0) else 0 end),
         conflicts: (if $chief then (map(select(.conflict)) | length) else null end)}')"
  [[ -n "$review" ]] || review="$(jq -cn --argjson manual "$manual" --argjson q "$q" --argjson chief "$chief" \
    '{manual:$manual, quorum:$q, needing:0, mine_todo:0, mine_last:0, conflicts:(if $chief then 0 else null end)}')"
fi

ok_json '{now:$now, clar:$clar, review:$review}' --argjson now "$now" --argjson clar "$clar" --argjson review "$review"
