# POST /problems/edit   (Bearer)   body: {id, enunciado_md?, author?, tags?, conf_text?,
#                                          examples?, tests?, good_sol?, title?, collections?}
# Edita um problema existente (repo git LOCAL da org). Commit autorado pelo login (sem Gitea).
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
org="${id%%#*}"; prob="${id##*#}"
[[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
require_problem_edit "$id"   # membro da org (senão 404, não revela existência)
pdir="$MOJ_PROBLEMS_DIR/$org/$prob"
[[ -d "$pdir" ]] || fail 404 "Problema não existe" "prob_missing"
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || owner="$SESSION_LOGIN"

apply_problem_fields "$pdir" "$body"
colls=""; jq -e 'has("collections")' >/dev/null 2>&1 <<<"$body" && colls="$(jq -c '.collections' <<<"$body")"
# CURADA: coleção marcada tem de EXISTIR no registro (mesma trava do set-collections).
if [[ -n "$colls" ]]; then
  while IFS= read -r cn; do [[ -n "$cn" ]] || continue
    coll_exists "$cn" || fail 400 "Coleção '$cn' não existe — crie antes (aba Coleções / moj collection create)" "coll_unknown"
  done < <(jq -r '.[]?' <<<"$colls")
fi
title="$(jq -r '.title // empty' <<<"$body")"
write_meta "$pdir" "$owner" "$org" "" "$colls" "$title"
bash "$MOJTOOLS_DIR/kattis/sidecar.sh" "$pdir" "$id" "$org" >/dev/null 2>&1 || true  # Kattis-aware

sha="$(problem_commit "$pdir" "$SESSION_LOGIN" "edita $prob")"
# atualiza o overlay (mantém public; título/coleções/autor do que está no pacote)
pub_now="$(jq -r 'if .public==true then "true" else "false" end' "$pdir/.moj-meta.json" 2>/dev/null)"
colls_now="$(jq -c '.collections // []' "$pdir/.moj-meta.json" 2>/dev/null)"
author_txt="$(cat "$pdir/author" 2>/dev/null | head -1)"
authored_upsert "$id" "$owner" "$org" "$prob" "$title" "${pub_now:-false}" "${colls_now:-[]}" "$author_txt" '[]'
audit_log "problem-edit" "id=$id by=$SESSION_LOGIN"
ok_json '{action:"edit", id:$id, sha:$s}' --arg id "$id" --arg s "${sha:0:12}"
