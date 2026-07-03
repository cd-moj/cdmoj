# POST /problems/collection-create   (Bearer)   body: {name}
# Cria uma COLEÇÃO no registro CURADO (tag de agrupamento). O nome é TEXTO LIVRE (pode ter espaços/
# acentos — é só rótulo, nunca vira id/caminho). Exige permissão de criação (mesma regra de criar
# contest); o criador vira dono. (NÃO é uma org — acesso é por org; ver /orgs/create.)
require_method POST
require_auth
source "$_DIR/lib/problems.sh"; source "$_DIR/lib/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar coleção (igual a criar contest)" "create_forbidden"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
coll_valid_name "$name" || fail 400 "Nome de coleção inválido (1–80 caracteres, sem controle)" "name_invalid"
if coll_exists "$name"; then coll_can_manage "$name" "$SESSION_LOGIN" || fail 409 "Coleção já existe (dono: $(coll_owner "$name"))" "taken"; fi
coll_register "$name" "$SESSION_LOGIN"
audit_log "collection-create" "name=$name by=$SESSION_LOGIN"
ok_json '{action:"collection-create", name:$n, owner:$o, mine:true, can_manage:true}' \
  --arg n "$name" --arg o "$(coll_owner "$name")"
