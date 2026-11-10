# /contest/staff/test-tasks?contest=<c>   (Bearer: .staff ou admin do contest)
# TAREFAS DE TESTE da impressão (09/11/2026; pedido do Fernando: medir a velocidade e o paralelismo das impressoras).
#   GET                                  -> {blocked, scope, sites, summary} — a medida do lote que ESTE staff vê
#   POST {action:"create", count, kind:"print"|"balloon"|"mixed", pages, site?}
#        cria `count` (1..200) tarefas de teste; `pages` (1..20) por impressão. O .staff cria SÓ para a própria sede
#        (as sedes do staff-filters dele; sem escopo = todas); o admin escolhe `site` (vazio = todas as sedes).
#   POST {action:"delete"}               -> apaga as tarefas de teste que este staff vê (admin: todas)
# PROIBIDO durante a prova (início definido e já passou, fim de todas as sedes ainda não): 409 test_blocked. Sem
# impressão (PRINT=0) não há teste de impressão; sem o módulo baloes, não há teste de balão (409). Regras e formato
# em lib/print.sh (pr_test_*). Auditado: staff-test.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_staff || is_admin; } || fail 403 "Apenas staff ou admin" "staff_required"
source "$_LIBDIR/print.sh"

blocked=false; pr_test_blocked "$contest" && blocked=true
# as sedes deste staff (o escopo do lote que ele cria); o admin escolhe entre as sedes do staff-filters
scope='[]'; sites='[]'
if is_admin; then
  f="$(pr_dir "$contest")/staff-filters.json"
  [[ -s "$f" ]] && sites="$(jq -c '[.[]? | .[]? | select(type == "string" and startswith("region:")) | .[7:] | gsub("^ +| +$"; "")
                                     | select(length > 0)] | unique' "$f" 2>/dev/null)"
  [[ -n "$sites" ]] || sites='[]'
elif mine="$(staff_regions "$contest")"; then
  scope="$(printf '%s\n' "$mine" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')"
fi
# staff COM escopo cujas sedes não se resolvem (escopo só por regex, time sem sede, módulo sedes desligado): o create
# falha fechado (o .staff cria só para a própria sede); só o staff SEM escopo nenhum (que já vê tudo) cria lote de todas.
unresolved=false
if ! is_admin && [[ "$scope" == '[]' ]] \
   && jq -e --arg s "$SESSION_LOGIN" 'has($s) and ((.[$s] // []) | length > 0)' "$(pr_dir "$contest")/staff-filters.json" >/dev/null 2>&1; then
  unresolved=true
fi

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  pr_test_purge_if_running "$contest"
  sm="$(pr_test_summary "$contest")"; [[ -n "$sm" ]] || sm='{}'
  ok_json '{blocked:$b, scope:$sc, sites:$si, summary:$sm}' \
    --argjson b "$blocked" --argjson sc "$scope" --argjson si "$sites" --argjson sm "$sm"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // ""' <<<"$body")"

case "$action" in
  create)
    [[ "$blocked" == true ]] && fail 409 "Tarefas de teste não podem ser criadas durante a prova" "test_blocked"
    n="$(jq -r '.count // 0' <<<"$body")"; kind="$(jq -r '.kind // "print"' <<<"$body")"; pages="$(jq -r '.pages // 1' <<<"$body")"
    [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= 200 )) || fail 422 "Quantidade: de 1 a 200" "count_invalid"
    [[ "$pages" =~ ^[0-9]+$ ]] && (( pages >= 1 && pages <= 20 )) || fail 422 "Páginas por impressão: de 1 a 20" "pages_invalid"
    case "$kind" in print|balloon|mixed) ;; *) fail 422 "Tipo: print, balloon ou mixed" "kind_invalid";; esac
    if [[ "$kind" != balloon ]] && ! print_enabled "$contest"; then
      fail 409 "A impressão está desligada neste contest" "print_disabled"
    fi
    if [[ "$kind" != print ]] && ! mod_on "$contest" baloes; then
      fail 409 "O módulo de balões está desligado neste contest" "balloons_disabled"
    fi
    [[ "$unresolved" == true ]] && fail 422 "O seu escopo não tem sede definida: peça ao admin para pôr a sede (region:<nome>) no seu escopo, ou para criar o lote" "test_scope_unresolved"
    if is_admin; then
      site="$(jq -r '.site // ""' <<<"$body")"
      if [[ -n "$site" ]]; then
        [[ ${#site} -le 120 && "$site" != *$'\n'* ]] || fail 422 "Sede inválida" "site_invalid"
        scope="$(jq -cn --arg s "$site" '[$s]')"
      fi
    fi
    range="$(pr_test_create "$contest" "$n" "$kind" "$pages" "$scope" "$SESSION_LOGIN")"
    audit_log_to "$contest" staff-test "create n=$n tipo=$kind paginas=$pages faixa=${range// /-} sedes=$(jq -r 'join(";")' <<<"$scope") by=$SESSION_LOGIN"
    ok_json '{created:$n, range:$r, scope:$sc}' --argjson n "$n" --arg r "$range" --argjson sc "$scope"
    ;;
  delete)
    mapfile -t ids < <(pr_test_visible_ids "$contest")
    k=0; (( ${#ids[@]} )) && k="$(pr_test_remove "$contest" "${ids[@]}")"
    audit_log_to "$contest" staff-test "delete n=$k by=$SESSION_LOGIN"
    ok_json '{deleted:$k}' --argjson k "${k:-0}"
    ;;
  *) fail 422 "action deve ser create ou delete" "action_invalid";;
esac
