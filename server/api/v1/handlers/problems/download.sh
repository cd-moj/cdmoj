# GET /problems/download?id=<id>   (Bearer) — baixa o pacote do problema (.tar.gz).
# Inclui as SOLUÇÕES, então exige permissão de escrita (ou admin). Fonte = Gitea.
require_method GET
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
owner="$(problem_owner "$id")"
[[ -n "$owner" ]] || fail 404 "Problema não está no Gitea" "not_gitea"
gitea_can_write "$owner" "$repo" "$SESSION_LOGIN" || is_admin || fail 403 "Sem permissão (o pacote contém soluções)" "forbidden"

# Lê do espelho (mantido em dia a cada save); materializa na 1ª vez com o token do dono.
pkg="$MOJ_PROBLEMS_DIR/$repo/$prob"
[[ -d "$MOJ_PROBLEMS_DIR/$repo/.git" ]] || ensure_repo_materialized "$repo" "$owner"
[[ -d "$pkg" ]] || fail 404 "Pacote não encontrado" "not_found"

audit_log "download" "id=$id by=$SESSION_LOGIN"
fn="$(printf '%s' "$prob" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$fn" ]] || fn=problema
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/gzip\r\n'
printf 'Content-Disposition: attachment; filename="%s.tar.gz"\r\n' "$fn"
printf '\r\n'
tar -czf - -C "$(dirname "$pkg")" --exclude='.git' "$(basename "$pkg")" 2>/dev/null
