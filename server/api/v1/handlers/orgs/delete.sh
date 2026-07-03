# POST /orgs/delete  (Bearer)  body: {name}
# Remove uma ORG VAZIA (sem nenhum problema). Só admin da org (ou admin global). A org IMPLÍCITA
# (<login>) NUNCA é removida. Emptiness é conferida em DISCO (autoritativa; o count do índice pode
# subcontar privados de outros membros). Deixa a coleção homônima em paz (ortogonal).
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"
body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
[[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
org_exists "$name" || fail 404 "Org não encontrada" "not_found"
org_can_manage "$name" "$SESSION_LOGIN" || fail 403 "Só um admin da org pode removê-la" "forbidden"
org_is_implicit "$name" && fail 409 "A org implícita (sua) não pode ser removida" "implicit_org"
# vazia? conta os diretórios de problema sob MOJ_PROBLEMS_DIR/<org>/ (padrão do set-public-allowed.sh);
# NUNCA grep -c (armadilha de 502): wc -l é seguro, depois saneia p/ dígitos.
n="$(find "$MOJ_PROBLEMS_DIR/$name" -mindepth 1 -maxdepth 1 -type d ! -name '.git' 2>/dev/null | wc -l)"
n="${n//[^0-9]/}"; n="${n:-0}"
(( n > 0 )) && fail 409 "A org tem $n problema(s) — mova ou exclua antes de remover" "org_not_empty"
org_delete "$name"
rmdir "$MOJ_PROBLEMS_DIR/$name" 2>/dev/null   # best-effort: remove o diretório se estiver vazio
audit_log "org-delete" "name=$name by=$SESSION_LOGIN"
ok_json '{action:"org-delete", name:$n}' --arg n "$name"
