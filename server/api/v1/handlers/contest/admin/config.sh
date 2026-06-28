# GET/POST /contest/admin/config?contest=<id>  (admin DO contest)
# GET  -> {name,mode,start,end,letters[],colors,regions,teams_meta,basic{...}}
# POST {colors?,regions?,teams_meta?,basic?} -> grava balloons/regions/teams-meta + conf basic.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
cdir="$CONTESTSDIR/$contest"

if [[ "${REQUEST_METHOD:-GET}" == GET ]]; then
  CONTEST_NAME=""; CONTEST_TYPE=""; CONTEST_START=0; CONTEST_END=0
  LOCALE=""; LOGIN_START_TIME=""; LOGIN_ENABLED=""; FREEZE_TIME=""; PROBS=()
  load_contest_conf "$contest"
  declare -a LT; for ((i=3;i<${#PROBS[@]};i+=5)); do LT+=("${PROBS[$i]}"); done
  letters="$( ((${#LT[@]})) && printf '%s\n' "${LT[@]}" | jq -R . | jq -cs . || echo '[]')"
  colors="$( [[ -f "$cdir/balloons.json" ]] && jq -c . "$cdir/balloons.json" 2>/dev/null || echo '{}')"
  regions="$( [[ -f "$cdir/regions.json" ]] && jq -c . "$cdir/regions.json" 2>/dev/null || echo '[]')"
  teams="$( [[ -f "$cdir/teams-meta.json" ]] && jq -c '.rules // (if type=="array" then . else [] end)' "$cdir/teams-meta.json" 2>/dev/null || echo '[]')"
  le="$([[ "$LOGIN_ENABLED" == n ]] && echo false || echo true)"
  ok_json '{name:$nm, mode:$md, start:$st, end:$en, letters:$lt, colors:$co, regions:$rg, teams_meta:$tm,
            basic:{locale:$loc, login_start:$lst, login_enabled:$le, freeze:$fz}}' \
    --arg nm "$CONTEST_NAME" --arg md "${CONTEST_TYPE:-icpc}" --argjson st "${CONTEST_START:-0}" --argjson en "${CONTEST_END:-0}" \
    --argjson lt "$letters" --argjson co "$colors" --argjson rg "$regions" --argjson tm "$teams" \
    --arg loc "${LOCALE:-pt}" --argjson lst "${LOGIN_START_TIME:-0}" --argjson le "$le" --argjson fz "${FREEZE_TIME:-0}"
  exit 0
fi

require_method POST
source "$_LIBDIR/contest-create.sh"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"

if jq -e 'has("colors")' >/dev/null 2>&1 <<<"$body"; then
  c="$(jq -c '.colors' <<<"$body")"
  if [[ "$(jq 'length' <<<"$c" 2>/dev/null)" -gt 0 ]]; then printf '%s' "$c" > "$cdir/balloons.json"; else rm -f "$cdir/balloons.json"; fi
fi
if jq -e 'has("regions")' >/dev/null 2>&1 <<<"$body"; then
  r="$(jq -c '.regions' <<<"$body")"
  if [[ "$(jq 'length' <<<"$r" 2>/dev/null)" -gt 0 ]]; then printf '%s' "$r" > "$cdir/regions.json"; else rm -f "$cdir/regions.json"; fi
fi
if jq -e 'has("teams_meta")' >/dev/null 2>&1 <<<"$body"; then
  t="$(jq -c '.teams_meta' <<<"$body")"
  if [[ "$(jq 'length' <<<"$t" 2>/dev/null)" -gt 0 ]]; then jq -cn --argjson r "$t" '{rules:$r}' > "$cdir/teams-meta.json"; else rm -f "$cdir/teams-meta.json"; fi
fi
if jq -e 'has("basic")' >/dev/null 2>&1 <<<"$body"; then
  bl="$(jq -r '.basic.locale // empty' <<<"$body")"; [[ "$bl" =~ ^(pt|en)$ ]] && cc_set_conf_var "$contest" LOCALE "$bl"
  bs="$(jq -r '.basic.login_start // empty' <<<"$body")"; [[ "$bs" =~ ^[0-9]+$ ]] && cc_set_conf_var "$contest" LOGIN_START_TIME "$bs"
  bf="$(jq -r '.basic.freeze // empty' <<<"$body")"; [[ "$bf" =~ ^[0-9]+$ ]] && cc_set_conf_var "$contest" FREEZE_TIME "$bf"
  if [[ "$(jq -r '.basic.login_enabled' <<<"$body")" == "false" ]]; then cc_set_conf_var "$contest" LOGIN_ENABLED n; else cc_del_conf_var "$contest" LOGIN_ENABLED; fi
fi
audit_log_to "$contest" config "$(jq -cr 'keys|join(",")' <<<"$body" 2>/dev/null | head -c 200)"
ok_json '{saved:true}'
