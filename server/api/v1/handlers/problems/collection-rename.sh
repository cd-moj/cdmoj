# POST /problems/collection-rename   (Bearer)   body: {name, to}
# Renomeia uma COLEÇÃO: o REGISTRO troca na hora; a tag nos N problemas (bulk retag + commit +
# re-index dos públicos) roda em BACKGROUND — síncrono estourava o timeout do nginx com N grande
# (rename da obi, 254 problemas: o cliente via erro e o loop morria no meio). Só o DONO da
# coleção ou admin global. `to` é texto livre (pode ter espaços).
# RETOMADA: se `name` já NÃO existe mas `to` existe (bulk anterior morreu no meio), repete só o
# retag — chamar de novo com os mesmos argumentos conserta o resto (o bulk é retomável: processa
# só metas que ainda têm a tag velha).
require_method POST
require_auth
source "$_DIR/lib/problems.sh"
body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
to="$(jq -r '.to // empty' <<<"$body" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
[[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
resume=0
if coll_exists "$name"; then
  coll_can_manage "$name" "$SESSION_LOGIN" || fail 403 "Só o dono da coleção (ou admin) renomeia" "forbidden"
  coll_valid_name "$to" || fail 400 "Novo nome inválido (1–80 caracteres, sem controle)" "name_invalid"
  [[ "$to" == "$name" ]] && fail 400 "Mesmo nome" "same"
  coll_exists "$to" && fail 409 "Já existe uma coleção '$to'" "taken"
  coll_rename "$name" "$to"
elif coll_exists "$to"; then
  coll_can_manage "$to" "$SESSION_LOGIN" || fail 403 "Só o dono da coleção (ou admin) renomeia" "forbidden"
  resume=1   # registro já renomeado; só refaz o retag dos metas que sobraram
else
  fail 404 "Coleção não existe" "not_found"
fi
job="$(coll_bulk_retag_bg "$name" "$to" "$SESSION_LOGIN")"
audit_log "collection-rename" "from=$name to=$to resume=$resume job=$job by=$SESSION_LOGIN (retag em background)"
ok_json '{action:"collection-rename", name:$to, from:$from, retag:"background", retag_job:$job, resumed:($r=="1")}' \
  --arg to "$to" --arg from "$name" --arg r "$resume" --arg job "$job"
