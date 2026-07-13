# GET /contest/history?contest=<id>   (Bearer) -> TXT
# Submissões DO PRÓPRIO usuário no contest, do store por-usuário (emit_user_history, que
# normaliza users/<login>/history p/ o formato global de 7 campos) — o controle/history
# GLOBAL é do modelo legado e não existe nos contests v2.
# 7 campos por linha: tempo:username:problemid:lang:verdict:epoch:subid
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"

emit_text

# O competidor recebe o veredicto CANÔNICO em TODOS os modos (lib/verdict.sh; anti-leak:
# a string de display com score/grupos fica no disco). O DETALHE por modo (score/grupos/
# heurístico) sai pelo /submission/summary, redigido por verdict_detail_level.
# emit_user_history insere o login (2º campo) que o store mantém implícito -> 7 campos;
# o verdict (campos 5..NF-2, pode conter ':') é remontado antes de canonizar.
emit_user_history "$contest" "$SESSION_LOGIN" | awk -F: "$VERDICT_CANON_AWK"'
{ v = $5; for (i = 6; i <= NF-2; i++) v = v ":" $i
  print $1 ":" $2 ":" $3 ":" $4 ":" canon(v) ":" $(NF-1) ":" $NF }'
