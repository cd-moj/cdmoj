# GET /problems/source?id=<id>   (Bearer)
# Devolve o SOURCE editável do problema (enunciado/autor/tags/conf/exemplos/testes/good).
# Fonte = Gitea. Dono+escrita => editável; dono mas sem escrita => somente leitura (não "legado").
require_method GET
require_auth
source "$_DIR/lib/gitea.sh"; source "$_DIR/lib/problems.sh"; source "$MOJTOOLS_DIR/git-broker.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"
[[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
owner="$(problem_owner "$id")"
# O Gitea é a fonte única: todo problema tem dono. Sem dono => não está no Gitea (não há "legado").
[[ -n "$owner" ]] || fail 404 "Problema não está no Gitea" "not_gitea"

# Materializa o espelho na 1ª vez com o token do DONO (a LEITURA vale p/ qualquer um); depois é
# leitura de arquivo pura. NÃO clona por leitura (repo pode ter 1GB+; clone custava ~5s/abertura).
pkg="$MOJ_PROBLEMS_DIR/$repo/$prob"
[[ -d "$MOJ_PROBLEMS_DIR/$repo/.git" ]] || ensure_repo_materialized "$repo" "$owner"
[[ -d "$pkg" ]] || fail 404 "Problema não encontrado" "not_found"
# O source pode ser GRANDE (todos os testes): vai p/ ARQUIVO e entra no jq por --slurpfile.
# Passar via --argjson estourava o ARG_MAX -> corpo VAZIO (editor em branco) em problema grande.
srcf="$(mktemp)"
read_problem_source "$pkg" > "$srcf"
[[ -s "$srcf" ]] || { rm -f "$srcf"; fail 500 "Falha ao ler o pacote do problema" "read_fail"; }

# Editável só se o usuário logado tem escrita no Gitea. Quem não é dono/colaborador vê SOMENTE
# LEITURA — isso NÃO é "legado" (o problema está no Gitea), é só falta de permissão.
if gitea_can_write "$owner" "$repo" "$SESSION_LOGIN"; then
  emit_json 200 OK
  jq -cn --arg id "$id" --arg o "$owner" --slurpfile s "$srcf" \
    '{success:true, id:$id, owner:$o, editable:true} + $s[0]'
else
  emit_json 200 OK
  jq -cn --arg id "$id" --arg o "$owner" --slurpfile s "$srcf" \
    '{success:true, id:$id, owner:$o, editable:false,
      note:"Somente leitura — você não é dono nem colaborador deste problema."} + $s[0]'
fi
rm -f "$srcf"
