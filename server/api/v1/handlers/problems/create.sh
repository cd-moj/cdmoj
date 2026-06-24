# POST /problems/create   (Bearer)
# body: {repo, prob, enunciado_md?, author?, tags?, conf_text?, examples?, tests?, good_sol?, title?}
# Cria um problema NOVO num diretório (repo Gitea) do autor. Commit autorado pelo login,
# push keyless via broker. Não publica — o autor depois clica Validar&Publicar.
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$MOJTOOLS_DIR/git-broker.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
repo="$(jq -r '.repo // empty' <<<"$body")"
prob="$(jq -r '.prob // empty' <<<"$body")"
[[ "$repo" =~ ^[a-z0-9][a-z0-9._-]{1,63}$ ]] || fail 400 "Diretório inválido" "repo_invalid"
[[ "$prob" =~ ^[a-z0-9][a-z0-9._-]{1,80}$ ]] || fail 400 "Nome de problema inválido (use [a-z0-9._-])" "prob_invalid"
owner="$(repo_owner "$repo")"; [[ -n "$owner" ]] || fail 404 "Diretório não existe (crie com repo-create)" "repo_missing"
gitea_can_write "$owner" "$repo" "$SESSION_LOGIN" || fail 403 "Sem permissão de escrita nesse diretório" "forbidden"

tmp="$(git_broker_open "$SESSION_LOGIN" "$owner" "$repo")" || fail 502 "Falha ao abrir o repositório" "git_open"
trap 'rm -rf "$tmp"' EXIT
wt="$tmp/wt"
[[ -e "$wt/$prob" ]] && fail 409 "Problema já existe nesse diretório" "prob_exists"
mkdir -p "$wt/$prob"
[[ -f "$wt/$prob/conf" ]] || printf 'ULIMITS[-u]=10000\nALLOWPARALLELTEST=y\n' > "$wt/$prob/conf"
apply_problem_fields "$wt/$prob" "$body"
[[ -s "$wt/$prob/author" ]] || printf '%s\n' "$SESSION_NAME" > "$wt/$prob/author"
colls="$(jq -c --arg r "$repo" '(.collections // [$r])' <<<"$body")"
title="$(jq -r '.title // empty' <<<"$body")"
write_meta "$wt/$prob" "$owner" "$repo" false "$colls" "$title"

sha="$(git_broker_commit_push "$SESSION_LOGIN" "$owner" "$repo" "$wt" "novo problema: $prob")" \
  || fail 502 "Falha ao enviar (push)" "git_push"
# overlay p/ visibilidade imediata em "Meus" (antes do reindex no NFS)
author_txt="$(cat "$wt/$prob/author" 2>/dev/null | head -1)"
authored_upsert "$repo#$prob" "$owner" "$repo" "$prob" "$title" false "$colls" "$author_txt" "$(repo_collabs "$repo")"
audit_log "problem-create" "id=$repo#$prob owner=$owner"
ok_json '{action:"create", id:$id, repo:$r, prob:$p, owner:$o, sha:$s}' \
  --arg id "$repo#$prob" --arg r "$repo" --arg p "$prob" --arg o "$owner" --arg s "${sha:0:12}"
