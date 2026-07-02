# GET /treino/history-full?user=<login>   -> TXT, todo o histórico do usuário.
# Se for o próprio usuário logado, pode vir autenticado (mesma saída).
user="$(param user)"
if [[ -z "$user" ]]; then load_session && user="$SESSION_LOGIN"; fi
[[ -n "$user" ]] || fail 400 "Missing user" "user_missing"
valid_id "$user" || fail 400 "Invalid user" "user_invalid"

# privacidade: histórico de outro usuário só se o perfil for público (ou dono/admin)
isowner=0; isadm=0
if load_session && [[ "$SESSION_CONTEST" == treino ]]; then
  [[ "$SESSION_LOGIN" == "$user" ]] && isowner=1; is_admin && isadm=1
fi
if (( !isowner && !isadm )) && ! profile_is_public treino "$user"; then
  emit_text; exit 0   # vazio -> a tela mostra "perfil privado"
fi

emit_text
emit_user_history treino "$user"   # store-v2 (users/<user>/history) ou legado (controle/history)
