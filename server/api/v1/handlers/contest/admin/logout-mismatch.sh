# POST /contest/admin/logout-mismatch?contest=<id>  (admin)
# Desloga as sessões cujo User-Agent NÃO contém a substring esperada (LOGIN_UA_SUBSTRING),
# exceto contas privilegiadas. Útil para expulsar quem entrou de máquina não autorizada.
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

sub="$(grep -m1 '^LOGIN_UA_SUBSTRING=' "$CONTESTSDIR/$contest/conf" 2>/dev/null | cut -d= -f2-)"
sub="${sub%\'}"; sub="${sub#\'}"; sub="${sub%\"}"; sub="${sub#\"}"
[[ -n "$sub" ]] || fail 422 "Defina o filtro de UA (LOGIN_UA_SUBSTRING) primeiro" "no_substring"

removed=0
set +o noglob; shopt -s nullglob
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  CONTEST=""; LOGIN=""; UA_B64=""; source "$f" 2>/dev/null
  [[ "$CONTEST" == "$contest" ]] || continue
  case "$LOGIN" in *.admin|*.judge|*.staff|*.mon) continue;; esac
  ua="$(printf '%s' "$UA_B64" | base64 -d 2>/dev/null)"
  [[ "$ua" == *"$sub"* ]] && continue
  rm -f "$f"; ((removed++))
done
shopt -u nullglob
audit_log_to "$contest" logout-mismatch "substring=$sub removed=$removed"
ok_json '{logged_out:true, sessions_removed:$n}' --argjson n "${removed:-0}"
