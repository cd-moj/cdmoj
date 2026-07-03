# POST /problems/move   (Bearer)   body: {id, to_org}
# Move um problema de RASCUNHO p/ outra ORG. Muda o id (<org>#<prob>), então só é permitido enquanto
# o problema NÃO está público / em uso (mover mudaria o id e órfãoria o histórico dos contests). Exige
# ser MEMBRO da org de origem E da org destino. O repo git local vai junto (mv do diretório).
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
to_org="$(jq -r '.to_org // .org // empty' <<<"$body")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
from_org="${id%%#*}"; prob="${id##*#}"; [[ "$prob" != "$id" ]] || fail 400 "Id sem '#'" "id_invalid"
[[ "$to_org" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$ ]] || fail 400 "Org destino inválida" "org_invalid"
[[ "$to_org" == "$from_org" ]] && fail 400 "Já está nessa org" "same_org"
require_problem_edit "$id"   # membro da org de origem (senão 404)
[[ "$to_org" == "$SESSION_LOGIN" ]] && ensure_implicit_org "$SESSION_LOGIN"
org_exists "$to_org" || fail 404 "Org destino não existe (crie com /orgs/create)" "org_missing"
org_is_member "$to_org" "$SESSION_LOGIN" || fail 403 "Você não é membro da org destino" "forbidden"

newid="$to_org#$prob"
src="$MOJ_PROBLEMS_DIR/$from_org/$prob"; dst="$MOJ_PROBLEMS_DIR/$to_org/$prob"
[[ -d "$src" ]] || fail 404 "Problema não existe" "prob_missing"
[[ -e "$dst" ]] && fail 409 "Já existe um problema com esse nome na org destino" "prob_exists"
# rascunho = privado; público está EM USO (alunos resolvem) -> não move (mudaria o id -> órfão)
ispub="$(owners_merged | jq -r --arg id "$id" 'first(.problems[]|select(.id==$id)).public // false' 2>/dev/null)"
[[ "$ispub" == "true" ]] && fail 409 "Problema público está em uso — despublique (ou duplique) em vez de mover" "is_public"

mkdir -p "$(dirname "$dst")"
mv "$src" "$dst" || fail 500 "Falha ao mover o diretório" "move_fail"
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || owner="$SESSION_LOGIN"
write_meta "$dst" "$owner" "$to_org" "" "" ""
problem_commit "$dst" "$SESSION_LOGIN" "move: $from_org#$prob -> $to_org" >/dev/null
# re-chaveia o estado por id (rascunho: normalmente vazio)
[[ -f "$RUNDIR/tl/$id.json" ]] && mv "$RUNDIR/tl/$id.json" "$RUNDIR/tl/$newid.json" 2>/dev/null
[[ -f "$RUNDIR/validation/$id.json" ]] && mv "$RUNDIR/validation/$id.json" "$RUNDIR/validation/$newid.json" 2>/dev/null
[[ -d "$RUNDIR/calib/$id" ]] && mv "$RUNDIR/calib/$id" "$RUNDIR/calib/$newid" 2>/dev/null
rm -f "$CONTESTSDIR/treino/var/jsons/$id.json" "$CONTESTSDIR/treino/var/jsons-private/$id.json" 2>/dev/null
authored_remove "$id"
colls="$(jq -c '.collections // []' "$dst/.moj-meta.json" 2>/dev/null)"; [[ -n "$colls" ]] || colls='[]'
title="$(jq -r '.display_title // ""' "$dst/.moj-meta.json" 2>/dev/null)"
author_txt="$(head -1 "$dst/author" 2>/dev/null)"
authored_upsert "$newid" "$owner" "$to_org" "$prob" "$title" false "$colls" "$author_txt" '[]'
audit_log "move" "from=$id to=$newid by=$SESSION_LOGIN"
ok_json '{action:"move", id:$new, from:$old}' --arg new "$newid" --arg old "$id"
