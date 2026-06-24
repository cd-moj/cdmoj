# GET /problems/source?id=<id>   (Bearer)
# Devolve o SOURCE editável do problema (enunciado/autor/tags/conf/exemplos/testes/good).
# Residente no Gitea (editável) -> clona e lê; legado (MOJ_PROBLEMS_DIR) -> lê read-only.
require_method GET
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$MOJTOOLS_DIR/git-broker.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"
[[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
owner="$(problem_owner "$id")"

if [[ -n "$owner" ]] && gitea_can_write "$owner" "$repo" "$SESSION_LOGIN"; then
  tmp="$(git_broker_open "$SESSION_LOGIN" "$owner" "$repo")" || fail 502 "Falha ao abrir o repositório" "git_open"
  trap 'rm -rf "$tmp"' EXIT
  pkg="$tmp/wt/$prob"
  [[ -d "$pkg" ]] || fail 404 "Problema não existe no diretório" "prob_missing"
  src="$(read_problem_source "$pkg")"
  emit_json 200 OK
  jq -cn --argjson s "$src" --arg id "$id" --arg o "$owner" \
    '{success:true, id:$id, owner:$o, editable:true} + $s'
else
  # legado: só leitura (precisa migrar p/ o Gitea para editar pela web)
  pkg="$MOJ_PROBLEMS_DIR/$repo/$prob"
  [[ -d "$pkg" ]] || fail 404 "Problema não encontrado" "not_found"
  src="$(read_problem_source "$pkg")"
  emit_json 200 OK
  jq -cn --argjson s "$src" --arg id "$id" --arg o "${owner:-}" \
    '{success:true, id:$id, owner:(if $o=="" then null else $o end), editable:false,
      note:"Problema legado — migre p/ o Gitea para editar pela web."} + $s'
fi
