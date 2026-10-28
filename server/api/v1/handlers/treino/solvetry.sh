# GET /treino/solvetry[?user=<login>]   -> {solved:[ids], attempted:[ids]}
# Sem ?user usa o usuário logado. Calcula a partir do history do usuário.
# Regras (as MESMAS do /treino/history-full): (1) o "usuário logado" só vale numa sessão DO TREINO — numa sessão de
# outro contest o mesmo NOME é outra conta; (2) perfil privado — e dir ÓRFÃO, sem account.json, resíduo de
# rename/remoção — dá listas vazias p/ quem não é o dono nem admin do treino; (3) problema PRIVADO
# (private_problem_ids, a fonte única) sai da lista, menos p/ o próprio dono do history. Índice ilegível = 503 (falha
# FECHADA; o dono, o caso comum da lista do treino, nem lê o índice).
user="$(param user)"
me=""; load_session && [[ "${SESSION_CONTEST:-}" == treino ]] && me="$SESSION_LOGIN"
[[ -n "$user" ]] || user="$me"
[[ -n "$user" ]] || fail 400 "Missing user" "user_missing"
valid_id "$user" || fail 400 "Invalid user" "user_invalid"
self=0; [[ -n "$me" && "$user" == "$me" ]] && self=1
if (( !self )) && ! { [[ -n "$me" ]] && is_admin; } \
   && { [[ ! -f "$(account_file treino "$user")" ]] || ! profile_is_public treino "$user"; }; then
  ok_json '{solved:[], attempted:[]}'; exit 0
fi
PF=""
if (( !self )); then
  source "$_LIBDIR/problems.sh"
  PF="$(mktemp)" || fail 500 "Falha ao criar temporário" "tmp_failed"
  trap 'rm -f "$PF"' EXIT
  private_problem_ids > "$PF" || fail 503 "Índice de problemas indisponível — tente de novo em instantes" "index_unavailable"
fi

# users/<user>/history — emit_user_history normaliza p/ 7 campos. A lista de privados entra por getline no BEGIN
# (com `NR==FNR`, lista VAZIA casaria o history inteiro). Corpo ANTES do cabeçalho: falha = 500, nunca 200 vazio.
body="$(emit_user_history treino "$user" \
| awk -F: -v PF="$PF" '
  BEGIN { if (PF != "") while ((getline l < PF) > 0) priv[l] = 1 }
  ($3 in priv) { next }
  { if ($5 ~ /^Accepted/) s[$3]=1; else a[$3]=1 }
  END { for (k in s) print "S\t" k; for (k in a) if (!(k in s)) print "A\t" k }
' \
| jq -R -s -c '
    split("\n") | map(select(length>0))
    | reduce .[] as $l ({solved:[], attempted:[]};
        ($l|split("\t")) as $p
        | if $p[0]=="S" then .solved += [$p[1]] else .attempted += [$p[1]] end)
    | {success:true} + .')"
[[ -n "$body" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
emit_json 200 OK
printf '%s\n' "$body"
