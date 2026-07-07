# GET /contest/admin/report?contest=<c>   (admin DO contest)
# Baixa o RELATÓRIO ESTÁTICO da prova: tar.gz com um site navegável offline (index.html
# com placar ABERTO + info + enunciados; runs; clarifications anônimas; estatísticas;
# tarefas do staff; infra), gerado por server/score/report-gen.sh — que também carrega o
# CONTRATO DE PRIVACIDADE (sem código-fonte, sem logs de juiz, sem senhas, sem asker).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

# balões em dia ANTES do snapshot (mesma reconciliação preguiçosa da fila do staff)
source "$_LIBDIR/print.sh"
pr_reconcile_balloons "$contest" || true

# uma geração por vez (duplo-clique/concorrência): flock não-bloqueante em var/
mkdir -p "$CONTESTSDIR/$contest/var" 2>/dev/null
exec 9>"$CONTESTSDIR/$contest/var/.report.lock"
flock -n 9 || fail 429 "Relatório já está sendo gerado" "busy"

stg="$(mktemp -d 2>/dev/null)" || fail 500 "tmp" "tmp"
trap 'rm -rf "$stg"' EXIT
if ! bash "$SCOREDIR/report-gen.sh" "$contest" "$stg/relatorio-$contest" \
      >/dev/null 2>"$CONTESTSDIR/$contest/var/report-gen.err"; then
  fail 500 "Falha ao gerar o relatório" "report_failed"
fi
rm -f "$CONTESTSDIR/$contest/var/report-gen.err" 2>/dev/null

npages="$(find "$stg/relatorio-$contest" -name '*.html' 2>/dev/null | wc -l | tr -d '[:space:]')"
audit_log_to "$contest" report-download "pages=$npages"

fn="relatorio-$(printf '%s' "$contest" | tr -cd 'A-Za-z0-9._-')-$(date +%Y%m%d-%H%M).tar.gz"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/gzip\r\n'
printf 'Content-Disposition: attachment; filename="%s"\r\n' "$fn"
printf '\r\n'
tar -czf - -C "$stg" "relatorio-$contest"
