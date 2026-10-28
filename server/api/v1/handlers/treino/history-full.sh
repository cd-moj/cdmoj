# GET /treino/history-full?user=<login>   -> TXT, todo o histórico do usuário.
# Se for o próprio usuário logado, pode vir autenticado (mesma saída).
# A mesma regra do /treino/solvetry: o "usuário logado" só vale numa sessão DO TREINO (o mesmo nome noutro contest é
# outra conta), e linha de problema PRIVADO (private_problem_ids) sai p/ quem não é o dono do history.
user="$(param user)"
isowner=0; isadm=0
if load_session && [[ "$SESSION_CONTEST" == treino ]]; then
  [[ -z "$user" ]] && user="$SESSION_LOGIN"
  [[ "$SESSION_LOGIN" == "$user" ]] && isowner=1; is_admin && isadm=1
fi
[[ -n "$user" ]] || fail 400 "Missing user" "user_missing"
valid_id "$user" || fail 400 "Invalid user" "user_invalid"

# privacidade: histórico de outro usuário só se o perfil for público (ou dono/admin). Dir ÓRFÃO (sem account.json —
# resíduo de rename/remoção, que o profile_is_public trataria como público) também é privado.
if (( !isowner && !isadm )) \
   && { [[ ! -f "$(account_file treino "$user")" ]] || ! profile_is_public treino "$user"; }; then
  emit_text; exit 0   # vazio -> a tela mostra "perfil privado"
fi

# ids PRIVADOS (private_problem_ids, a fonte única): falha FECHADA — sem a lista, 503, nunca o history inteiro
PF=""
if (( !isowner )); then
  source "$_LIBDIR/problems.sh"
  PF="$(mktemp)" || fail 500 "Falha ao criar temporário" "tmp_failed"
  trap 'rm -f "$PF"' EXIT
  private_problem_ids > "$PF" || fail 503 "Índice de problemas indisponível — tente de novo em instantes" "index_unavailable"
fi

# users/<user>/history (7 campos normalizados); verdict CANÔNICO (lib/verdict.sh) —
# o detalhe (testes/pontos) vem do /submission/summary, que é só do dono.
# A lista de privados entra por getline no BEGIN (com `NR==FNR`, lista VAZIA casaria o history inteiro).
# Corpo ANTES do cabeçalho (falha do awk = 500 honesto).
body="$(emit_user_history treino "$user" | awk -F: -v PF="$PF" "$VERDICT_CANON_AWK"'
BEGIN { if (PF != "") while ((getline l < PF) > 0) priv[l] = 1 }
($3 in priv) { next }
{ v = $5; for (i = 6; i <= NF-2; i++) v = v ":" $i
  print $1 ":" $2 ":" $3 ":" $4 ":" canon_team(v) ":" $(NF-1) ":" $NF }')" || fail 500 "Falha ao ler o histórico" "read_fail"
emit_text
[[ -z "$body" ]] || printf '%s\n' "$body"
