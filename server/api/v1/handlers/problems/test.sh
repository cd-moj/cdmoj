# GET /problems/test?id=<id>&name=<teste>   (Bearer)
# Conteúdo de UM teste (input+output) do pacote — o par do `tests=meta` do /problems/source:
# o editor web lista nome/tamanho e busca o conteúdo só do teste que o setter for editar.
# ACESSO: mesmo gate do source (teste oculto é conteúdo sensível) — só dono/colaborador; 404.
require_method GET
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"
[[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
name="$(param name)"; [[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
# nome de teste: sem '/', sem '..' — o path vem do cliente e NUNCA pode escapar de tests/
[[ "$name" =~ ^[A-Za-z0-9._-]{1,120}$ && "$name" != .. && "$name" != .* ]] \
  || fail 400 "Nome de teste inválido" "name_invalid"

owner="$(problem_owner "$id")"
[[ -n "$owner" ]] || fail 404 "Problema não encontrado" "not_found"
require_problem_edit "$id"

pkg="$MOJ_PROBLEMS_DIR/$repo/$prob"
inp="$pkg/tests/input/$name"
[[ -f "$inp" ]] || fail 404 "Teste não encontrado" "test_notfound"
outp="$pkg/tests/output/$name"; [[ -f "$outp" ]] || outp=/dev/null

body="$(jq -nc --arg nm "$name" --rawfile i "$inp" --rawfile o "$outp" \
  '{success:true, name:$nm, input:$i, output:$o}')" || fail 500 "Falha ao ler o teste" "read_fail"
[[ -n "$body" ]] || fail 500 "Falha ao ler o teste" "read_fail"

emit_json 200 OK
printf '%s\n' "$body"
