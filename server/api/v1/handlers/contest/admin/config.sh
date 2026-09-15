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

# colors: objeto com chaves = grava (substitui o arquivo inteiro: o editor manda todas as letras +
# enableSonic true/false); {} = NÃO MEXE (o editor devolve {} quando nada mudou — apagar aqui
# perdia as cores e desligava o módulo, relato de 2026-09-14); null = volta às cores padrão.
# Toda escrita/remoção derruba o cache de /contest/balloons (o frescor por -nt não vê arquivo
# apagado; a lista de presença em resp_cache_fresh também cobre, mas o explícito é grátis).
# (escritor único: cc_balloons_write/clear em lib/contest-create.sh — a troca de rodada usa o mesmo)
if jq -e 'has("colors")' >/dev/null 2>&1 <<<"$body"; then
  c="$(jq -c '.colors' <<<"$body")"
  if [[ "$c" == null ]]; then cc_balloons_clear "$contest"
  elif [[ "$(jq 'if type=="object" then length else 0 end' <<<"$c" 2>/dev/null)" -gt 0 ]]; then
    cc_balloons_write "$contest" "$c" || fail 500 "Falha ao gravar as cores" "colors_write"
  fi
fi
if jq -e 'has("regions")' >/dev/null 2>&1 <<<"$body"; then
  r="$(jq -c '.regions' <<<"$body")"
  if [[ "$(jq 'length' <<<"$r" 2>/dev/null)" -gt 0 ]]; then printf '%s' "$r" > "$cdir/regions.json"; mod_enable "$contest" sedes; else rm -f "$cdir/regions.json"; fi
fi
if jq -e 'has("teams_meta")' >/dev/null 2>&1 <<<"$body"; then
  t="$(jq -c '.teams_meta' <<<"$body")"
  if [[ "$(jq 'length' <<<"$t" 2>/dev/null)" -gt 0 ]]; then jq -cn --argjson r "$t" '{rules:$r}' > "$cdir/teams-meta.json"; mod_enable "$contest" sedes; else rm -f "$cdir/teams-meta.json"; fi
fi
if jq -e 'has("basic")' >/dev/null 2>&1 <<<"$body"; then
  bl="$(jq -r '.basic.locale // empty' <<<"$body")"; [[ "$bl" =~ ^(pt|en)$ ]] && cc_set_conf_var "$contest" LOCALE "$bl"
  bs="$(jq -r '.basic.login_start // empty' <<<"$body")"; [[ "$bs" =~ ^[0-9]+$ ]] && cc_set_conf_var "$contest" LOGIN_START_TIME "$bs"
  bf="$(jq -r '.basic.freeze // empty' <<<"$body")"
  if [[ "$bf" =~ ^[0-9]+$ ]] && [[ "$bf" != "$(conf_value "$contest" FREEZE_TIME)" ]]; then
    # 0 = descongelar (ou freeze em vigor empurrado p/ o futuro): só a partir do fim geral + 1 min
    source "$_LIBDIR/contest-gate.sh"; freeze_change_guard "$contest" "$bf"
    cc_set_conf_var "$contest" FREEZE_TIME "$bf"
    # freeze mudou ⇒ rebuild FORÇADO: o gatilho passivo "conf mais novo que .metrics-stamp"
    # perde p/ um build em voo (corrida de mtime, Maratona 29/08 — ver lib/common.sh).
    score_kick_rebuild "$contest"
  fi
  if [[ "$(jq -r '.basic.login_enabled' <<<"$body")" == "false" ]]; then cc_set_conf_var "$contest" LOGIN_ENABLED n; else cc_del_conf_var "$contest" LOGIN_ENABLED; fi
fi
audit_log_to "$contest" config "$(jq -cr 'keys|join(",")' <<<"$body" 2>/dev/null | head -c 200)"
ok_json '{saved:true}'
