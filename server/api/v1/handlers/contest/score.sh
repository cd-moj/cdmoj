# GET /contest/score?contest=<id>  -> TXT
# Serve o placar pré-gerado (controle/placar.txt, gerado por server/score/), cuja
# 1ª linha é o MODO (icpc/obi/treino/...). Se ausente, emite só a linha do modo.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"

f="$CONTESTSDIR/$contest/controle/placar.txt"
# Cache preguiçoso: (re)gera o placar se a fonte (history/conf) mudou ou se ele
# nunca foi montado. O daemon já reconstrói a cada veredicto; isto cobre contests
# importados/legados cujo placar nunca foi gerado (ficava eternamente vazio).
regen_locked "$CONTESTSDIR/$contest/var/.placar.lock" \
  "$f" "$CONTESTSDIR/$contest/controle/history" "$CONTESTSDIR/$contest/conf" \
  -- bash "$SCOREDIR/build.sh" "$contest"

emit_text
if [[ -f "$f" ]]; then
  cat "$f"
else
  # placar ainda não gerado (contest sem history): front renderiza vazio pelo modo.
  score_mode_of "$contest"; printf '\n'
fi
