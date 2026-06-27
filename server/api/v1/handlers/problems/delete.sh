# POST /problems/delete   (Bearer)   body: {id, confirm}
# REMOVE um problema do Gitea (git rm da subpasta) e do treino. DESTRUTIVO: exige confirmação
# POR ESCRITO — `confirm` tem de repetir EXATAMENTE o id. Só o dono/colaborador (ou admin) remove.
require_method POST
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$MOJTOOLS_DIR/git-broker.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
confirm="$(jq -r '.confirm // empty' <<<"$body")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
# confirmação por escrito: tem de repetir o id exatamente
[[ "$confirm" == "$id" ]] || fail 400 "Confirmação inválida — repita exatamente o id ($id) para remover" "confirm_mismatch"
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || fail 404 "Problema não está no Gitea" "not_gitea"
gitea_can_write "$owner" "$repo" "$SESSION_LOGIN" || fail 403 "Sem permissão de escrita" "forbidden"

# 1) remove do Gitea: git rm da subpasta do problema + commit/push como o autor (add -A já faz o stage da remoção)
tmp="$(git_broker_open "$SESSION_LOGIN" "$owner" "$repo")" || fail 502 "Falha ao abrir o repositório" "git_open"
trap 'rm -rf "$tmp"' EXIT
wt="$tmp/wt"; [[ -d "$wt/$prob" ]] || fail 404 "Problema não existe" "prob_missing"
rm -rf "$wt/$prob"
git_broker_commit_push "$SESSION_LOGIN" "$owner" "$repo" "$wt" "remove $prob" >/dev/null \
  || fail 502 "Falha ao enviar (push)" "git_push"

# 2) remove do espelho, do treino e dos artefatos/índices (visibilidade IMEDIATA)
rm -rf "$MOJ_PROBLEMS_DIR/$repo/$prob" 2>/dev/null
rm -f "$CONTESTSDIR/treino/var/jsons/$id.json" "$CONTESTSDIR/treino/var/jsons-private/$id.json" 2>/dev/null
rm -f "$RUNDIR/validation/$id.json" 2>/dev/null
authored_remove "$id"
# regenera o índice de donos JÁ (senão o removido ainda apareceria até o TTL)
( MOJ_PROBLEMS_DIR="$MOJ_PROBLEMS_DIR" CONTESTSDIR="$CONTESTSDIR" \
    setsid bash "$MOJTOOLS_DIR/gen-problem-owners.sh" >/dev/null 2>&1 & ) 2>/dev/null

audit_log "delete" "id=$id by=$SESSION_LOGIN"
ok_json '{action:"delete", id:$id}' --arg id "$id"
