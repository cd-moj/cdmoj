# POST /orgs/set-public-allowed  (Bearer)  body: {name, public_allowed:bool}
# Trava anti-vazamento: se OFF (padrão), NENHUM problema da org pode ficar público. Só admin da org
# (ou admin global). A org IMPLÍCITA nunca liga. Desligar DESPUBLICA em cascata os problemas públicos
# da org — a cascata entra no rework de set-public (Fase 4); por ora, vira só a flag.
require_method POST
require_auth
source "$_DIR/lib/orgs.sh"; source "$_DIR/lib/problems.sh"
source "$_DIR/lib/tl-store.sh"   # unindex_problem (lista do treino invalida por evento)
body="$(read_body)"; jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
name="$(jq -r '.name // empty' <<<"$body")"
[[ -n "$name" ]] || fail 400 "Missing name" "name_missing"
org_exists "$name" || fail 404 "Org não encontrada" "not_found"
org_can_manage "$name" "$SESSION_LOGIN" || fail 403 "Só um admin da org muda a trava de público" "forbidden"
pa="$(jq -r 'if .public_allowed==true then "true" elif .public_allowed==false then "false" else "" end' <<<"$body")"
[[ -n "$pa" ]] || fail 400 "public_allowed deve ser bool" "bad_value"
org_set_public_allowed "$name" "$pa"; rc=$?
case "$rc" in
  0) ;;
  3) fail 409 "Org implícita é sempre privada (não permite público)" "implicit_private" ;;
  *) fail 500 "Falha ao gravar a trava" "write_failed" ;;
esac
# CASCATA anti-vazamento: rebaixar p/ privada DESPUBLICA os problemas públicos da org (tira do treino
# na hora). Sem isso, a trava só valeria p/ publicações futuras — e prova já pública continuaria vazando.
unpub=0
if [[ "$pa" == "false" ]]; then
  # varre os DIRETÓRIOS da org (robusto, independe do índice; find por causa do -o noglob da API)
  while IFS= read -r pdir; do
    [[ -d "$pdir" && -f "$pdir/.moj-meta.json" ]] || continue
    jq -e '.public==true' >/dev/null 2>&1 < "$pdir/.moj-meta.json" || continue
    prob="$(basename "$pdir")"; pid="$name#$prob"
    powner="$(problem_owner "$pid")"; [[ -n "$powner" ]] || powner="$SESSION_LOGIN"
    write_meta "$pdir" "$powner" "$name" false "" ""
    problem_commit "$pdir" "$SESSION_LOGIN" "org privada: despublica $prob" >/dev/null
    authored_patch "$pid" '.public=false'
    unindex_problem "$pid"
    unpub=$((unpub+1))
  done < <(find "$MOJ_PROBLEMS_DIR/$name" -maxdepth 1 -mindepth 1 -type d ! -name '.git' 2>/dev/null)
  [[ "$unpub" -gt 0 ]] && rm -f "$CONTESTSDIR/treino/var/problems.json" 2>/dev/null
fi
audit_log "org-public-allowed" "name=$name public_allowed=$pa unpublished=$unpub by=$SESSION_LOGIN"
ok_json '{action:"org-set-public-allowed", name:$n, public_allowed:$pa, unpublished:$u}' \
  --arg n "$name" --argjson pa "$pa" --argjson u "$unpub"
