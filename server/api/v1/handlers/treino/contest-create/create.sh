# POST /treino/contest-create  (auth treino, pode criar) -> cria e publica o contest (no ar na hora)
require_method POST
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"

# guarda: problemas PRIVADOS só entram se o criador tem acesso (dono/colaborador)
source "$_LIBDIR/problems.sh"
pids="$(jq -c '[.problems[]? | (.bank_id // .problem_id // "") | gsub("/";"#") | select(.!="")]' <<<"$body")"
if [[ "$pids" != "[]" ]]; then
  denied="$(owners_merged | jq -r --argjson pids "$pids" --arg me "$SESSION_LOGIN" '
    (.problems | map({key:.id, value:.}) | from_entries) as $by
    | [ $pids[] | . as $id | ($by[$id]) as $p
        | select($p != null and $p.owner != $me and ((($p.collaborators // [])|index($me))|not) and ($p.public|not)) | $id ]
    | unique | join(", ")' 2>/dev/null)"
  [[ -n "$denied" ]] && fail 403 "Sem acesso a problema(s) privado(s): $denied" "problem_denied"
fi

cc_create "$body" "$SESSION_LOGIN" "$SESSION_NAME"

# auto-validar problemas PRIVADOS sem enunciado pronto: enfileira index (gera jsons-private).
# O contest mostra o enunciado assim que o juiz indexar (fallback em contest/problems.sh).
source "$_DIR/../../judge-gw/sched-lib.sh" 2>/dev/null || source "$_LIBDIR/../judge-gw/sched-lib.sh" 2>/dev/null || true
if declare -F idx_request >/dev/null; then
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    [[ -f "$CONTESTSDIR/treino/var/jsons/$id.json" || -f "$CONTESTSDIR/treino/var/jsons-private/$id.json" ]] && continue
    repo="${id%%#*}"; [[ "$repo" != "$id" ]] || continue
    idx_request "$repo" "$id" "auto-contest:$SESSION_LOGIN" >/dev/null 2>&1 || true
  done < <(jq -r '.problems[]? | (.bank_id // .problem_id // "") | gsub("/";"#") | select(.!="")' <<<"$body")
fi

audit_log contest-create "id=$(jq -r '.contest_id' <<<"$CC_RESULT") mode=$(jq -r '.mode//"?"' <<<"$body") name=$(jq -r '.name//"?"' <<<"$body")"
ok_json '$r' --argjson r "$CC_RESULT"
