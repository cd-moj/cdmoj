# GET /contest/score?contest=<id>  -> TXT
# Serve o placar pré-gerado (var/placar.txt, gerado por server/score/), cuja
# 1ª linha é o MODO (icpc/obi/treino/...). Se ausente, emite só a linha do modo.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
# contest SUPER SECRETO: o placar deixa de ser público — exige sessão DO contest
# (gate ANTES do regen preguiçoso: anônimo não gasta rebuild)
require_not_secret_or_auth "$contest"

f="$CONTESTSDIR/$contest/var/placar.txt"
# Cache preguiçoso: (re)gera o placar se a fonte mudou (var/.score-dirty, tocado a cada
# escrita de history; + conf) ou se ele nunca foi montado. O daemon já reconstrói a cada
# veredicto; isto cobre contests importados cujo placar nunca foi gerado.
regen_locked "$CONTESTSDIR/$contest/var/.placar.lock" \
  "$f" "$CONTESTSDIR/$contest/var/.score-dirty" "$CONTESTSDIR/$contest/conf" \
  -- bash "$SCOREDIR/build.sh" "$contest"

# Privilegiados veem o placar COMPLETO (sem freeze): .admin/.judge SEMPRE + os logins na
# allowlist do conf (SCORE_FULL_USERS, espaço-separados, configurável pelo .admin — vale
# também p/ liberar um .cstaff). Auth é OPCIONAL aqui (placar é público): só checamos se
# houver token válido deste contest.
# `view=public` força a visão PÚBLICA (congelada) mesmo p/ privilegiado — a cerimônia de
# reveal precisa das DUAS visões (frozen + full) p/ computar o delta.
# `scope=mine` (honrado SÓ p/ .cstaff): recorta o placar servido (frozen E full) aos
# usuários que o cstaff enxerga (staff-filters) — é a cerimônia POR SEDE. Fora da
# allowlist, o cstaff só recebe o full quando o contest terminou PARA TODOS
# (contest_over_for_all: fim base + a prorrogação mais tardia de time-overrides.json).
ff="$CONTESTSDIR/$contest/var/placar-full.txt"
sess=0
load_session 2>/dev/null && [[ "$SESSION_CONTEST" == "$contest" ]] && sess=1
if [[ "$(param view)" != public && -f "$ff" && "$sess" == 1 ]]; then
  priv=0; is_judge && priv=1
  if [[ "$priv" == 0 ]]; then
    allow="$(. "$CONTESTSDIR/$contest/conf" 2>/dev/null; printf '%s' "${SCORE_FULL_USERS:-}")"
    case " $allow " in *" $SESSION_LOGIN "*) priv=1;; esac
  fi
  if [[ "$priv" == 0 && "$(param scope)" == mine ]] && is_cstaff; then
    source "$_LIBDIR/contest-gate.sh"
    contest_over_for_all "$contest" && priv=1
  fi
  [[ "$priv" == 1 ]] && f="$ff"
fi

emit_text
if [[ -f "$f" ]]; then
  if [[ "$sess" == 1 && "$(param scope)" == mine ]] && is_cstaff; then
    source "$_LIBDIR/print.sh"
    pr_filter_board "$contest" "$SESSION_LOGIN" < "$f"
  else
    cat "$f"
  fi
else
  # placar ainda não gerado (contest sem history): front renderiza vazio pelo modo.
  score_mode_of "$contest"; printf '\n'
fi
