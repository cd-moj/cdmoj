# GET/POST /contest/admin/settings?contest=<id>  (admin DO contest)
# GET  -> configurações editáveis do contest.
# POST -> atualiza só os campos presentes no body (cada um validado) + auditoria.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_LIBDIR/contest-create.sh"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  CONTEST_NAME=""; CONTEST_START=0; CONTEST_END=0; LOGIN_START_TIME=""; LOGIN_ENABLED=""
  FREEZE_TIME=""; LOCALE=""; SHOWCODE=""; SHOWLOG=""; SHOWEDITOR=""; ALLOWLATEUSER=""; LOGIN_UA_SUBSTRING=""; SCORE_ANON=""; SHOWTL=""
  load_contest_conf "$contest"
  ok_json '{name:$nm, start:$st, end:$en, login_start:$ls, login_enabled:$le, freeze:$fz, locale:$loc,
            show_code:$sc, show_log:$sl, show_editor:$se, allow_late:$al, login_ua_substring:$ua, score_anon:$sa,
            show_tl:$stl}' \
    --arg nm "$CONTEST_NAME" --argjson st "${CONTEST_START:-0}" --argjson en "${CONTEST_END:-0}" \
    --argjson ls "${LOGIN_START_TIME:-0}" --argjson fz "${FREEZE_TIME:-0}" --arg loc "${LOCALE:-pt}" \
    --argjson le "$([[ "$LOGIN_ENABLED" == n ]] && echo false || echo true)" \
    --argjson sc "$([[ "$SHOWCODE" == 1 ]] && echo true || echo false)" \
    --argjson sl "$([[ "$SHOWLOG" == 0 ]] && echo false || echo true)" \
    --argjson se "$([[ "$SHOWEDITOR" == 0 ]] && echo false || echo true)" \
    --argjson al "$([[ "$ALLOWLATEUSER" == y ]] && echo true || echo false)" \
    --arg ua "$LOGIN_UA_SUBSTRING" \
    --argjson sa "$([[ "$SCORE_ANON" == 1 ]] && echo true || echo false)" \
    --argjson stl "$([[ "$SHOWTL" == 0 ]] && echo false || echo true)"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
declare -a CH
has(){ jq -e "has(\"$1\")" >/dev/null 2>&1 <<<"$body"; }
setvar(){ cc_set_conf_var "$contest" "$1" "$2"; CH+=("$1=$2"); }
delvar(){ cc_del_conf_var "$contest" "$1"; CH+=("$1=padrao"); }

if has name; then v="$(jq -r '.name' <<<"$body")"; { [[ -n "$v" ]] && (( ${#v} <= 160 )); } || fail 422 "nome inválido" "name_invalid"; setvar CONTEST_NAME "$v"; fi
for pair in start:CONTEST_START end:CONTEST_END login_start:LOGIN_START_TIME freeze:FREEZE_TIME; do
  k="${pair%%:*}"; var="${pair#*:}"
  has "$k" && { v="$(jq -r ".$k" <<<"$body")"; [[ "$v" =~ ^[0-9]+$ ]] || fail 422 "$k inválido" "int_invalid"; setvar "$var" "$v"; }
done
has locale && { v="$(jq -r '.locale' <<<"$body")"; [[ "$v" =~ ^(pt|en)$ ]] || fail 422 "locale inválido" "locale_invalid"; setvar LOCALE "$v"; }

bset(){ # <jsonkey> <VAR> <on-value-p/-positivos>
  has "$1" || return 0
  local on; on="$(jq -r ".$1" <<<"$body")"
  if [[ "$on" == true ]]; then
    case "$2" in LOGIN_ENABLED|SHOWLOG|SHOWEDITOR|SHOWTL) delvar "$2";; *) setvar "$2" "$3";; esac
  else
    case "$2" in LOGIN_ENABLED) setvar LOGIN_ENABLED n;; SHOWLOG) setvar SHOWLOG 0;; SHOWEDITOR) setvar SHOWEDITOR 0;; SHOWTL) setvar SHOWTL 0;; *) delvar "$2";; esac
  fi
}
bset show_code   SHOWCODE 1
bset allow_late  ALLOWLATEUSER y
bset score_anon  SCORE_ANON 1
bset login_enabled LOGIN_ENABLED _
bset show_log    SHOWLOG _
bset show_editor SHOWEDITOR _
bset show_tl     SHOWTL _

if has login_ua_substring; then
  v="$(jq -r '.login_ua_substring' <<<"$body")"; v="${v//$'\n'/}"
  (( ${#v} <= 200 )) || fail 422 "substring muito longa" "ua_long"
  [[ -n "$v" ]] && setvar LOGIN_UA_SUBSTRING "$v" || delvar LOGIN_UA_SUBSTRING
fi

audit_log_to "$contest" settings "$( ((${#CH[@]})) && { IFS=,; echo "${CH[*]}"; } || echo nada )"
ok_json '{saved:true, changed:$c}' \
  --argjson c "$( ((${#CH[@]})) && printf '%s\n' "${CH[@]}" | jq -R . | jq -cs . || echo '[]')"
