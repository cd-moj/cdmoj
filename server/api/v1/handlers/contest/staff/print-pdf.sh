# GET /contest/staff/print-pdf?contest=<c>&id=<id>   (Bearer; .staff ou .admin)
# Gera (build-once, cache) e serve INLINE o PDF combinado: folha de rosto + documento.
# Escopo por regex; auditado (print-served; + print-build-fail no fallback).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
{ is_staff || is_admin; } || fail 403 "Apenas staff" "staff_required"
source "$_LIBDIR/print.sh"

id="$(param id)"
[[ "$id" =~ ^[A-Za-z0-9_]+$ ]] || fail 400 "id inválido" "id_invalid"
dir="$(pr_dir "$contest")"
meta="$dir/$id.json"
[[ -f "$meta" && -f "$dir/$id.src" ]] || fail 404 "Pedido não encontrado" "notfound"
owner="$(jq -r '.login // ""' "$meta" 2>/dev/null)"
staff_can_see "$contest" "$SESSION_LOGIN" "$owner" || fail 403 "Tarefa fora do seu escopo" "out_of_scope"
seq="$(jq -r '.seq // 0' "$meta" 2>/dev/null)"

pdf="$(pr_build_pdf "$contest" "$id")" || fail 500 "Falha ao gerar PDF" "build_failed"
pages="$(jq -r '.pages // 0' "$meta" 2>/dev/null)"
[[ "$(jq -r '.build_ok // true' "$meta" 2>/dev/null)" == false ]] \
  && audit_log_to "$contest" print-build-fail "seq=$seq id=$id mime=$(jq -r '.mime // ""' "$meta" 2>/dev/null)"
audit_log_to "$contest" print-served "seq=$seq by=$SESSION_LOGIN paginas=$pages"

printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/pdf\r\n'
printf 'Content-Disposition: inline; filename="tarefa-%s.pdf"\r\n' "$seq"
printf '\r\n'
cat "$pdf"
