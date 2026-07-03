# POST /problems/upload   (Bearer)   body: {id? | repo(=org),prob, tar_b64}
# Sobe um .tar(.gz)/.zip do pacote e ATUALIZA TUDO (substitui o conteúdo do problema). Commit LOCAL
# autorado pelo login (sem Gitea). Novo problema exige permissão de criação. Acesso = membro da org.
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
if [[ -n "$id" ]]; then valid_id "$id" || fail 400 "Invalid id" "id_invalid"; org="${id%%#*}"; prob="${id##*#}"
else org="$(jq -r '.repo // .org // empty' <<<"$body")"; prob="$(jq -r '.prob // empty' <<<"$body")"; id="$org#$prob"; fi
[[ "$org" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]] || fail 400 "Org inválida" "org_invalid"
[[ "$prob" =~ ^[a-z0-9][a-z0-9._-]{1,80}$ ]] || fail 400 "Nome de problema inválido" "prob_invalid"
[[ "$org" == "$SESSION_LOGIN" ]] && ensure_implicit_org "$SESSION_LOGIN"
org_exists "$org" || fail 404 "Org não existe (crie com /orgs/create)" "org_missing"
org_is_member "$org" "$SESSION_LOGIN" || fail 403 "Você não é membro dessa org" "forbidden"
pdir="$MOJ_PROBLEMS_DIR/$org/$prob"

tarf="$(mktemp)"; ex=""
trap 'rm -rf "$tarf" "$ex"' EXIT
jq -r '.tar_b64 // .archive_b64 // ""' <<<"$body" | base64 -d > "$tarf" 2>/dev/null
[[ -s "$tarf" ]] || fail 400 "Arquivo vazio/ inválido" "tar_empty"
ex="$(mktemp -d)"
if [[ "$(head -c2 "$tarf")" == "PK" ]]; then
  command -v unzip >/dev/null || fail 501 "Sem unzip no servidor (envie .tar.gz)" "no_unzip"
  unzip -Z1 "$tarf" 2>/dev/null | grep -qE '(^/|(^|/)\.\.(/|$))' && fail 400 "Zip com caminho inseguro" "zip_unsafe"
  unzip -qq -o "$tarf" -d "$ex" 2>/dev/null || fail 400 "Zip inválido" "zip_bad"
else
  tar -tf "$tarf" 2>/dev/null | grep -qE '(^/|(^|/)\.\.(/|$))' && fail 400 "Arquivo com caminho inseguro" "tar_unsafe"
  tar -xf "$tarf" -C "$ex" --no-same-owner 2>/dev/null || fail 400 "Arquivo inválido (tar/tar.gz/tar.bz2/tar.zst/zip)" "tar_bad"
fi
# raiz do pacote: 1 diretório de topo -> usa ele; senão a raiz extraída
src="$ex"; top="$(find "$ex" -maxdepth 1 -mindepth 1)"
[[ "$(printf '%s\n' "$top" | grep -c .)" -eq 1 && -d "$top" ]] && src="$top"

if [[ ! -d "$pdir" ]]; then   # problema NOVO via tar -> exige permissão de criação
  source "$_DIR/lib/contest-create.sh"
  cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar novos problemas (mesma regra de criar contest)" "create_forbidden"
fi
mkdir -p "$pdir"
# preserva o .git do problema (histórico local): rsync --delete com --exclude='.git' NÃO o apaga
rsync -a --delete --exclude='.git' "$src"/ "$pdir"/ 2>/dev/null || cp -a "$src"/. "$pdir"/
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || owner="$SESSION_LOGIN"
write_meta "$pdir" "$owner" "$org" "" "" ""
[[ -f "$pdir/problem.yaml" ]] || bash "$MOJTOOLS_DIR/kattis/sidecar.sh" "$pdir" "$id" "$org" >/dev/null 2>&1 || true

sha="$(problem_commit "$pdir" "$SESSION_LOGIN" "upload do pacote: $prob")"
pub="$(jq -r 'if .public==true then "true" else "false" end' "$pdir/.moj-meta.json" 2>/dev/null)"
colls="$(jq -c '.collections // []' "$pdir/.moj-meta.json" 2>/dev/null)"
title="$(jq -r '.display_title // ""' "$pdir/.moj-meta.json" 2>/dev/null)"
author="$(head -1 "$pdir/author" 2>/dev/null)"
authored_upsert "$id" "$owner" "$org" "$prob" "$title" "${pub:-false}" "${colls:-[]}" "$author" '[]'
audit_log "upload" "id=$id by=$SESSION_LOGIN"
ok_json '{action:"upload", id:$id, sha:$s}' --arg id "$id" --arg s "${sha:0:12}"
