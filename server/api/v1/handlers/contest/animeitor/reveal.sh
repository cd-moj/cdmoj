# GET /contest/animeitor/reveal?contest=<id>      (Bearer: .cstaff, .staff — e .animeitor/admin)
# Os links do REVELEITOR (a revelação do Animeitor) DA SEDE de quem pede. Ver docs/ANIMEITOR.md.
#
# O link de revelação mostra as respostas reais depois do congelamento: é CREDENCIAL. Por isso:
#   · só existe depois que o `.animeitor` LIBERA (POST /contest/animeitor/api {action:"reveal-release"});
#     antes disso → {released:false, links:[]} p/ todo mundo, sem tocar o servidor do telão;
#   · `.cstaff`/`.staff` recebem SÓ os da sede deles — o escopo é o `staff-filters.json` de sempre
#     (`staff_regions`, lib/print.sh) — em TODOS os placares em que a sede aparece (Geral, país…);
#   · fail-CLOSED: staff sem sede definida no staff-filters não recebe nenhum ({scoped:false}). Nas telas de
#     leitura "sem filtro = vê tudo"; aqui não — seria a revelação do evento inteiro na mão de um .staff genérico;
#   · `.animeitor`/admin veem todos (é a mesma lista do ?links=1 da rota deles).
# Os links são buscados AO VIVO no Animeitor e nunca gravados. Auditado por pedido atendido.
# `verify` (25/09/2026) = a última CONFERÊNCIA do MOJ (o Animeitor tem todas as runs? — lib/animeitor.sh
# an_verify): p/ o .animeitor/admin o resumo do evento; p/ .cstaff/.staff só o das sedes DELE —
# {at, state, final, final_at, ok (as sedes dele batem), sites:[{contest, site, ok}]}, sem ids nem contagem
# de outra sede. É o "validado" que o cartão do reveleitor mostra.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_animeitor || is_admin || is_cstaff || is_staff; } || fail 403 "Apenas a organização da sede ou a conta de placar" "role_required"
[[ "${REQUEST_METHOD:-GET}" == GET ]] || fail 405 "GET only" "method_not_allowed"
source "$_LIBDIR/cohorts.sh"
source "$_LIBDIR/animeitor.sh"

# .animeitor/admin veem TODOS os links, liberado ou não (é a prévia deles antes de liberar às sedes; o
# cabeçalho acima sempre disse isso, e a ordem dos testes dizia o contrário) — e a leitura vai ao audit
if is_animeitor || is_admin; then
  rel="$(an_reveal_released "$contest" && echo true || echo false)"
  an_configured "$contest" || { ok_json '{released:$r, scoped:false, all:true, sites:[], links:[], error:"not_configured"}' --argjson r "$rel"; exit 0; }
  vs="$(an_verify_summary "$contest")"
  lk="$(an_links "$contest")" || fail 502 "Animeitor inacessível" "upstream_error"
  audit_log_to "$contest" animeitor-links-read "by=$SESSION_LOGIN links=$(jq '(.revelation // []) | length' <<<"$lk" 2>/dev/null) via=reveal"
  ok_json_slurp '{released:$r, scoped:false, all:true, sites:[], links:($l[0].revelation // []), verify:$v}' l "$lk" --argjson v "$vs" --argjson r "$rel"
  exit 0
fi
if ! an_reveal_released "$contest"; then ok_json '{released:false, scoped:true, sites:[], links:[]}'; exit 0; fi
an_configured "$contest" || { ok_json '{released:true, scoped:true, sites:[], links:[], error:"not_configured"}'; exit 0; }

vs="$(an_verify_summary "$contest")"

source "$_LIBDIR/print.sh"
rf="$(mktemp)"; trap 'rm -f "$rf"' EXIT
if ! staff_regions "$contest" > "$rf" 2>/dev/null || [[ ! -s "$rf" ]]; then
  ok_json '{released:true, scoped:false, sites:[], links:[]}'; exit 0
fi
links="$(an_reveal_links "$contest" "$rf")" || fail 502 "Animeitor inacessível" "upstream_error"
audit_log_to "$contest" animeitor-reveal-read "sedes=$(tr '\n' ',' < "$rf" | cut -c1-120) links=$(jq 'length' <<<"$links" 2>/dev/null)"
# a conferência das sedes DELE (pelos pares placar/sede dos links que ele recebeu)
vmine="$(jq -c --argjson l "$links" '
  . as $v | ($l | map({contest, site})) as $mine
  | if ($v.at // 0) == 0 then {}
    else ([ ($v.sites // [])[] | select({contest, site} as $k | $mine | index([$k]))
            | {contest, site, ok: (.http == "200" and .missing == 0 and .wrong == 0 and .extra == 0)} ]) as $ss
         | {at: $v.at, state: $v.state, final: (($v.final == true) and ($ss | length) > 0 and ($ss | all(.ok))), final_at: ($v.final_at // 0),
            ok: (($ss | length) > 0 and ($ss | all(.ok))), sites: $ss} end' <<<"$vs" 2>/dev/null)"
[[ -n "$vmine" ]] || vmine='{}'
ok_json_slurp '{released:true, scoped:true, sites:($s | split("\n") | map(select(length > 0))), links:$l[0], verify:$v}' l "$links" --rawfile s "$rf" --argjson v "$vmine"
