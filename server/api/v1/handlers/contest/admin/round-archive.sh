# GET /contest/admin/round-archive?contest=<c>&round=<slug>   (admin DO contest)
# Baixa o ARQUIVO CRU de uma rodada arquivada: tar.gz de contests/<c>/rounds/<slug>/ — com
# código-fonte das submissões, log do juiz, review, clarifications, backups e os logs copiados.
# É a auditoria completa (o /contest/round serve só o relatório, que é redigido).
require_method GET
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
source "$_DIR/lib/contest-rounds.sh"

round="$(param round)"
rd_valid_slug "$round" || fail 400 "round inválido" "round_invalid"
dir="$(rd_archive_dir "$contest" "$round")"
[[ -d "$dir" ]] || fail 404 "Rodada não arquivada" "not_archived"

audit_log_to "$contest" round-archive-download "round=$round"
fn="rodada-$(printf '%s' "$contest-$round" | tr -cd 'A-Za-z0-9._-')-$(date +%Y%m%d-%H%M).tar.gz"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/gzip\r\n'
printf 'Content-Disposition: attachment; filename="%s"\r\n' "$fn"
printf '\r\n'
tar -czf - -C "$(rd_base "$contest")" "$round"
