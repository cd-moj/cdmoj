# POST /treino/admin/contest-remove  (.admin do treino) {contest, confirm:<o mesmo id>}
# Move um contest CRIADO PELA INTERFACE para contests/.trash (reversível). Não toca em contests legados.
# Quem remove: o DONO do contest ou o super-admin (16/10/2026 — a tela já só oferecia a eles, mas a API deixava um
# .admin comum remover o contest de qualquer criador sem papel). `confirm` = o id digitado: a confirmação era só do
# navegador; CLI antiga (sem o campo) leva 400 com a dica de atualizar.
require_method POST
require_treino_admin
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
cid="$(jq -r '.contest // empty' <<<"$body")"
[[ -n "$cid" ]] || fail 400 "Informe o contest" "missing"
valid_id "$cid" || fail 400 "contest inválido" "contest_invalid"
d="$CONTESTSDIR/$cid"
[[ -d "$d" && -f "$d/conf" ]] || fail 404 "Contest não encontrado" "notfound"
[[ -f "$d/created-by" ]] || fail 403 "Só é possível remover contests criados pela interface" "not_user_created"
# mesmo escopo da lista: contest que este admin não vê responde 404 (não confirma a existência)
source "$_LIBDIR/contest-create.sh"
owner="$(cc_contest_owner "$cid")"
cc_contest_visible_to "$SESSION_LOGIN" "$owner" || fail 404 "Contest não encontrado" "notfound"
[[ "$owner" == "$SESSION_LOGIN" ]] || is_superadmin \
  || fail 403 "Só o dono do contest ($owner) ou o super-admin da plataforma pode removê-lo" "remove_forbidden"
[[ "$(jq -r '.confirm // "" | tostring' <<<"$body")" == "$cid" ]] \
  || fail 400 "Para remover, confirme digitando o id do contest ($cid). Usando a CLI? Atualize: moj-contest update" "confirm_mismatch"
trash="$CONTESTSDIR/.trash"; mkdir -p "$trash"
dest="$cid-$EPOCHSECONDS"
mv "$d" "$trash/$dest" 2>/dev/null || fail 500 "Falha ao remover" "remove_fail"
audit_log contest-remove "id=$cid dono=$owner lixeira=.trash/$dest ip=$(client_ip)"
ok_json '{removed:true, contest:$c, trash:$t}' --arg c "$cid" --arg t ".trash/$dest"
