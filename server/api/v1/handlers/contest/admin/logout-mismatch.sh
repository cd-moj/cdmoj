# POST /contest/admin/logout-mismatch?contest=<id>  (admin)
# Desloga as sessões cujo User-Agent NÃO contém a substring esperada (LOGIN_UA_SUBSTRING),
# exceto contas privilegiadas. Útil para expulsar quem entrou de máquina não autorizada.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

# O esperado é POR TIME (sede): lib/ua-gate.sh resolve (captura no login, override por sede,
# isentos) e cai no LOGIN_UA_SUBSTRING legado quando não há ua-gate.json.
source "$_DIR/lib/ua-gate.sh"
_g="$(ug_get "$contest")"
if [[ "$(jq -r '.mode' <<<"$_g")" == off ]]; then
  fail 422 "o gate de UA está desligado (mode:off)" "gate_off"
fi
jq -e '(.from_login != null) or ((.by_region|length) > 0) or ((.by_regex|length) > 0)
       or ((.fallback // "") != "")' <<<"$_g" >/dev/null 2>&1 \
  || [[ -n "$(ug_legacy "$contest")" ]] \
  || fail 422 "Configure o gate de UA primeiro (ua-gate.json ou LOGIN_UA_SUBSTRING)" "no_substring"

removed=0
set +o noglob; shopt -s nullglob
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  CONTEST=""; LOGIN=""; UA_B64=""; source "$f" 2>/dev/null
  [[ "$CONTEST" == "$contest" ]] || continue
  is_reserved_role_login "$LOGIN" && continue
  ua="$(printf '%s' "$UA_B64" | base64 -d 2>/dev/null)"
  ug_ok "$contest" "$LOGIN" "$ua" && continue
  rm -f "$f"; ((removed++))
done
shopt -u nullglob
audit_log_to "$contest" logout-mismatch "por-sede removed=$removed"
ok_json '{logged_out:true, sessions_removed:$n}' --argjson n "${removed:-0}"
