# GET /problems/source?id=<id>   (Bearer)
# Devolve o SOURCE do problema (enunciado/autor/tags/conf/exemplos/testes OCULTOS/SOLUÇÕES/editorial).
# ACESSO (garantido AQUI na API, nunca só na interface): conteúdo sensível => SÓ dono ou colaborador.
require_method GET
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

id="$(param id)"; [[ -n "$id" ]] || fail 400 "Missing id" "id_missing"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
repo="${id%%#*}"; prob="${id##*#}"
[[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
owner="$(problem_owner "$id")"
[[ -n "$owner" ]] || fail 404 "Problema não encontrado" "not_found"
# CORTE NA API: o source traz testes ocultos + soluções -> só dono/colaborador. Não-autorizado: 404
# (nem revela que existe). SEM atalho de .admin. Burlar pela interface não adianta: a trava está aqui.
require_problem_edit "$id"

# O canônico é a árvore LOCAL do problema (repo git por problema); leitura de arquivo pura.
pkg="$MOJ_PROBLEMS_DIR/$repo/$prob"
[[ -d "$pkg" ]] || fail 404 "Problema não encontrado" "not_found"
# O source pode ser GRANDE (todos os testes): vai p/ ARQUIVO e entra no jq por --slurpfile (ARG_MAX).
srcf="$(mktemp)"
read_problem_source "$pkg" > "$srcf"
[[ -s "$srcf" ]] || { rm -f "$srcf"; fail 500 "Falha ao ler o pacote do problema" "read_fail"; }
emit_json 200 OK
jq -cn --arg id "$id" --arg o "$owner" --slurpfile s "$srcf" \
  '{success:true, id:$id, owner:$o, editable:true} + $s[0]'
rm -f "$srcf"
