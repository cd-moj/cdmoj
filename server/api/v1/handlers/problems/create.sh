# POST /problems/create   (Bearer)
# body: {repo(=org), prob, enunciado_md?, author?, tags?, conf_text?, examples?, tests?, good_sol?, title?, collections?, languages?}
# Cria um problema NOVO numa ORG de que o login é MEMBRO (ou na sua org implícita <login>). Storage =
# repo git LOCAL por problema em MOJ_PROBLEMS_DIR/<org>/<prob>; commit autorado pelo login (sem Gitea).
# Não publica — o autor depois clica Validar&Publicar (e a org precisa permitir público).
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"; source "$_DIR/lib/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar problemas (mesma regra de criar contest)" "create_forbidden"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
org="$(jq -r '.repo // .org // empty' <<<"$body")"
prob="$(jq -r '.prob // empty' <<<"$body")"
[[ "$org" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]] || fail 400 "Org inválida" "org_invalid"
[[ "$prob" =~ ^[a-z0-9][a-z0-9._-]{1,80}$ ]] || fail 400 "Nome de problema inválido (use [a-z0-9._-])" "prob_invalid"
# org implícita <login> é criada sob demanda; orgs compartilhadas precisam existir + ser membro
[[ "$org" == "$SESSION_LOGIN" ]] && ensure_implicit_org "$SESSION_LOGIN"
org_exists "$org" || fail 404 "Org não existe (crie com /orgs/create)" "org_missing"
org_is_member "$org" "$SESSION_LOGIN" || fail 403 "Você não é membro dessa org" "forbidden"

id="$org#$prob"
pdir="$MOJ_PROBLEMS_DIR/$org/$prob"
[[ -e "$pdir" ]] && fail 409 "Problema já existe nessa org" "prob_exists"
mkdir -p "$pdir"
[[ -f "$pdir/conf" ]] || printf 'ULIMITS[-u]=10000\nALLOWPARALLELTEST=y\n' > "$pdir/conf"
apply_problem_fields "$pdir" "$body"
[[ -s "$pdir/author" ]] || printf '%s\n' "$SESSION_NAME" > "$pdir/author"
colls="$(jq -c --arg r "$org" '(.collections // [$r])' <<<"$body")"
coll_register "$org" "$SESSION_LOGIN"   # a coleção homônima da org (agrupamento default) fica válida
title="$(jq -r '.title // empty' <<<"$body")"
# languages: restrição de submissão por-problema ([]/ausente = todas)
langs=""; jq -e 'has("languages")' >/dev/null 2>&1 <<<"$body" && langs="$(jq -c '(.languages // [])' <<<"$body")"
write_meta "$pdir" "$SESSION_LOGIN" "$org" false "$colls" "$title" "$langs"
bash "$MOJTOOLS_DIR/kattis/sidecar.sh" "$pdir" "$id" "$org" >/dev/null 2>&1 || true  # Kattis-aware

sha="$(problem_commit "$pdir" "$SESSION_LOGIN" "novo problema: $prob")"
# overlay p/ visibilidade imediata em "Meus" (antes do reindex)
author_txt="$(cat "$pdir/author" 2>/dev/null | head -1)"
authored_upsert "$id" "$SESSION_LOGIN" "$org" "$prob" "$title" false "$colls" "$author_txt" '[]'
audit_log "problem-create" "id=$id org=$org owner=$SESSION_LOGIN"
ok_json '{action:"create", id:$id, repo:$r, prob:$p, owner:$o, sha:$s}' \
  --arg id "$id" --arg r "$org" --arg p "$prob" --arg o "$SESSION_LOGIN" --arg s "${sha:0:12}"
