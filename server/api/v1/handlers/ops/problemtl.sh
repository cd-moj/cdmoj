# GET /ops/problemtl?problem=<id>   (Bearer, admin) -> JSON
# Time limits de um problema, do STORE reportado pelos juízes (modelo cache).
#   {success, problem, checksum, time_limits:{lang:seg} (máx entre hosts), hosts:{...}}
# time_limits vazio = ninguém calibrou a versão atual ainda (ou o pacote mudou).
# PORTÃO (16/10/2026): admin com sessão DO TREINO — antes `require_admin` aceitava o .admin local de qualquer contest.
require_treino_admin
source "$_DIR/lib/tl-store.sh"

problem="$(param problem)"
[[ -n "$problem" ]] || fail 400 "Missing problem" "problem_missing"
valid_id "$problem" || fail 400 "Invalid problem" "problem_invalid"

pdir="$(pkg_path "$problem")"
cur="$(pkg_tl_checksum "$pdir")"
meth=moj; tl_conf_method_to meth "$pdir"   # o método do TL do conf (26/10/2026): a metade que vale
tlf=tl; [[ "$meth" == kattis ]] && tlf=tl_kattis
tlcal="$(tl_store_served_for "$problem" "$cur" "$tlf")"
ov="$(tl_conf_overrides "$pdir")"   # time_limits = efetivo (TLOVERRIDE do conf vence)
mods="$(tl_conf_mods "$pdir")"      # …e o TLMOD sum/mult do conf entra antes dele (a conta do juiz)
body="$(jq -cn --arg p "$problem" --arg cks "$cur" \
   --argjson tl "$(tl_override_apply "$tlcal" "$ov" "$mods")" \
   --argjson tlcal "$tlcal" --argjson ov "$ov" --argjson mods "$mods" --arg meth "$meth" \
   --argjson bm "$(tl_by_method_json "$problem" "$cur" "$ov" "$mods")" \
   --argjson store "$(tl_store_get "$problem")" '
   {success:true, problem:$p, checksum:$cks, time_limits:$tl,
    time_limits_calibrated:$tlcal, tl_override:$ov, tl_mods:$mods, tl_method:$meth, time_limits_by_method:$bm,
    calibrated_checksum:($store.checksum // ""),
    hosts:($store.hosts // {}), updated_at:($store.updated_at // null),
    stale:(($store.checksum // "") != $cks and ($store.checksum // "") != "")}')"
[[ -n "$body" ]] || fail 500 "Falha ao montar a resposta" "tl_fail"
emit_json 200 OK
printf '%s' "$body"
