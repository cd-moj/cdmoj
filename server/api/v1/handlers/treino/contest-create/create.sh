# POST /treino/contest-create  (auth treino, pode criar) -> cria e publica o contest (no ar na hora)
require_method POST
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"

# guarda: problemas PRIVADOS só entram se o criador tem acesso (dono, colaborador ou MEMBRO da org) — topo E rodadas
# planejadas (a promoção aplica a lista da rodada sem passar por aqui de novo). Fonte única: cc_spec_guard.
cc_spec_guard "$body" "$SESSION_LOGIN"

cc_create "$body" "$SESSION_LOGIN" "$SESSION_NAME"

# auto-indexar problemas PRIVADOS sem enunciado pronto (gera o jsons-private, de onde o contest lê).
# Era `idx_request` (fila kind=index p/ o juiz) — mas o agente responde "legado, nada a fazer no juiz"
# (judge/agent/moj-agent.sh): era NO-OP, e um contest com problema privado nunca indexado ficava sem
# enunciado. Quem indexa é o SERVIDOR: index_problem_bg (portão estático + jsons-private).
source "$_DIR/lib/tl-store.sh" 2>/dev/null || true
if declare -F index_problem_bg >/dev/null; then
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    [[ -f "$CONTESTSDIR/treino/var/jsons/$id.json" || -f "$CONTESTSDIR/treino/var/jsons-private/$id.json" ]] && continue
    [[ "${id%%#*}" != "$id" ]] || continue
    index_problem_bg "$id" 1 >/dev/null 2>&1 || true
  done < <(jq -r '.problems[]? | (.bank_id // .problem_id // "") | gsub("/";"#") | select(.!="")' <<<"$body")
fi

_cid="$(jq -r '.contest_id' <<<"$CC_RESULT")"
audit_log contest-create "id=$_cid mode=$(jq -r '.mode//"?"' <<<"$body") name=$(jq -r '.name//"?"' <<<"$body") $(cc_audit_summary "$_cid")"
ok_json '$r' --argjson r "$CC_RESULT"
