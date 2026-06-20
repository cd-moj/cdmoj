# GET /contest/score?contest=<id>  -> TXT
# Serve o placar pré-gerado (controle/placar.txt, gerado por server/score/), cuja
# 1ª linha é o MODO (icpc/obi/treino/...). Se ausente, emite só a linha do modo.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"

emit_text
f="$CONTESTSDIR/$contest/controle/placar.txt"
if [[ -f "$f" ]]; then
  cat "$f"
else
  # placar ainda não gerado: front renderiza vazio com base no modo da 1ª linha.
  score_mode_of "$contest"; printf '\n'
fi
