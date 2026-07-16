# GET /problems/download?id=<id>[&sha=<sha>]   (Bearer) — baixa o pacote do problema (.tar.gz).
# Com `sha`, baixa a VERSÃO DAQUELE COMMIT (git archive — worktree intocado, sem .git).
# Inclui as SOLUÇÕES, então exige permissão de escrita (ou admin). Fonte = repo git local.
require_method GET
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
owner="$(problem_owner "$id")"
[[ -n "$owner" ]] || fail 404 "Problema não encontrado" "not_found"
require_problem_edit "$id"   # pacote inclui SOLUÇÕES -> só dono/colaborador (SEM atalho de .admin)

pkg="$MOJ_PROBLEMS_DIR/$repo/$prob"   # canônico LOCAL (repo git por problema)
[[ -d "$pkg" ]] || fail 404 "Pacote não encontrado" "not_found"

sha="$(param sha)"
fn="$(printf '%s' "$prob" | tr -cd 'A-Za-z0-9._-')"; [[ -n "$fn" ]] || fn=problema
if [[ -n "$sha" ]]; then
  # versão de um commit ANTIGO: regex antes de tocar o git; git archive não mexe no worktree
  [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || fail 400 "sha inválido" "sha_invalid"
  git -C "$pkg" cat-file -e "$sha^{commit}" 2>/dev/null || fail 404 "Commit não encontrado" "sha_unknown"
  audit_log "download" "id=$id sha=${sha:0:12} by=$SESSION_LOGIN"
  printf 'Status: 200 OK\r\n'
  printf 'Content-Type: application/gzip\r\n'
  printf 'Content-Disposition: attachment; filename="%s-%s.tar.gz"\r\n' "$fn" "${sha:0:7}"
  printf '\r\n'
  git -C "$pkg" archive --format=tar.gz --prefix="$(basename "$pkg")/" "$sha" 2>/dev/null
  exit 0
fi

audit_log "download" "id=$id by=$SESSION_LOGIN"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/gzip\r\n'
printf 'Content-Disposition: attachment; filename="%s.tar.gz"\r\n' "$fn"
printf '\r\n'
tar -czf - -C "$(dirname "$pkg")" --exclude='.git' "$(basename "$pkg")" 2>/dev/null
