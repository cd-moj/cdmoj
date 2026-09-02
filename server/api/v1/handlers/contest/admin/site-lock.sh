# GET/POST /contest/admin/site-lock?contest=<c>   (GET: admin ou juiz-chefe; POST: só admin)
# TRAVA DE SEDE POR IP (lib/site-lock.sh). GET → {enabled, grace, claims:[{ip,until,first,last,
# logins,blocked,last_block,last_target,active}], blocks:[{at,ip,target,route,login}] (últimos
# do audit), claims_audit:[…]}. POST {action:"set", enabled, grace?} liga/desliga (conf
# SITE_LOCK/SITE_LOCK_GRACE); {action:"release", ip} solta um IP; {action:"claim-seen"} prende
# desde já todos os IPs que logaram na janela da rodada (aquecimento incluso). Tudo auditado.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
cdir="$CONTESTSDIR/$contest"

_sl_audit_json(){ # <action-prefix> [n] -> últimas linhas do audit com aquela ação, em JSON
  local act="$1" n="${2:-200}"
  [[ -s "$cdir/var/admin-audit.log" ]] || { printf '[]'; return 0; }
  awk -F'\t' -v a="$act" '$3 == a' "$cdir/var/admin-audit.log" | tail -n "$n" \
    | jq -Rn '[ inputs | split("\t") | select(length >= 4)
        | (.[3] | split(" ") | map(select(contains("="))) | map(split("=") | {key:.[0], value:(.[1:]|join("="))}) | from_entries) as $d
        | {at:(.[0]|tonumber? // 0), who:.[1], ip:($d.ip // ""), target:($d.target // ""), route:($d.route // ""),
           login:($d.login // ""), until:($d.until // "")} ] | reverse' 2>/dev/null || printf '[]'
}

if [[ "$REQUEST_METHOD" == GET ]]; then
  is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
  en=false; sl_enabled "$contest" && en=true
  cl="$(sl_list "$contest")"; [[ -n "$cl" ]] || cl='[]'
  bl="$(_sl_audit_json site-lock-block 200)"; ca="$(_sl_audit_json site-lock-claim 500)"
  ok_json '{enabled:$e, grace:$g, claims:$c[0], blocks:$b[0], claims_audit:$a[0]}' \
    --argjson e "$en" --argjson g "$(sl_grace "$contest")" \
    --slurpfile c <(printf '%s' "$cl") --slurpfile b <(printf '%s' "$bl") --slurpfile a <(printf '%s' "$ca")
  exit 0
fi

require_method POST
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // "set"' <<<"$body")"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
case "$action" in
  set)
    if jq -e '.enabled == true' <<<"$body" >/dev/null 2>&1; then cc_set_conf_var "$contest" SITE_LOCK 1
    else cc_set_conf_var "$contest" SITE_LOCK 0; fi
    g="$(jq -r '.grace // empty' <<<"$body")"
    if [[ -n "$g" ]]; then [[ "$g" =~ ^[0-9]+$ ]] && (( g <= 86400 )) || fail 422 "grace inválida (0..86400 s)" "grace_invalid"; cc_set_conf_var "$contest" SITE_LOCK_GRACE "$g"; fi
    audit_log_to "$contest" site-lock-set "enabled=$(jq -r '.enabled == true' <<<"$body") grace=${g:-$(sl_grace "$contest")}"
    en=false; sl_enabled "$contest" && en=true
    ok_json '{saved:true, enabled:$e, grace:$g}' --argjson e "$en" --argjson g "$(sl_grace "$contest")";;
  release)
    ip="$(jq -r '.ip // ""' <<<"$body")"; ip="${ip//[^0-9a-fA-F.:]/}"
    [[ -n "$ip" ]] || fail 400 "Informe o ip" "missing"
    sl_release "$contest" "$ip"
    audit_log_to "$contest" site-lock-release "ip=$ip"
    ok_json '{released:true, ip:$i}' --arg i "$ip";;
  claim-seen)
    # prende desde já os IPs de competidores vistos na janela da rodada (aquecimento incluso):
    # útil na manhã da prova, antes de o 1º time logar. Só com a trava LIGADA.
    sl_enabled "$contest" || fail 409 "Ligue a trava primeiro" "site_lock_off"
    source "$_DIR/lib/contest-rounds.sh"
    _r="$(rd_round "$contest" "$(rd_active "$contest")")"; [[ -n "$_r" ]] || _r='{}'
    _cs="$(jq -r '.start // 0' <<<"$_r")"; [[ "$_cs" =~ ^[0-9]+$ ]] || _cs=0
    _from=$(( _cs > 43200 ? _cs - 43200 : 0 ))
    n=0
    while IFS=$'\t' read -r _t _lg _ip _rest; do
      [[ "$_t" =~ ^[0-9]+$ ]] && (( _t >= _from )) || continue
      is_reserved_role_login "$_lg" && continue
      r="$(sl_claim "$contest" "$_ip" "$_lg")"; [[ "$r" == new ]] && ((n++))
    done < <(awk -F'\t' -v a="$_from" 'NF>=3 && $1+0>=a {print $1 "\t" $2 "\t" $3}' "$cdir/var/access.log" 2>/dev/null | sort -u -t$'\t' -k3,3)
    audit_log_to "$contest" site-lock-claim-seen "new=$n since=$_from"
    ok_json '{claimed:$n}' --argjson n "$n";;
  *) fail 400 "action inválida" "action_invalid";;
esac
