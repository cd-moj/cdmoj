# POST /problems/set-public   (Bearer)   body: {id, public:bool}
# Público **on** => a ORG precisa PERMITIR público (`public_allowed`), senão 403 (camada
# anti-vazamento de prova). Grava `public` no .moj-meta.json (commit LOCAL), VALIDA (index_problem_bg)
# + CALIBRA (cal_request a um juiz). **off** => sai do treino na hora. Só MEMBRO da org. AÇÃO EXPLÍCITA.
require_method POST
require_auth
source "$_DIR/../../judge-gw/sched-lib.sh"; source "$_DIR/lib/tl-store.sh"   # cal_request + index_problem_bg
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"

body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
id="$(jq -r '.id // empty' <<<"$body")"
valid_id "$id" || fail 400 "Invalid id" "id_invalid"
pub="$(jq -r 'if .public==true then "true" elif .public==false then "false" else "" end' <<<"$body")"
[[ -n "$pub" ]] || fail 400 "Missing public (bool)" "public_missing"
org="${id%%#*}"; prob="${id##*#}"
require_problem_edit "$id"   # membro da org (senão 404)
pdir="$MOJ_PROBLEMS_DIR/$org/$prob"; [[ -d "$pdir" ]] || fail 404 "Problema não existe" "prob_missing"

# TRAVA ANTI-VAZAMENTO: só publica se a ORG permitir (org privada => problemas nunca ficam públicos)
if [[ "$pub" == "true" ]]; then
  org_public_allowed "$org" || fail 403 "A org '$org' é privada — não permite tornar problemas públicos" "org_private"
fi
owner="$(problem_owner "$id")"; [[ -n "$owner" ]] || owner="$SESSION_LOGIN"
write_meta "$pdir" "$owner" "$org" "$pub" "" ""
# tornar público: tira o PUBLIC=no legado do conf (senão o gerador do treino ignora)
if [[ "$pub" == "true" && -f "$pdir/conf" ]]; then
  sed -i -E '/^[[:space:]]*PUBLIC[[:space:]]*=[[:space:]]*no[[:space:]]*$/d' "$pdir/conf" 2>/dev/null || true
fi
problem_commit "$pdir" "$SESSION_LOGIN" "set public=$pub ($prob)" >/dev/null
authored_patch "$id" '.public=($p=="true")' --arg p "$pub"
reqid=""
if [[ "$pub" == "true" ]]; then
  # público => fluxo completo: VALIDA (portão + índice) + CALIBRA (juiz roda as good, reporta TL)
  index_problem_bg "$id" 1
  reqid="$(cal_request "$org" "$id" "$SESSION_LOGIN")"
else
  # DESPUBLICAR: sai do treino livre NA HORA (índice servível + cache de 5min), não fica vazando
  rm -f "$CONTESTSDIR/treino/var/jsons/$id.json" "$CONTESTSDIR/treino/var/problems.json" 2>/dev/null
fi
audit_log "set-public" "id=$id public=$pub reqid=$reqid"
ok_json '{action:"set-public", id:$id, public:($p=="true"), reqid:$r}' \
  --arg id "$id" --arg p "$pub" --arg r "$reqid"
