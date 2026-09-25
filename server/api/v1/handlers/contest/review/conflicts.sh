# GET /contest/review/conflicts?contest=<id>   (Bearer, admin OU juiz-chefe)
# Sumário dos CONFLITOS de veredicto (2 juízes discordaram) p/ o juiz-chefe resolver. Mostra os
# votos de cada juiz. `n` é usado pelo front p/ disparar o alerta vibrante quando aumenta.
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "chief_required"
source "$_LIBDIR/review.sh"

now="$EPOCHSECONDS"
# UMA passada de jq sobre a fila (rv_scan) — era um jq POR ARQUIVO e, em cada volta, um `$(rv_quorum)` (grep
# no conf). O alerta do chefe (shared/chief-alert.js) chama esta rota a cada 8–12 s em CADA aba aberta: na
# XIV Maratona UnB (25/09/2026) foi a 2ª rota mais cara, com p95 de 1,3 s e crescendo com a fila.
out="$(rv_scan "$(rv_dir "$contest")" "$(rv_expire_filter)
    | $(rv_recompute)
    | select(.conflict == true)
    | { id, login, problem_id, lang, sub_epoch, computed_verdict, created_at,
        votes:[ (.votes // [])[] | {by, label, verdict} ] }" \
  --argjson now "$now" --argjson q "$(rv_quorum "$contest")" \
  | jq -cs 'sort_by(.created_at, .id)')"
[[ -n "$out" ]] || out='[]'
# a lista cresce com o evento ⇒ por arquivo (ok_json_slurp), nunca por --argjson (teto de 128 KiB por argumento)
ok_json_slurp '{conflicts:$c[0], n:($c[0]|length), options:$o}' c "$out" --argjson o "$(rv_options "$contest")"
