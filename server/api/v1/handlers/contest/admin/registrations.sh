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
#   team-meta     {team, univ?, ai?, flag?} — a organização ajusta a apresentação de um time
#   individual-meta {login, univ?, ai?, flag?} — idem p/ um inscrito INDIVIDUAL
#   materialize   — reescreve os overlays do store a partir do roster (conserto)
#   invite-remind {team, login}   — o mojinho cutuca UM convite pendente por DM
#   invite-remind-all             — idem p/ TODOS os convites pendentes do contest
#     (o aviso automático da véspera é da lib/invite-notify.sh, varrida no poll do bot)
require_auth_contest "$(param contest)"
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
source "$_DIR/lib/users.sh"
source "$_DIR/lib/cohorts.sh"
source "$_DIR/lib/registration.sh"
source "$_DIR/lib/invite-notify.sh"

cdir="$CONTESTSDIR/$contest"
if [[ "$REQUEST_METHOD" != POST ]]; then
  is_admin || is_chief || fail 403 "Apenas o admin do contest" "admin_required"
else
  is_admin || fail 403 "Apenas o admin do contest" "admin_required"
fi

_emit(){   # [<json-extra p/ mesclar na resposta>]
  local extra="${1:-}" st op cl lt anc rnd out
  IFS=$'\t' read -r st op cl lt anc rnd < <(reg_window "$contest")
  # corpo ANTES do header: jq que falha depois de emit_json vira 200 mudo com corpo vazio
  local photos='[]'
  photos="$( ( set +o noglob; shopt -s nullglob
    for f in "$cdir"/users/*/photo.png; do d="${f%/photo.png}"; printf '%s\n' "${d##*/}"; done ) \
    | jq -R . | jq -cs .)"
  [[ -n "$photos" ]] || photos='[]'
  # quem tem Telegram vinculado entre os CONVIDADOS (é quem o lembrete alcança) + a
  # contabilidade dos avisos já enviados. São poucos: um arquivo lido por convidado.
  local tgs invf
  tgs="$( reg_get "$contest" | jq -r '[.teams[] | (.invited // [])[]] | unique[]' 2>/dev/null \
          | while IFS= read -r l; do [[ -n "$l" ]] || continue
              [[ -n "$(inv_chat_of "$contest" "$l")" ]] && printf '%s\n' "$l"
            done | jq -R . | jq -cs . )"
  [[ -n "$tgs" ]] || tgs='[]'
  invf="$(mktemp)"; inv_get "$contest" > "$invf"
  out="$(reg_get "$contest" | jq -c --argjson photos "$photos" --arg st "$st" --argjson op "${op:-0}" --argjson cl "${cl:-0}" \
      --argjson lt "${lt:-0}" --argjson max "$(reg_team_max "$contest")" \
      --argjson anc "${anc:-0}" --arg rnd "${rnd:-}" --arg kind "$(reg_round_kind "$contest")" \
      --argjson gate "$(reg_gate_active "$contest" && echo true || echo false)" \
      --argjson en "$(reg_enabled "$contest" && echo true || echo false)" \
      --argjson tok "$(reg_teams_allowed "$contest" && echo true || echo false)" \
      --argjson remind "$(reg_remind_on "$contest" && echo true || echo false)" \
      --argjson tgs "$tgs" --slurpfile inv "$invf" '
    (($inv[0].items) // {}) as $im
    | { success:true, enabled:$en, teams_allowed:$tok, team_max:$max, remind:$remind,
      window:{state:$st, opens_at:$op, closes_at:$cl, late_until:$lt,
              official_start:$anc, official_round:$rnd},
      round_kind:$kind, gate_active:$gate,
      teams: [ .teams | to_entries[] | .key as $tm | .value as $v
               | {login:$tm, name:$v.name, captain:$v.captain,
                  members:$v.members, invited:$v.invited, cohort:$v.cohort,
                  created_at:$v.created_at, univ:($v.univ // ""), flag:($v.flag // ""),
                  ai:(if ($v | has("ai")) then $v.ai else null end),
                  has_photo:(($photos | index($tm)) != null),
                  invited_meta: [ ($v.invited // [])[] | . as $l
                                  | (($im[$tm + "|" + $l]) // {}) as $e
                                  | {login:$l, at:($e.at // 0), dm_at:($e.dm // 0),
                                     warned_at:($e.warn // 0), tg:(($tgs | index($l)) != null)} ]} ]
             | sort_by(.name),
      individuals: [ .entries | to_entries[] | select(.value.kind == "individual")
                     | {login:.key, cohort:.value.cohort, at:.value.at,
                        univ:(.value.univ // ""), flag:(.value.flag // ""),
                        ai:(if (.value | has("ai")) then .value.ai else null end)} ]
                   | sort_by(.login),
      totals: { people:(.entries | length), teams:(.teams | length),
                individuals:([.entries[] | select(.kind=="individual")] | length),
                invites:([.teams[] | (.invited // []) | length] | add // 0),
                invites_no_tg:([.teams[] | (.invited // [])[] | . as $l
                                | select(($tgs | index($l)) == null)] | length) } }')"
  rm -f "$invf"
  [[ -n "$out" ]] || fail 500 "Falha ao montar as inscrições" "reg_render_failed"
  if [[ -n "$extra" ]]; then
    out="$(jq -c --argjson x "$extra" '. + $x' <<<"$out")" \
      || fail 500 "Falha ao montar as inscrições" "reg_render_failed"
  fi
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
    # ⚠ `.teams // empty` NÃO serve p/ BOOLEANO: o // do jq trata `false` como vazio, então
    # desmarcar a caixinha nunca chegava aqui (bug silencioso: "aceita times" não desligava).
    _bool(){ jq -r --arg k "$1" 'if has($k) then (.[$k] | tostring) else "" end' <<<"$body"; }
    case "$(_bool teams)" in
      false) cc_set_conf_var "$contest" REG_TEAMS n ;;
      true)  cc_del_conf_var "$contest" REG_TEAMS ;;
    esac
    # aviso automático do convite pendente (default ligado; n = desligado)
    case "$(_bool remind)" in
      false) cc_set_conf_var "$contest" REG_REMIND n ;;
      true)  cc_del_conf_var "$contest" REG_REMIND ;;
    esac
    audit_log_to "$contest" reg-window "$(jq -c '{open,close,late_minutes,team_max,teams,remind}' <<<"$body")" ;;
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
  team-meta)
    t="$(jq -r '.team // empty' <<<"$body")"
    valid_id "$t" || fail 400 "Time inválido" "team_invalid"
    cap="$(reg_get "$contest" | jq -r --arg t "$t" '.teams[$t].captain // empty')"
    [[ -n "$cap" ]] || fail 404 "Time não encontrado" "team_notfound"
    u="$(jq -r '.univ // ""' <<<"$body")"; a="$(jq -r '.ai // ""' <<<"$body")"
    fl="$(jq -r '.flag // ""' <<<"$body")"
    case "$a" in yes|no|"") ;; *) fail 400 "ai deve ser yes|no" "ai_invalid";; esac
    # a lib exige capitão: o admin ajusta EM NOME do capitão do time
    out="$(reg_team_meta "$contest" "$cap" "$u" "$a" "$fl")" || fail 400 "Não deu ($out)" "$out"
    audit_log_to "$contest" reg-team-meta-admin "team=$t univ=$u ai=$a flag=$fl" ;;
  individual-meta)
    login="$(jq -r '.login // empty' <<<"$body")"
    valid_id "$login" || fail 400 "Login inválido" "login_invalid"
    u="$(jq -r '.univ // ""' <<<"$body")"; a="$(jq -r '.ai // ""' <<<"$body")"
    fl="$(jq -r '.flag // ""' <<<"$body")"
    case "$a" in yes|no|"") ;; *) fail 400 "ai deve ser yes|no" "ai_invalid";; esac
    out="$(reg_individual_meta "$contest" "$login" "$u" "$a" "$fl")" || fail 400 "Não deu ($out)" "$out"
    audit_log_to "$contest" reg-individual-meta-admin "login=$login univ=$u ai=$a flag=$fl" ;;
  team-rm)
    t="$(jq -r '.team // empty' <<<"$body")"
    valid_id "$t" || fail 400 "Time inválido" "team_invalid"
    cap="$(reg_get "$contest" | jq -r --arg t "$t" '.teams[$t].captain // empty')"
    [[ -n "$cap" ]] || fail 404 "Time não encontrado" "team_notfound"
    out="$(reg_team_dissolve "$contest" "$cap")" || fail 409 "Não deu p/ dissolver ($out)" "$out"
    audit_log_to "$contest" reg-team-rm "team=$t" ;;
  invite-remind|invite-remind-all)
    # o botão "lembrar" do painel. Carimba `dm` (intervalo mínimo entre pings) mas NÃO `warn`:
    # cutucar hoje não pode cancelar o aviso automático da véspera, que é o mais valioso.
    IFS=$'\t' read -r wst wo wc wl wa wr < <(reg_window "$contest")
    [[ "$wst" == closed ]] \
      && fail 409 "As inscrições já fecharam — o convite não pode mais ser aceito" "registration_closed"
    inv_reconcile "$contest" >/dev/null 2>&1
    sent=0; skipped=()
    if [[ "$action" == invite-remind ]]; then
      t="$(jq -r '.team // empty' <<<"$body")"; login="$(jq -r '.login // empty' <<<"$body")"
      valid_id "$t" || fail 400 "Time inválido" "team_invalid"
      valid_id "$login" || fail 400 "Login inválido" "login_invalid"
      reg_get "$contest" | jq -e --arg t "$t" --arg l "$login" \
          '((.teams[$t].invited // []) | index($l)) != null' >/dev/null 2>&1 \
        || fail 404 "Não há convite pendente desse time p/ esse login" "no_invite"
      out="$(inv_notify "$contest" "$t" "$login" remind)"
      case "$out" in
        sent)        sent=1 ;;
        no_telegram) fail 409 "$login não tem Telegram vinculado — não dá p/ avisar por DM" "no_telegram" ;;
        *)           fail 500 "Não deu p/ enfileirar o aviso (${out:-?})" "${out:-remind_failed}" ;;
      esac
      audit_log_to "$contest" reg-invite-remind "team=$t login=$login" ;
    else
      while IFS=$'\t' read -r it il iat idm iwn; do
        [[ -n "$it" && -n "$il" ]] || continue
        if [[ "$(inv_notify "$contest" "$it" "$il" remind)" == sent ]]
          then sent=$(( sent + 1 ))
          else skipped+=("$il"); fi
      done < <(inv_pending "$contest")
      audit_log_to "$contest" reg-invite-remind-all "n=$sent sem_telegram=${#skipped[@]}"
    fi
    skipjson="$(printf '%s\n' ${skipped[@]+"${skipped[@]}"} | grep -v '^[[:space:]]*$' | jq -R . | jq -cs .)"
    [[ -n "$skipjson" ]] || skipjson='[]'
    extra="$(jq -cn --argjson s "$sent" --argjson k "$skipjson" \
              '{remind_result:{sent:$s, skipped:$k}}')" ;;
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
_emit "${extra:-}"
