# POST /problems/upload   (Bearer)   body: {id? | repo,prob, tar_b64}
# Sobe um .tar(.gz) do pacote e ATUALIZA TUDO (substitui o conteúdo do problema). Commit+push
# autorado pelo login. Útil p/ máquinas sem git e p/ trabalhar offline e subir de uma vez.
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$MOJTOOLS_DIR/git-broker.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
if [[ -n "$id" ]]; then valid_id "$id" || fail 400 "Invalid id" "id_invalid"; repo="${id%%#*}"; prob="${id##*#}"
else repo="$(jq -r '.repo // empty' <<<"$body")"; prob="$(jq -r '.prob // empty' <<<"$body")"; id="$repo#$prob"; fi
[[ "$repo" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Diretório inválido" "repo_invalid"
[[ "$prob" =~ ^[a-z0-9][a-z0-9._-]{1,80}$ ]] || fail 400 "Nome de problema inválido" "prob_invalid"
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || owner="$(repo_owner "$repo")"
[[ -n "$owner" ]] || fail 404 "Diretório não existe (crie com repo-create)" "repo_missing"
gitea_can_write "$owner" "$repo" "$SESSION_LOGIN" || fail 403 "Sem permissão de escrita" "forbidden"

tarf="$(mktemp)"; ex=""; tmp=""
trap 'rm -rf "$tarf" "$ex" "$tmp"' EXIT
# aceita o campo .tar_b64 (qualquer formato) ou .archive_b64 (alias)
jq -r '.tar_b64 // .archive_b64 // ""' <<<"$body" | base64 -d > "$tarf" 2>/dev/null
[[ -s "$tarf" ]] || fail 400 "Arquivo vazio/ inválido" "tar_empty"
ex="$(mktemp -d)"
# zip (magic PK) -> unzip; senão tar -xf (auto-detecta gz/bz2/xz/zst/plain)
if [[ "$(head -c2 "$tarf")" == "PK" ]]; then
  command -v unzip >/dev/null || fail 501 "Sem unzip no servidor (envie .tar.gz)" "no_unzip"
  unzip -Z1 "$tarf" 2>/dev/null | grep -qE '(^/|(^|/)\.\.(/|$))' && fail 400 "Zip com caminho inseguro" "zip_unsafe"
  unzip -qq -o "$tarf" -d "$ex" 2>/dev/null || fail 400 "Zip inválido" "zip_bad"
else
  tar -tf "$tarf" 2>/dev/null | grep -qE '(^/|(^|/)\.\.(/|$))' && fail 400 "Arquivo com caminho inseguro" "tar_unsafe"
  tar -xf "$tarf" -C "$ex" --no-same-owner 2>/dev/null || fail 400 "Arquivo inválido (formatos: tar/tar.gz/tar.bz2/tar.zst/zip)" "tar_bad"
fi
# raiz do pacote: 1 diretório de topo -> usa ele; senão a raiz extraída
src="$ex"; top="$(find "$ex" -maxdepth 1 -mindepth 1)"
[[ "$(printf '%s\n' "$top" | grep -c .)" -eq 1 && -d "$top" ]] && src="$top"

tmp="$(git_broker_open "$SESSION_LOGIN" "$owner" "$repo")" || fail 502 "Falha ao abrir o repositório" "git_open"
wt="$tmp/wt"
if [[ ! -d "$wt/$prob" ]]; then   # problema NOVO via tar -> exige permissão de criação
  source "$_DIR/lib/contest-create.sh"
  cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar novos problemas (mesma regra de criar contest)" "create_forbidden"
fi
mkdir -p "$wt/$prob"
rsync -a --delete --exclude='.git' "$src"/ "$wt/$prob"/ 2>/dev/null \
  || { rm -rf "$wt/$prob"; mkdir -p "$wt/$prob"; cp -a "$src"/. "$wt/$prob"/; }
write_meta "$wt/$prob" "$owner" "$repo" "" "" ""
[[ -f "$wt/$prob/problem.yaml" ]] || bash "$MOJTOOLS_DIR/kattis/sidecar.sh" "$wt/$prob" "$repo#$prob" "$repo" >/dev/null 2>&1 || true

sha="$(git_broker_commit_push "$SESSION_LOGIN" "$owner" "$repo" "$wt" "upload do pacote: $prob")" \
  || fail 502 "Falha ao enviar (push)" "git_push"
pub="$(jq -r 'if .public==true then "true" else "false" end' "$wt/$prob/.moj-meta.json" 2>/dev/null)"
colls="$(jq -c '.collections // []' "$wt/$prob/.moj-meta.json" 2>/dev/null)"
title="$(jq -r '.display_title // ""' "$wt/$prob/.moj-meta.json" 2>/dev/null)"
author="$(head -1 "$wt/$prob/author" 2>/dev/null)"
authored_upsert "$id" "$owner" "$repo" "$prob" "$title" "${pub:-false}" "${colls:-[]}" "$author" "$(repo_collabs "$repo")"
audit_log "upload" "id=$id by=$SESSION_LOGIN"
ok_json '{action:"upload", id:$id, sha:$s}' --arg id "$id" --arg s "${sha:0:12}"
