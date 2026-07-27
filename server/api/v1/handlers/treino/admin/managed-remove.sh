# POST /treino/admin/managed-remove  (.admin) {login} — remove uma conta GERIDA.
# mv p/ contests/treino/.removed-users/<login>-<epoch> (padrão do user-remove; submissões
# preservadas) + derruba sessões. Só contas geridas. docs/CONTAS-GERIDAS.md.
require_method POST
require_auth_contest treino
is_admin || fail 403 "Apenas administradores do treino" "admin_required"
body="$(read_body)"
login="$(jq -r '.login // empty' <<<"$body" 2>/dev/null)"
[[ -n "$login" ]] || fail 400 "Informe login" "login_missing"
valid_id "$login" || fail 400 "Login inválido" "login_invalid"
[[ "$login" == "$SESSION_LOGIN" ]] && fail 409 "Não remova a si mesmo" "self"
user_exists treino "$login" || fail 404 "Usuário não encontrado" "user_notfound"
[[ -n "$(managed_json treino "$login")" ]] || fail 400 "Não é uma conta gerida" "not_managed"

dst="$CONTESTSDIR/treino/.removed-users"
mkdir -p "$dst" 2>/dev/null
mv "$(user_dir treino "$login")" "$dst/${login}-$EPOCHSECONDS" \
  || fail 500 "Falha ao remover" "remove_fail"

set +o noglob; shopt -s nullglob
for f in "$SESSIONDIR"/*; do
  [[ -f "$f" ]] || continue
  lg="$( CONTEST=""; LOGIN=""; source "$f" 2>/dev/null; [[ "$CONTEST" == treino ]] && printf '%s' "$LOGIN" )"
  [[ "$lg" == "$login" ]] && rm -f "$f"
done
shopt -u nullglob
_score_dirty treino

audit_log managed-remove "login=$login"
ok_json '{removed:true, login:$l}' --arg l "$login"
