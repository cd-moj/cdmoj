# POST /problems/edit   (Bearer)   body: {id, enunciado_md?, author?, tags?, conf_text?,
#                                          examples?, tests?, good_sol?, title?, collections?, languages?}
# Edita um problema existente (repo git LOCAL da org). Commit autorado pelo login (sem Gitea).
#
# O CORPO VEM EM ARQUIVO (read_body_file), nunca em variável: um pacote de 84 MB vira ~100 MB de JSON,
# e cada `jq … <<<"$body"` REGRAVA os 100 MB num temp e RE-PARSEIA tudo. Este handler fazia 5 dessas
# + 31 dentro do apply_problem_fields => ~50s de CPU, 3,6 GB de I/O, 504 do nginx aos 120s — e o
# pacote ficava PELA METADE (testes trocados, meta não). Aqui: UMA passada de jq p/ os escalares.
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

bodyf="$(read_body_file)"
trap 'rm -f "$bodyf"' EXIT
jq -e . >/dev/null 2>&1 < "$bodyf" || fail 400 "Invalid JSON body" "bad_json"

# 1 passada p/ TUDO que este handler precisa do corpo (id/título/coleções/linguagens)
eval "$(jq -r '
    "H_ID=\((.id // "") | @sh)",
    "H_TITLE=\((.title // "") | @sh)",
    "H_HASCOLLS=\(if has("collections") then 1 else 0 end)",
    "H_COLLS=\(((.collections // []) | tojson) | @sh)",
    "H_HASLANGS=\(if has("languages") then 1 else 0 end)",
    "H_LANGS=\(((.languages // []) | tojson) | @sh)"
  ' < "$bodyf" 2>/dev/null)"

id="$H_ID"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
org="${id%%#*}"; prob="${id##*#}"
[[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
require_problem_edit "$id"   # membro da org (senão 404, não revela existência)
pdir="$MOJ_PROBLEMS_DIR/$org/$prob"
[[ -d "$pdir" ]] || fail 404 "Problema não existe" "prob_missing"
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || owner="$SESSION_LOGIN"

# CURADA: coleção marcada tem de EXISTIR no registro (mesma trava do set-collections). Antes de
# escrever qualquer coisa — reprovar depois de aplicar deixaria o pacote e o meta divergentes.
colls=""
if (( H_HASCOLLS )); then
  colls="$H_COLLS"
  while IFS= read -r cn; do [[ -n "$cn" ]] || continue
    coll_exists "$cn" || fail 400 "Coleção '$cn' não existe — crie antes (aba Coleções / moj collection create)" "coll_unknown"
  done < <(jq -r '.[]?' <<<"$colls")
fi
title="$H_TITLE"
# languages: restrição de submissão por-problema ([]/ausente = todas). O flag distingue "não mandou"
# (não mexe) de "mandou []" (limpa) — mesmo padrão do collections acima.
langs=""; (( H_HASLANGS )) && langs="$H_LANGS"

apply_problem_fields "$pdir" "$bodyf" || fail 400 "Corpo do problema ilegível" "bad_body"
write_meta "$pdir" "$owner" "$org" "" "$colls" "$title" "$langs"
bash "$MOJTOOLS_DIR/kattis/sidecar.sh" "$pdir" "$id" "$org" >/dev/null 2>&1 || true  # Kattis-aware

sha="$(problem_commit "$pdir" "$SESSION_LOGIN" "edita $prob")"
# atualiza o overlay (mantém public; título/coleções/autor do que está no pacote)
pub_now="$(jq -r 'if .public==true then "true" else "false" end' "$pdir/.moj-meta.json" 2>/dev/null)"
colls_now="$(jq -c '.collections // []' "$pdir/.moj-meta.json" 2>/dev/null)"
author_txt="$(head -1 "$pdir/author" 2>/dev/null)"
authored_upsert "$id" "$owner" "$org" "$prob" "$title" "${pub_now:-false}" "${colls_now:-[]}" "$author_txt" '[]'
audit_log "problem-edit" "id=$id by=$SESSION_LOGIN"
ok_json '{action:"edit", id:$id, sha:$s}' --arg id "$id" --arg s "${sha:0:12}"
