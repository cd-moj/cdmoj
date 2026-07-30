# GET/POST /contest/admin/ua-gate?contest=<c>
# GATE DE NAVEGADOR POR SEDE. A imagem de prova de cada sede manda um UA que carrega um pedaço do
# próprio login do time (teambrspso001 -> "brspso"); aqui se configura essa regra, os overrides
# por sede e os ISENTOS. Motor: lib/ua-gate.sh. Leitura: admin ou juiz-chefe. Escrita: só admin.
#
# GET  [?login=<l>]  -> {gate:{…}, legacy, regions:[…], check?:{login,expected,region}}
#                       (`login` = dry-run: o que se espera daquele time, sem ele precisar logar)
# POST {action}:
#   set     {mode?, from_login?:{regex,expect}, by_region?:{}, by_regex?:[], exempt?:[], fallback?}
#   check   {login}    — igual ao GET com ?login=
require_auth_contest "$(param contest)"
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/ua-gate.sh"

_ug_check(){  # <login> -> {login,expected,region,exempt}
  local l="$1" exp reg
  exp="$(ug_expected "$contest" "$l")"
  reg="$(ug_region_of "$contest" "$l")"
  jq -cn --arg l "$l" --arg e "$exp" --arg r "$reg" \
    '{login:$l, expected:$e, region:$r, gated:($e != "")}'
}

if [[ "$REQUEST_METHOD" == GET ]]; then
  is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
  chk=null
  l="$(param login)"
  if [[ -n "$l" ]]; then
    valid_id "$l" || fail 422 "login inválido" "login_invalid"
    chk="$(_ug_check "$l")"
  fi
  regions='[]'
  [[ -s "$CONTESTSDIR/$contest/regions.json" ]] && regions="$(jq -c \
    '[.. | objects | select((.regex // "") != "") | {name:(.name // .regex), regex}]' \
    "$CONTESTSDIR/$contest/regions.json" 2>/dev/null)"
  [[ -n "$regions" ]] || regions='[]'
  body="$(jq -cn --argjson g "$(ug_get "$contest")" --arg legacy "$(ug_legacy "$contest")" \
     --argjson r "$regions" --argjson chk "$chk" \
     '{success:true, gate:$g, legacy:$legacy, regions:$r, check:$chk}')"
  [[ -n "$body" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
  emit_json 200 OK; printf '%s\n' "$body"; exit 0
fi

require_method POST
bodyf="$(read_body_file)"
jq -e . "$bodyf" >/dev/null 2>&1 || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // "set"' "$bodyf")"

if [[ "$action" == check ]]; then
  is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
  l="$(jq -r '.login // ""' "$bodyf")"
  valid_id "$l" || fail 422 "login inválido" "login_invalid"
  ok_json '{check:$c}' --argjson c "$(_ug_check "$l")"
  exit 0
fi

is_admin || fail 403 "Apenas o admin do contest" "admin_required"
[[ "$action" == set ]] || fail 400 "action inválida" "action_invalid"

# regex tem de COMPILAR (regra quebrada silenciaria o gate inteiro) — mesma validação do
# time-overrides.sh, que é o precedente de regra-por-regex no repo.
_rx_ok(){ [[ -z "$1" ]] && return 0; jq -n --arg r "$1" '"x" | test($r)' >/dev/null 2>&1; }

g="$(ug_get "$contest")"
if jq -e 'has("mode")' "$bodyf" >/dev/null 2>&1; then
  m="$(jq -r '.mode' "$bodyf")"
  case "$m" in enforce|off) ;; *) fail 422 "mode deve ser enforce|off" "mode_invalid";; esac
  g="$(jq -c --arg m "$m" '.mode=$m' <<<"$g")"
fi
if jq -e 'has("from_login")' "$bodyf" >/dev/null 2>&1; then
  if jq -e '.from_login == null or (.from_login.regex // "") == ""' "$bodyf" >/dev/null 2>&1; then
    g="$(jq -c '.from_login=null' <<<"$g")"
  else
    rx="$(jq -r '.from_login.regex' "$bodyf")"; ex="$(jq -r '.from_login.expect // "\\1"' "$bodyf")"
    _rx_ok "$rx" || fail 422 "regex inválida: $rx" "regex_invalid"
    (( ${#rx} <= 200 && ${#ex} <= 200 )) || fail 422 "regra muito longa" "rule_long"
    g="$(jq -c --arg r "$rx" --arg e "$ex" '.from_login={regex:$r, expect:$e}' <<<"$g")"
  fi
fi
if jq -e 'has("by_region")' "$bodyf" >/dev/null 2>&1; then
  br="$(jq -c '(.by_region // {}) | with_entries(.value |= tostring)
        | with_entries(select((.key|length) > 0 and (.value|length) > 0 and (.value|length) <= 200))' "$bodyf")"
  [[ -n "$br" ]] || fail 422 "by_region inválido" "by_region_invalid"
  (( $(jq 'length' <<<"$br") <= 100 )) || fail 422 "máximo de 100 sedes" "too_many"
  g="$(jq -c --argjson v "$br" '.by_region=$v' <<<"$g")"
fi
if jq -e 'has("by_regex")' "$bodyf" >/dev/null 2>&1; then
  bx="$(jq -c '[ (.by_regex // [])[] | select(type=="object")
        | {regex:((.regex // "")|tostring), expect:((.expect // "")|tostring)}
        | select(.regex != "" and .expect != "" and (.regex|length) <= 200) ] | .[0:50]' "$bodyf")"
  [[ -n "$bx" ]] || fail 422 "by_regex inválido" "by_regex_invalid"
  while IFS= read -r rr; do _rx_ok "$rr" || fail 422 "regex inválida: $rr" "regex_invalid"; done \
    < <(jq -r '.[].regex' <<<"$bx")
  g="$(jq -c --argjson v "$bx" '.by_regex=$v' <<<"$g")"
fi
if jq -e 'has("exempt")' "$bodyf" >/dev/null 2>&1; then
  ex="$(jq -c '[ (.exempt // [])[] | tostring | select(length > 0 and length <= 200) ] | unique | .[0:200]' "$bodyf")"
  [[ -n "$ex" ]] || fail 422 "exempt inválido" "exempt_invalid"
  while IFS= read -r rr; do _rx_ok "$rr" || fail 422 "regex inválida: $rr" "regex_invalid"; done \
    < <(jq -r '.[]' <<<"$ex")
  g="$(jq -c --argjson v "$ex" '.exempt=$v' <<<"$g")"
fi
if jq -e 'has("fallback")' "$bodyf" >/dev/null 2>&1; then
  fb="$(jq -r '.fallback // ""' "$bodyf")"; fb="${fb//$'\n'/}"
  (( ${#fb} <= 200 )) || fail 422 "fallback muito longo" "fallback_long"
  g="$(jq -c --arg v "$fb" '.fallback=$v' <<<"$g")"
fi

ug_save "$contest" "$g"
audit_log_to "$contest" ua-gate-set "mode=$(jq -r '.mode' <<<"$g") sedes=$(jq -r '.by_region|length' <<<"$g") isentos=$(jq -r '.exempt|length' <<<"$g")"
ok_json '{saved:true, gate:$g}' --argjson g "$g"
