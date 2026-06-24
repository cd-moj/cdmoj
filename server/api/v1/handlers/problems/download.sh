# GET /problems/download?id=<id>   (Bearer) — baixa o pacote do problema (.tar.gz).
# Inclui as SOLUÇÕES, então exige permissão de escrita (ou admin); legado só admin.
require_method GET
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$MOJTOOLS_DIR/git-broker.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
owner="$(problem_owner "$id")"

pkg=""; tmp=""
if [[ -n "$owner" ]] && gitea_can_write "$owner" "$repo" "$SESSION_LOGIN"; then
  tmp="$(git_broker_open "$SESSION_LOGIN" "$owner" "$repo")" || fail 502 "Falha ao abrir o repositório" "git_open"
  trap 'rm -rf "$tmp"' EXIT
  pkg="$tmp/wt/$prob"
elif is_admin; then
  pkg="$MOJ_PROBLEMS_DIR/$repo/$prob"
else
  fail 403 "Sem permissão (o pacote contém soluções)" "forbidden"
fi
[[ -d "$pkg" ]] || fail 404 "Pacote não encontrado" "not_found"

audit_log "download" "id=$id by=$SESSION_LOGIN"
fn="$(printf '%s' "$prob" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$fn" ]] || fn=problema
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/gzip\r\n'
printf 'Content-Disposition: attachment; filename="%s.tar.gz"\r\n' "$fn"
printf '\r\n'
tar -czf - -C "$(dirname "$pkg")" --exclude='.git' "$(basename "$pkg")" 2>/dev/null
