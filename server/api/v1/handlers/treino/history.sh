# GET /treino/history?id=<problem>   (Bearer) -> TXT, histórico do usuário no problema.
# 7 campos por linha: tempo:username:problemid:lang:verdict:epoch:subid
require_auth_contest treino
id="$(param id)"
[[ -n "$id" ]] || fail 400 "Missing problem id" "id_missing"
valid_id "$id" || fail 400 "Invalid problem id" "id_invalid"
emit_text
# users/<login>/history (login implícito). emit_user_history
# devolve as duas no MESMO formato de 7 campos (com login), então o filtro por problema não muda.
# O verdict (campos 5..NF-2) sai CANÔNICO (lib/verdict.sh) — o detalhe vem do /submission/summary.
emit_user_history treino "$SESSION_LOGIN" | awk -F: -v p="$id" "$VERDICT_CANON_AWK"'
$3 == p { v = $5; for (i = 6; i <= NF-2; i++) v = v ":" $i
  print $1 ":" $2 ":" $3 ":" $4 ":" canon(v) ":" $(NF-1) ":" $NF }'
