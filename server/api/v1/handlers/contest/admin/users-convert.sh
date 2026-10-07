# POST /contest/admin/users-convert?contest=<id>  (admin DO contest)
#   {dry_run?:true, plan_id?, confirm?, logout_all?:false}
# CONVERTE um contest com usuários do Treino Livre (USERS_FROM) em contas PRÓPRIAS — o "desfazer" do
# compartilhamento (28/09/2026). Lógica e invariantes: lib/users-convert.sh.
#   dry_run (padrão)  -> a PRÉVIA: contagens, amostras, avisos em códigos e o plan_id. Nada é gravado.
#   executar          -> exige o plan_id da prévia (a população não pode ter mudado: 409 plan_changed com a
#                        prévia nova) e a confirmação: `confirm:true` antes da prova; o ID do contest digitado
#                        (`confirm:"<id>"`) durante ou depois. Devolve as credenciais NOVAS (única vez que a
#                        senha aparece; depois, as etiquetas).
# Sem USERS_FROM: 409 not_shared (ou already_converted com o resumo, se foi convertido).
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
body="$(read_body)"
[[ -z "$body" ]] && body='{}'
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
source "$_LIBDIR/users-convert.sh"
source "$_LIBDIR/registration.sh"
cdir="$CONTESTSDIR/$contest"

if [[ "$(_users_source "$contest")" == "$contest" ]]; then
  if [[ -s "$cdir/var/users-convert.json" ]]; then
    FAIL_EXTRA="$(jq -c '{converted:(del(.accounts) + {accounts:(.accounts | length)})}' "$cdir/var/users-convert.json" 2>/dev/null)" \
      fail 409 "Este contest já foi convertido para contas próprias" "already_converted"
  fi
  fail 409 "Este contest não usa usuários do Treino Livre" "not_shared"
fi

dry="$(jq -r 'if .dry_run == false then "0" else "1" end' <<<"$body")"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
uc_collect "$contest" "$W" || fail 500 "Falha ao levantar as contas" "collect_fail"
uc_report "$contest" "$W" > "$W/report.json" || fail 500 "Falha ao montar a prévia" "report_fail"

if [[ "$dry" == 1 ]]; then
  ok_json_slurp '{preview:$r[0]}' r "$(cat "$W/report.json")"
  exit 0
fi

# --- execução -------------------------------------------------------------------------------------------
phase="$(jq -r .phase "$W/report.json")"
want="$(jq -r '.plan_id // ""' <<<"$body")"
cf="$(jq -r 'if .confirm == true then "true" elif (.confirm|type) == "string" then .confirm else "" end' <<<"$body")"
if [[ "$phase" == before ]]; then
  [[ "$cf" == true || "$cf" == "$contest" ]] || { FAIL_EXTRA='{"need":"true"}' fail 409 "Confirme a conversão" "confirm_required"; }
else
  [[ "$cf" == "$contest" ]] || { FAIL_EXTRA="$(jq -cn --arg c "$contest" '{need:$c}')" \
    fail 409 "A prova já começou: digite o id do contest ($contest) para confirmar" "confirm_required"; }
fi
logout=0; jq -e '.logout_all == true' >/dev/null 2>&1 <<<"$body" && logout=1

# locks: rodadas → inscrição → conversão (a mesma ordem de quem já segura os dois primeiros)
mkdir -p "$cdir/var"
exec 7>"$cdir/var/.round.lock";               flock -w 10 7 || fail 409 "Contest ocupado (troca de rodada) — tente de novo" "busy"
exec 8>"$(reg_lock_file "$contest")";          flock -w 10 8 || fail 409 "Contest ocupado (inscrição) — tente de novo" "busy"
exec 9>"$cdir/var/users-convert.lock";         flock -w 10 9 || fail 409 "Conversão em andamento — tente de novo" "busy"
# sob o lock a população é levantada DE NOVO: o que se grava é o que a pessoa viu (plan_id)
rm -rf "$W"/*; uc_collect "$contest" "$W" || fail 500 "Falha ao levantar as contas" "collect_fail"
uc_report "$contest" "$W" > "$W/report.json"
now_id="$(jq -r .plan_id "$W/report.json")"
if [[ -z "$want" || "$want" != "$now_id" ]]; then
  FAIL_EXTRA="$(jq -c '{preview:.}' "$W/report.json")" \
    fail 409 "A lista de contas mudou desde a prévia — confira a prévia nova e confirme de novo" "plan_changed"
fi
res="$(uc_apply "$contest" "$W" "$logout")" || fail 500 "Falha na conversão (o contest segue compartilhado; repita para completar)" "apply_fail"
IFS=$'\x1f' read -r nsess arch moff <<<"$res"
audit_log_to "$contest" users-convert \
  "individuals=$(jq .counts.individuals "$W/report.json") teams=$(jq .counts.teams "$W/report.json") phase=$phase logout_all=$logout sessions_removed=${nsess:-0}${moff:+ modules_off=$moff}"
declare -F audit_log >/dev/null && audit_log "users-convert" "contest=$contest by=$SESSION_LOGIN"
jq -cs . "$W/creds.jsonl" > "$W/creds.json"
ok_json_slurp '{converted:true, credentials:$cr[0], counts:$rp[0].counts, sessions_removed:$ns,
                registrations_archived:(if $ar != "" then $ar else null end),
                modules_off:(if $mo != "" then [$mo] else [] end)}' cr "$(cat "$W/creds.json")" \
  --argjson ns "${nsess:-0}" --arg ar "${arch:-}" --arg mo "${moff:-}" --slurpfile rp "$W/report.json"
