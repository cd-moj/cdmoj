# GET /contest/staff/print-html?contest=<c>&id=<id>   (Bearer; .staff ou .admin) — PROTÓTIPO (09/11/2026)
# A folha em HTML de impressão (lib/print.sh pr_html), para a estação imprimir no navegador quando o contest usa
# PRINT_FORMAT=html. O MESMO gate do print-pdf (escopo da tarefa, .cstaff fora) e a mesma auditoria.
# 409 html_unsupported = a tarefa não sai em HTML (pedido que não é texto, ou texto grande demais): a estação usa o
# PDF de sempre. A página carrega a própria CSP (sem script) — ver pr_html.
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
[[ -f "$meta" ]] || fail 404 "Tarefa não encontrada" "notfound"
kind="$(jq -r '.kind // "print"' "$meta" 2>/dev/null)"
[[ "$kind" == balloon || -f "$dir/$id.src" ]] || fail 404 "Tarefa não encontrada" "notfound"
pr_task_can_see "$contest" "$meta" || fail 403 "Tarefa fora do seu escopo" "out_of_scope"
seq="$(jq -r '.seq // 0' "$meta" 2>/dev/null)"

html="$(mktemp)"; trap 'rm -f "$html"' EXIT
pr_html "$contest" "$id" > "$html"; rc=$?
(( rc == 3 )) && fail 409 "Esta tarefa não sai em HTML: use o PDF" "html_unsupported"
(( rc == 0 )) && [[ -s "$html" ]] || fail 500 "Falha ao gerar a folha" "build_failed"
if [[ "$kind" == balloon ]]; then
  audit_log_to "$contest" balloon-served "seq=$seq by=$SESSION_LOGIN formato=html problema=$(jq -r '.short // ""' "$meta" 2>/dev/null)"
else
  audit_log_to "$contest" print-served "seq=$seq by=$SESSION_LOGIN formato=html"
fi
printf 'Status: 200 OK\r\n'
printf 'Content-Type: text/html; charset=utf-8\r\n'
printf "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; img-src data:\r\n"
printf 'Cache-Control: no-store\r\n'
printf '\r\n'
cat "$html"
