# POST /problems/edit   (Bearer)   body: {id, enunciado_md?, author?, tags?, conf_text?,
#                                          examples?, tests?, good_sol?, title?, collections?}
# Edita um problema existente (residente no Gitea). Commit autorado pelo login, push keyless.
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$MOJTOOLS_DIR/git-broker.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"
[[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || fail 404 "Problema não está no Gitea (migre antes)" "not_gitea"
gitea_can_write "$owner" "$repo" "$SESSION_LOGIN" || fail 403 "Sem permissão de escrita" "forbidden"

tmp="$(git_broker_open "$SESSION_LOGIN" "$owner" "$repo")" || fail 502 "Falha ao abrir o repositório" "git_open"
trap 'rm -rf "$tmp"' EXIT
wt="$tmp/wt"; [[ -d "$wt/$prob" ]] || fail 404 "Problema não existe no diretório" "prob_missing"
apply_problem_fields "$wt/$prob" "$body"
colls=""; jq -e 'has("collections")' >/dev/null 2>&1 <<<"$body" && colls="$(jq -c '.collections' <<<"$body")"
title="$(jq -r '.title // empty' <<<"$body")"
write_meta "$wt/$prob" "$owner" "$repo" "" "$colls" "$title"
bash "$MOJTOOLS_DIR/kattis/sidecar.sh" "$wt/$prob" "$id" "$repo" >/dev/null 2>&1 || true  # Kattis-aware

sha="$(git_broker_commit_push "$SESSION_LOGIN" "$owner" "$repo" "$wt" "edita $prob")" \
  || fail 502 "Falha ao enviar (push)" "git_push"
ensure_repo_materialized "$repo" "$SESSION_LOGIN"   # espelha p/ indexador/juiz acharem o pacote
# atualiza o overlay (mantém public; título/coleções/autor do que está no pacote)
pub_now="$(jq -r 'if .public==true then "true" else "false" end' "$wt/$prob/.moj-meta.json" 2>/dev/null)"
colls_now="$(jq -c '.collections // []' "$wt/$prob/.moj-meta.json" 2>/dev/null)"
author_txt="$(cat "$wt/$prob/author" 2>/dev/null | head -1)"
authored_upsert "$id" "$owner" "$repo" "$prob" "$title" "${pub_now:-false}" "${colls_now:-[]}" "$author_txt" "$(repo_collabs "$repo")"
grant_problem_collections "$id" "$repo" "$SESSION_LOGIN"   # setters das coleções ganham acesso
audit_log "problem-edit" "id=$id by=$SESSION_LOGIN"
ok_json '{action:"edit", id:$id, sha:$s}' --arg id "$id" --arg s "${sha:0:12}"
