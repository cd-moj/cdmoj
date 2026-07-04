# GET /contest/score?contest=<id>  -> TXT
# Serve o placar pré-gerado (controle/placar.txt, gerado por server/score/), cuja
# 1ª linha é o MODO (icpc/obi/treino/...). Se ausente, emite só a linha do modo.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
# contest SUPER SECRETO: o placar deixa de ser público — exige sessão DO contest
# (gate ANTES do regen preguiçoso: anônimo não gasta rebuild)
require_not_secret_or_auth "$contest"

f="$CONTESTSDIR/$contest/controle/placar.txt"
# Cache preguiçoso: (re)gera o placar se a fonte (history/conf) mudou ou se ele
# nunca foi montado. O daemon já reconstrói a cada veredicto; isto cobre contests
# importados/legados cujo placar nunca foi gerado (ficava eternamente vazio).
regen_locked "$CONTESTSDIR/$contest/var/.placar.lock" \
  "$f" "$CONTESTSDIR/$contest/controle/history" "$CONTESTSDIR/$contest/conf" \
  -- bash "$SCOREDIR/build.sh" "$contest"

# Privilegiados veem o placar COMPLETO (sem freeze): .admin/.judge SEMPRE + os logins na
# allowlist do conf (SCORE_FULL_USERS, espaço-separados, configurável pelo .admin). Auth é
# OPCIONAL aqui (placar é público): só checamos se houver token válido deste contest.
ff="$CONTESTSDIR/$contest/controle/placar-full.txt"
if [[ -f "$ff" ]] && load_session 2>/dev/null && [[ "$SESSION_CONTEST" == "$contest" ]]; then
  priv=0; is_judge && priv=1
  if [[ "$priv" == 0 ]]; then
    allow="$(. "$CONTESTSDIR/$contest/conf" 2>/dev/null; printf '%s' "${SCORE_FULL_USERS:-}")"
    case " $allow " in *" $SESSION_LOGIN "*) priv=1;; esac
  fi
  [[ "$priv" == 1 ]] && f="$ff"
fi

emit_text
if [[ -f "$f" ]]; then
  cat "$f"
else
  # placar ainda não gerado (contest sem history): front renderiza vazio pelo modo.
  score_mode_of "$contest"; printf '\n'
fi
