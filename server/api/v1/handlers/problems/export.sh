# GET /problems/export?id=<id>   (Bearer) — baixa o problema como pacote ICPC/Kattis (.tar.gz).
# Inclui as soluções, então exige permissão de escrita (ou admin). Fonte = Gitea.
require_method GET
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
owner="$(problem_owner "$id")"
[[ -n "$owner" ]] || fail 404 "Problema não encontrado" "not_found"
require_problem_edit "$id"   # pacote inclui SOLUÇÕES -> só dono/colaborador (SEM atalho de .admin)

# Lê do espelho (mantido em dia a cada save); materializa na 1ª vez com o token do dono.
pkg="$MOJ_PROBLEMS_DIR/$repo/$prob"
[[ -d "$MOJ_PROBLEMS_DIR/$repo/.git" ]] || ensure_repo_materialized "$repo" "$owner"
[[ -d "$pkg" ]] || fail 404 "Pacote não encontrado" "not_found"

work="$(mktemp -d)"; tgz="$work/$prob.tar.gz"
bash "$MOJTOOLS_DIR/kattis/export.sh" "$pkg" "$id" "$tgz" >/dev/null 2>"$work/err" || { rm -rf "$work"; fail 500 "Falha no export ICPC ($(head -1 "$work/err" 2>/dev/null))" "export_fail"; }
[[ -s "$tgz" ]] || { rm -rf "$work"; fail 500 "Export vazio" "export_empty"; }

audit_log "export-kattis" "id=$id by=$SESSION_LOGIN"
fn="$(printf '%s' "$prob" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$fn" ]] || fn=problema
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/gzip\r\n'
printf 'Content-Disposition: attachment; filename="%s.icpc.tar.gz"\r\n' "$fn"
printf '\r\n'
cat "$tgz"
rm -rf "$work"
