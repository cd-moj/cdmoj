# GET /treino/contest-create/export?id=<cid>&full_statements=0|1  (auth treino, pode criar)
# Baixa o SPEC JSON de um contest existente (formato aceito pelo /create — round-trip).
# GATE: contest criado pela interface (created-by) E (dono OU admin do treino) — senão 404
# (não vaza a existência). NUNCA exporta passwd/users/senhas/submissões (só conf+problemas+
# visual). Enunciados: auto embute só o material exclusivo do contest; full_statements=1 tudo.
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
id="$(param id)"
{ [[ -n "$id" ]] && valid_id "$id"; } || fail 400 "Informe o id" "id_missing"
cdir="$CONTESTSDIR/$id"
cowner="$(head -1 "$cdir/owner" 2>/dev/null)"
{ [[ -f "$cdir/created-by" && -f "$cdir/conf" ]] && { is_admin || [[ -n "$cowner" && "$cowner" == "$SESSION_LOGIN" ]]; }; } \
  || fail 404 "Contest não encontrado" "notfound"
mode=auto; [[ "$(param full_statements)" == 1 ]] && mode=all
spec="$(cc_export_spec "$id" "$mode")"
[[ -n "$spec" ]] || fail 500 "Falha ao exportar" "export_fail"
audit_log contest-export "id=$id statements=$mode"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/json; charset=utf-8\r\n'
printf 'Content-Disposition: attachment; filename="%s-spec.json"\r\n' "$id"
printf '\r\n'
jq . <<<"$spec"
