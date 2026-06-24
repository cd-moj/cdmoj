# GET /problems/export?id=<id>   (Bearer) — baixa o problema como pacote ICPC/Kattis (.tar.gz).
# Inclui as soluções, então exige permissão de escrita (ou admin); legado só admin.
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
  pkg="$tmp/wt/$prob"
elif is_admin; then
  pkg="$MOJ_PROBLEMS_DIR/$repo/$prob"
else
  fail 403 "Sem permissão (o pacote contém soluções)" "forbidden"
fi
[[ -d "$pkg" ]] || { [[ -n "$tmp" ]] && rm -rf "$tmp"; fail 404 "Pacote não encontrado" "not_found"; }

work="$(mktemp -d)"; tgz="$work/$prob.tar.gz"
bash "$MOJTOOLS_DIR/kattis/export.sh" "$pkg" "$id" "$tgz" >/dev/null 2>"$work/err" || { rm -rf "$tmp" "$work"; fail 500 "Falha no export ICPC ($(head -1 "$work/err" 2>/dev/null))" "export_fail"; }
[[ -s "$tgz" ]] || { rm -rf "$tmp" "$work"; fail 500 "Export vazio" "export_empty"; }

audit_log "export-kattis" "id=$id by=$SESSION_LOGIN"
fn="$(printf '%s' "$prob" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$fn" ]] || fn=problema
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/gzip\r\n'
printf 'Content-Disposition: attachment; filename="%s.icpc.tar.gz"\r\n' "$fn"
printf '\r\n'
cat "$tgz"
rm -rf "$tmp" "$work"
