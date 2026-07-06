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
  FREEZE_TIME=""; LOCALE=""; SHOWCODE=""; SHOWLOG=""; SHOWEDITOR=""; ALLOWLATEUSER=""; LOGIN_UA_SUBSTRING=""; SCORE_ANON=""; SHOWTL=""; LANGUAGES=""; SCORE_FULL_USERS=""; BACKUP=""; PRINT=""; MANUAL_VERDICT=""; SECRET=""
  PENALTY_MINUTES=""; PENALTY_VERDICTS="__unset"
  load_contest_conf "$contest"
  langs_json='[]'; [[ -n "$LANGUAGES" ]] && langs_json="$(printf '%s\n' $LANGUAGES | grep -v '^$' | jq -R . | jq -cs .)"
  sfu_json='[]'; [[ -n "$SCORE_FULL_USERS" ]] && sfu_json="$(printf '%s\n' $SCORE_FULL_USERS | grep -v '^$' | jq -R . | jq -cs .)"
  # penalidade ICPC: default (var ausente) = 20 min / PENALTY_CODES_DEFAULT; '' = lista vazia
  [[ "$PENALTY_MINUTES" =~ ^[0-9]+$ ]] || PENALTY_MINUTES=20
  [[ "$PENALTY_VERDICTS" == "__unset" ]] && PENALTY_VERDICTS="$PENALTY_CODES_DEFAULT"
  pvd_json="$(jq -cn --arg pv "$PENALTY_VERDICTS" '$pv|split(" ")|map(select(length>0))')"
  ok_json '{name:$nm, start:$st, end:$en, login_start:$ls, login_enabled:$le, freeze:$fz, locale:$loc,
            show_code:$sc, show_log:$sl, show_editor:$se, allow_late:$al, login_ua_substring:$ua, score_anon:$sa,
            show_tl:$stl, languages:$langs, score_full_users:$sfu, allow_backup:$ab, allow_print:$ap, manual_verdict:$mv,
            secret:$sec, mode:$mode, penalty_minutes:$pm, penalty_verdicts:$pvd}' \
    --arg mode "$(contest_score_mode "$contest")" \
    --argjson pm "$PENALTY_MINUTES" --argjson pvd "$pvd_json" \
    --arg nm "$CONTEST_NAME" --argjson st "${CONTEST_START:-0}" --argjson en "${CONTEST_END:-0}" \
    --argjson ls "${LOGIN_START_TIME:-0}" --argjson fz "${FREEZE_TIME:-0}" --arg loc "${LOCALE:-pt}" \
    --argjson le "$([[ "$LOGIN_ENABLED" == n ]] && echo false || echo true)" \
    --argjson sc "$([[ "$SHOWCODE" == 1 ]] && echo true || echo false)" \
    --argjson sl "$([[ "$SHOWLOG" == 0 ]] && echo false || echo true)" \
    --argjson se "$([[ "$SHOWEDITOR" == 0 ]] && echo false || echo true)" \
    --argjson al "$([[ "$ALLOWLATEUSER" == y ]] && echo true || echo false)" \
    --arg ua "$LOGIN_UA_SUBSTRING" \
    --argjson sa "$([[ "$SCORE_ANON" == 1 ]] && echo true || echo false)" \
    --argjson stl "$([[ "$SHOWTL" == 0 ]] && echo false || echo true)" \
    --argjson langs "$langs_json" --argjson sfu "$sfu_json" \
    --argjson ab "$([[ "$BACKUP" == 0 ]] && echo false || echo true)" \
    --argjson ap "$([[ "$PRINT" == 0 ]] && echo false || echo true)" \
    --argjson mv "$([[ "$MANUAL_VERDICT" == 1 ]] && echo true || echo false)" \
    --argjson sec "$([[ "$SECRET" == 1 ]] && echo true || echo false)"
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
    case "$2" in LOGIN_ENABLED|SHOWLOG|SHOWEDITOR|SHOWTL|BACKUP|PRINT) delvar "$2";; *) setvar "$2" "$3";; esac
  else
    case "$2" in LOGIN_ENABLED) setvar LOGIN_ENABLED n;; SHOWLOG) setvar SHOWLOG 0;; SHOWEDITOR) setvar SHOWEDITOR 0;; SHOWTL) setvar SHOWTL 0;; BACKUP) setvar BACKUP 0;; PRINT) setvar PRINT 0;; *) delvar "$2";; esac
  fi
}
bset show_code   SHOWCODE 1
bset allow_late  ALLOWLATEUSER y
bset score_anon  SCORE_ANON 1
bset login_enabled LOGIN_ENABLED _
bset show_log    SHOWLOG _
bset show_editor SHOWEDITOR _
bset show_tl     SHOWTL _
bset allow_backup BACKUP _
bset allow_print PRINT _
bset manual_verdict MANUAL_VERDICT 1
bset secret      SECRET 1

if has login_ua_substring; then
  v="$(jq -r '.login_ua_substring' <<<"$body")"; v="${v//$'\n'/}"
  (( ${#v} <= 200 )) || fail 422 "substring muito longa" "ua_long"
  [[ -n "$v" ]] && setvar LOGIN_UA_SUBSTRING "$v" || delvar LOGIN_UA_SUBSTRING
fi

# whitelist de linguagens do contest (ids canônicos minúsculos, espaço-separados; vazio = todas)
if has languages; then
  lj="$(jq -r '(.languages // []) | map(ascii_downcase | select(test("^[a-z0-9_+.-]+$"))) | unique | join(" ")' <<<"$body")"
  [[ -n "$lj" ]] && setvar LANGUAGES "$lj" || delvar LANGUAGES
fi

# logins que veem o placar COMPLETO (sem freeze) além de .admin/.judge (espaço-separados)
if has score_full_users; then
  su="$(jq -r '(.score_full_users // []) | map(select(test("^[A-Za-z0-9._@#+-]+$"))) | unique | join(" ")' <<<"$body")"
  [[ -n "$su" ]] && setvar SCORE_FULL_USERS "$su" || delvar SCORE_FULL_USERS
fi

# penalidade do placar ICPC (default = var ausente; editar em prova recomputa o placar
# no próximo GET — conf mais novo que var/.metrics-stamp dispara o recompute em massa)
if has penalty_minutes; then
  v="$(jq -r '.penalty_minutes' <<<"$body")"
  { [[ "$v" =~ ^[0-9]+$ ]] && (( v <= 100000 )); } || fail 422 "penalty_minutes inválido" "penalty_minutes_invalid"
  if (( v == 20 )); then delvar PENALTY_MINUTES; else setvar PENALTY_MINUTES "$v"; fi
fi
if has penalty_verdicts; then
  pv="$(penalty_codes_normalize "$(jq -c '.penalty_verdicts' <<<"$body")")" \
    || fail 422 "penalty_verdicts inválido (use wa/tle/mle/rte/ce)" "penalty_verdicts_invalid"
  if [[ "$pv" == "$PENALTY_CODES_DEFAULT" ]]; then delvar PENALTY_VERDICTS; else setvar PENALTY_VERDICTS "$pv"; fi
fi

audit_log_to "$contest" settings "$( ((${#CH[@]})) && { IFS=,; echo "${CH[*]}"; } || echo nada )"
ok_json '{saved:true, changed:$c}' \
  --argjson c "$( ((${#CH[@]})) && printf '%s\n' "${CH[@]}" | jq -R . | jq -cs . || echo '[]')"
