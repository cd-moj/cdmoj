# POST /problems/restore   (Bearer)   body: {id, sha, confirm}
# RESTAURA o problema ao estado de um commit antigo como um COMMIT NOVO (a história NUNCA é
# reescrita — dá p/ "des-restaurar" restaurando de volta). `confirm` tem de repetir o sha
# (padrão do delete). O **.moj-meta.json é PRESERVADO** (campos de ACESSO — public/collections/
# owner; um meta antigo poderia republicar prova privada — mesma doutrina do --exclude do
# upload). Sem revalidação/recalibração automática (igual ao edit: o painel acusa "precisa
# recalibrar" pelo checksum; o autor valida/calibra quando quiser). Só MEMBRO da org.
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
sha="$(jq -r '.sha // empty' <<<"$body")"
# regex ANTES de tocar o git (nunca começa com '-'; não vira flag)
[[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || fail 400 "sha inválido" "sha_invalid"
confirm="$(jq -r '.confirm // empty' <<<"$body")"
[[ "$confirm" == "$sha" ]] || fail 400 "confirm tem de repetir exatamente o sha" "confirm_mismatch"
require_problem_edit "$id"
pdir="$MOJ_PROBLEMS_DIR/$repo/$prob"
[[ -d "$pdir" && -d "$pdir/.git" ]] || fail 404 "Problema não encontrado" "not_found"
git -C "$pdir" cat-file -e "$sha^{commit}" 2>/dev/null || fail 404 "Commit não encontrado" "sha_unknown"

# 1) traz o CONTEÚDO do sha p/ índice+worktree (paths que existem no sha)
git -C "$pdir" restore --source="$sha" --staged --worktree -- . 2>/dev/null \
  || fail 500 "Falha ao restaurar do commit" "restore_fail"
# 2) apaga o que foi ADICIONADO depois do sha (não existe lá) — exceto o meta do servidor
while IFS= read -r -d '' f; do
  [[ "$f" == ".moj-meta.json" ]] && continue
  rm -f "$pdir/$f" 2>/dev/null
done < <(git -C "$pdir" diff --name-only --diff-filter=A -z "$sha" HEAD -- 2>/dev/null)
# 3) meta do SERVIDOR preservado (se o restore o trouxe do passado, volta o de HEAD)
git -C "$pdir" restore --source=HEAD --staged --worktree -- .moj-meta.json 2>/dev/null || true

newsha="$(problem_commit "$pdir" "$SESSION_LOGIN" "restaura versão ${sha:0:12} ($prob)")"
audit_log "restore" "id=$id from=${sha:0:12} to=${newsha:0:12} by=$SESSION_LOGIN"
ok_json '{action:"restore", id:$id, from:$f, sha:$s}' \
  --arg id "$id" --arg f "$sha" --arg s "${newsha:0:12}"
