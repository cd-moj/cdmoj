# POST /treino/profile/password  {old_password, new_password}  -> troca a própria senha
require_method POST
require_auth_contest treino
login="$SESSION_LOGIN"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
old="$(jq -r '.old_password // empty' <<<"$body")"
new="$(jq -r '.new_password // empty' <<<"$body")"
[[ -n "$old" && -n "$new" ]] || fail 400 "Informe a senha atual e a nova" "missing"
verify_password treino "$login" "$old" || fail 403 "Senha atual incorreta" "bad_old"
[[ "$new" == *:* ]] && fail 400 "A senha não pode conter ':'" "pass_colon"
(( ${#new} >= 4 )) || fail 400 "Senha muito curta (mínimo 4 caracteres)" "pass_short"

user_set_password treino "$login" "$new" || fail 500 "Falha ao salvar a senha" "save_fail"
# as OUTRAS sessões da conta NO TREINO caem (a desta requisição fica; as de prova em contest que usa as contas do
# treino seguem — a pessoa pode estar no meio dela); a troca vai à trilha, com o IP
nout="$(RCS_KEEP_TOKEN="${SESSION_TOKEN:-}" remove_contest_sessions treino "$login")"
audit_log "password-change" "ip=$(client_ip) sessoes_encerradas=${nout:-0}"
ok_json '{updated:true}'
