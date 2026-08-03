# GET/POST /contest/admin/registrations?contest=<c>   (admin DO contest; leitura tb p/ .cjudge)
#
# INSCRIÇÕES do contest: quem entrou (individual/time), convites pendentes e a JANELA.
# O competidor inscrito é materializado no store por-usuário (lib/registration.sh), então o
# placar/impressão/balões já enxergam sem saber que existe roster.
#
# GET  -> {enabled, window, team_max, teams_allowed, teams:[…], individuals:[…], totals}
# POST {action}:
#   enable        — liga o registro (cria o roster vazio + semeia as coortes individual/times)
#   disable       — desliga (o roster vai p/ registrations.json.off; ninguém é desmaterializado)
#   window        {open?,close?,late_minutes?,team_max?,teams?} — grava no conf (epoch)
#   add           {login}          — inscreve alguém à mão (individual)
#   rm            {login}          — tira da inscrição (sai do time, se estiver em um)
#   team-add      {name, members:[…]} — cria um time pronto (sem convite; uso do organizador)
#   team-rm       {team}           — dissolve
#   materialize   — reescreve os overlays do store a partir do roster (conserto)
require_auth_contest "$(param contest)"
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
source "$_DIR/lib/users.sh"
source "$_DIR/lib/cohorts.sh"
source "$_DIR/lib/registration.sh"

cdir="$CONTESTSDIR/$contest"
if [[ "$REQUEST_METHOD" != POST ]]; then
  is_admin || is_chief || fail 403 "Apenas o admin do contest" "admin_required"
else
  is_admin || fail 403 "Apenas o admin do contest" "admin_required"
fi

_emit(){
  local st op cl lt out
  IFS=$'\t' read -r st op cl lt < <(reg_window "$contest")
  # corpo ANTES do header: jq que falha depois de emit_json vira 200 mudo com corpo vazio
  out="$(reg_get "$contest" | jq -c --arg st "$st" --argjson op "${op:-0}" --argjson cl "${cl:-0}" \
      --argjson lt "${lt:-0}" --argjson max "$(reg_team_max "$contest")" \
      --argjson en "$(reg_enabled "$contest" && echo true || echo false)" \
      --argjson tok "$(reg_teams_allowed "$contest" && echo true || echo false)" '
    { success:true, enabled:$en, teams_allowed:$tok, team_max:$max,
      window:{state:$st, opens_at:$op, closes_at:$cl, late_until:$lt},
      teams: [ .teams | to_entries[]
               | {login:.key, name:.value.name, captain:.value.captain,
                  members:.value.members, invited:.value.invited, cohort:.value.cohort,
                  created_at:.value.created_at} ] | sort_by(.name),
      individuals: [ .entries | to_entries[] | select(.value.kind == "individual")
                     | {login:.key, cohort:.value.cohort, at:.value.at} ] | sort_by(.login),
      totals: { people:(.entries | length), teams:(.teams | length),
                individuals:([.entries[] | select(.kind=="individual")] | length),
                invites:([.teams[] | (.invited // []) | length] | add // 0) } }')"
  [[ -n "$out" ]] || fail 500 "Falha ao montar as inscrições" "reg_render_failed"
  emit_json 200 OK; printf '%s\n' "$out"
}
[[ "$REQUEST_METHOD" == POST ]] || { _emit; exit 0; }

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // empty' <<<"$body")"
[[ -n "$action" ]] || fail 400 "Informe a ação" "action_missing"

mkdir -p "$cdir/var"
exec 9>"$(reg_lock_file "$contest")" || fail 500 "Falha ao obter lock" "lock_fail"
flock 9

case "$action" in
  enable)
    reg_enabled "$contest" || { reg_save "$contest" '{"version":1,"teams":{},"entries":{}}'; reg_seed_cohorts "$contest"; }
    audit_log_to "$contest" reg-enable "" ;;
  disable)
    [[ -f "$(reg_file "$contest")" ]] && mv -f "$(reg_file "$contest")" "$(reg_file "$contest").off"
    audit_log_to "$contest" reg-disable "" ;;
  window)
    # epochs no conf, no mesmo caminho do settings (cc_set_conf_var); vazio/null APAGA a chave
    source "$_DIR/lib/contest-create.sh"
    _set(){ # <chave> <valor-jq>
      local k="$1" v; v="$(jq -r "$2 // empty" <<<"$body")"
      [[ -z "$v" || "$v" == null ]] && return 0
      [[ "$v" =~ ^[0-9]+$ ]] || fail 400 "Valor inválido p/ $k" "bad_value"
      cc_set_conf_var "$contest" "$k" "$v"
    }
    _set REG_OPEN '.open'; _set REG_CLOSE '.close'
    _set REG_LATE_MINUTES '.late_minutes'; _set REG_TEAM_MAX '.team_max'
    case "$(jq -r '.teams // empty' <<<"$body")" in
      false) cc_set_conf_var "$contest" REG_TEAMS n ;;
      true)  cc_del_conf_var "$contest" REG_TEAMS ;;
    esac
    audit_log_to "$contest" reg-window "$(jq -c '{open,close,late_minutes,team_max,teams}' <<<"$body")" ;;
  add)
    login="$(jq -r '.login // empty' <<<"$body")"
    valid_id "$login" || fail 400 "Login inválido" "login_invalid"
    user_exists "$(reg_source_of "$contest")" "$login" || user_exists "$contest" "$login" \
      || fail 404 "Conta não encontrada" "user_notfound"
    reg_enabled "$contest" || { reg_save "$contest" '{"version":1,"teams":{},"entries":{}}'; reg_seed_cohorts "$contest"; }
    out="$(reg_register_individual "$contest" "$login")" || fail 409 "Não deu p/ inscrever ($out)" "$out"
    audit_log_to "$contest" reg-add "login=$login" ;;
  rm)
    login="$(jq -r '.login // empty' <<<"$body")"
    valid_id "$login" || fail 400 "Login inválido" "login_invalid"
    out="$(reg_cancel "$contest" "$login")" || fail 409 "Não deu p/ remover ($out)" "$out"
    audit_log_to "$contest" reg-rm "login=$login" ;;
  team-add)
    name="$(jq -r '.name // empty' <<<"$body")"
    mapfile -t _mem < <(jq -r '(.members // [])[]' <<<"$body")
    (( ${#_mem[@]} )) || fail 400 "Informe os membros" "members_missing"
    reg_enabled "$contest" || { reg_save "$contest" '{"version":1,"teams":{},"entries":{}}'; reg_seed_cohorts "$contest"; }
    cap="${_mem[0]}"
    valid_id "$cap" || fail 400 "Login inválido: $cap" "login_invalid"
    t="$(reg_team_create "$contest" "$cap" "$name")" || fail 409 "Não deu p/ criar o time ($t)" "$t"
    for m in "${_mem[@]:1}"; do
      valid_id "$m" || continue
      reg_team_invite "$contest" "$cap" "$m" >/dev/null 2>&1 && reg_team_accept "$contest" "$m" "$t" >/dev/null 2>&1
    done
    audit_log_to "$contest" reg-team-add "team=$t membros=${_mem[*]}" ;;
  team-rm)
    t="$(jq -r '.team // empty' <<<"$body")"
    valid_id "$t" || fail 400 "Time inválido" "team_invalid"
    cap="$(reg_get "$contest" | jq -r --arg t "$t" '.teams[$t].captain // empty')"
    [[ -n "$cap" ]] || fail 404 "Time não encontrado" "team_notfound"
    out="$(reg_team_dissolve "$contest" "$cap")" || fail 409 "Não deu p/ dissolver ($out)" "$out"
    audit_log_to "$contest" reg-team-rm "team=$t" ;;
  materialize)
    n=0
    while IFS=$'\t' read -r l co; do
      [[ -n "$l" ]] || continue
      reg_materialize_login "$contest" "$l" "$co" && n=$(( n + 1 ))
    done < <(reg_get "$contest" | jq -r '.entries | to_entries[] | select(.value.kind=="individual")
                                          | [.key, (.value.cohort // "individual")] | @tsv')
    while IFS= read -r t; do
      [[ -n "$t" ]] || continue
      reg_materialize_team "$contest" "$t" && n=$(( n + 1 ))
    done < <(reg_get "$contest" | jq -r '.teams | keys[]')
    audit_log_to "$contest" reg-materialize "n=$n" ;;
  *) fail 400 "Ação desconhecida" "action_invalid" ;;
esac

flock -u 9
_emit
