# GET /treino/virtual/problems?contest=<cid>   (Bearer do TREINO)
# Os problemas da prova — letra, id, nome, linguagens do CONTEST, idiomas do enunciado. Só com a
# run LARGADA (rodando/terminada): antes disso 403 `virtual_not_started`. O ENUNCIADO não sai daqui:
# o virtual só existe p/ problema PÚBLICO, então o cliente o busca na rota pública de sempre
# (`/treino/problem?id=`) — esta feature não cria caminho novo até conteúdo de problema.
require_method GET
require_auth_contest treino
source "$_LIBDIR/virtual.sh"; source "$_LIBDIR/langs.sh"
cid="$(param contest)"; vr_gate "$cid"
vr_lock "$SESSION_LOGIN" && { vr_refresh "$SESSION_LOGIN" "$cid"; vr_unlock; }
case "$(vr_effective "$(vr_state "$SESSION_LOGIN" "$cid")")" in
  running|judging|finished) ;;
  *) fail 403 "Comece a participação virtual para ver os problemas" "virtual_not_started" ;;
esac
out="$(for i in "${!VR_CANON[@]}"; do
  id="${VR_CANON[i]}"; wl="$(effective_problem_langs "$cid" "$id")"; [[ -n "$wl" ]] || wl='[]'
  jq -c --arg l "${VR_SHORT[i]}" --arg id "$id" --arg n "${VR_NAME[i]}" --argjson wl "$wl" \
    '{letter:$l, id:$id, name:$n, languages:$wl, statement_langs:(.statement_langs // ["pt"])}' \
    "$CONTESTSDIR/treino/var/jsons/$id.json"
done | jq -cs .)"
[[ -n "$out" ]] || fail 500 "Falha ao montar a lista" "build_fail"
ok_json '{contest:$c, problems:$p}' --arg c "$VR_CID" --argjson p "$out"
