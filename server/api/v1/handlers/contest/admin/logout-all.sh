# GET/POST /contest/admin/logout-all?contest=<c>   (admin)
# SAIR EM MASSA + TRAVA DE LOGIN — a troca de rodada: fechar o login, derrubar todo mundo,
# promover, reabrir quando os times puderem entrar.
#   GET  → {login_enabled, sessions:{competitors, staff, privileged}}
#   POST {scope:"competitors"|"staff"|"all", close_login?:true, open_login?:true}
#      scope competitors = toda conta que NÃO é de papel; staff = .staff + .cstaff; all = os dois.
#      NUNCA derruba .admin/.judge/.cjudge/.mon/.animeitor (quem opera a prova). Cada sessão
#      removida vira linha `logout` em var/session-events.log (com quem mandou); a ação vai ao
#      audit (`logout-all scope= competitors= staff= login=`). close_login grava LOGIN_ENABLED=n
#      (o /auth/login responde 403 login_disabled a não-papel); open_login apaga a variável
#      (aberto = default, mesma semântica do settings). Só POST muda algo.
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
require_auth_contest "$contest"
is_admin || fail 403 "Apenas o admin do contest" "admin_required"

_cls(){ # <login> -> competitor | staff | privileged
  case "$1" in *.admin|*.judge|*.cjudge|*.mon|*.animeitor) printf privileged;; *.staff|*.cstaff) printf staff;; *) printf competitor;; esac; }
_login_enabled(){ [[ "$(conf_value "$contest" LOGIN_ENABLED)" != n ]]; }

if [[ "$REQUEST_METHOD" == GET ]]; then
  nc=0; ns=0; np=0
  set +o noglob; shopt -s nullglob
  if sess_index_seeded "$contest"; then
    # índice por login (lib/session-index.sh): só os tokens DESTE contest — a varredura global
    # (20 mil arquivos na produção) era o que deixava o painel lento a cada 30 s
    for f in "$(_sidx_dir "$contest")"/*; do
      [[ -f "$f" && "$f" != *.lock ]] || continue
      LOGIN="${f##*/}"; n=0
      # token REPETIDO no índice (a semeadura é só apêndice — sessions.sh e anomalies.sh semeiam) contava 2× (6/2/4
      # com 3/1/2 reais; auditoria do painel, 03/10/2026)
      unset _seen; declare -A _seen=()
      while IFS= read -r t; do [[ -n "$t" && -z "${_seen[$t]:-}" ]] && valid_id "$t" && [[ -f "$SESSIONDIR/$t" ]] && { _seen[$t]=1; n=$((n+1)); }; done < "$f"
      unset _seen
      (( n )) || continue
      case "$(_cls "$LOGIN")" in competitor) nc=$((nc+n));; staff) ns=$((ns+n));; *) np=$((np+n));; esac
    done
  else
    while IFS= read -r -d '' f; do
      [[ -f "$f" ]] || continue
      CONTEST=""; LOGIN=""; source "$f" 2>/dev/null
      [[ "$CONTEST" == "$contest" && -n "$LOGIN" ]] || continue
      case "$(_cls "$LOGIN")" in competitor) nc=$((nc+1));; staff) ns=$((ns+1));; *) np=$((np+1));; esac
    done < <(sess_files_of "$contest")
  fi
  shopt -u nullglob
  le=false; _login_enabled && le=true
  # a abertura do login (LOGIN_START_TIME) também fecha a porta p/ os times — a pílula dizia "ABERTO" antes dela
  ls_at="$(conf_value "$contest" LOGIN_START_TIME)"; ls_at="${ls_at//[^0-9]/}"; ls_at="${ls_at:-0}"
  ok_json '{login_enabled:$le, login_start:$ls, login_open_now:($le and ($ls == 0 or $ls <= now)), sessions:{competitors:$c, staff:$s, privileged:$p}}' \
    --argjson le "$le" --argjson c "$nc" --argjson s "$ns" --argjson p "$np" --argjson ls "$ls_at"
  exit 0
fi

require_method POST
body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
scope="$(jq -r '.scope // ""' <<<"$body")"
case "$scope" in competitors|staff|all|"") ;; *) fail 422 "scope deve ser competitors|staff|all" "scope_invalid";; esac
close="$(jq -r '.close_login == true' <<<"$body")"; open="$(jq -r '.open_login == true' <<<"$body")"
[[ "$close" == true && "$open" == true ]] && fail 422 "close_login e open_login juntos" "conflict"
[[ -n "$scope" || "$close" == true || "$open" == true ]] || fail 400 "nada a fazer" "noop"

nc=0; ns=0
if [[ -n "$scope" ]]; then
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    CONTEST=""; LOGIN=""; MKEY=""; source "$f" 2>/dev/null
    [[ "$CONTEST" == "$contest" && -n "$LOGIN" ]] || continue
    cls="$(_cls "$LOGIN")"
    case "$scope:$cls" in competitors:competitor|staff:staff|all:competitor|all:staff) ;; *) continue;; esac
    rm -f "$f" || continue
    # ⚠ `((nc++))` devolve 1 quando nc era 0 — o `&&…||…` mandava o 1º competidor p/ o staff
    if [[ "$cls" == competitor ]]; then nc=$((nc+1)); else ns=$((ns+1)); fi
    sess_event "$contest" "$LOGIN" logout "$MKEY" "" "${f##*/}" "$SESSION_LOGIN"
  done < <(sess_files_of "$contest")
fi
source "$_DIR/lib/users.sh"; source "$_DIR/lib/contest-create.sh"
lstate="-"
if [[ "$close" == true ]]; then cc_set_conf_var "$contest" LOGIN_ENABLED n; lstate=closed; fi
if [[ "$open" == true ]]; then cc_del_conf_var "$contest" LOGIN_ENABLED; lstate=opened; fi
# conf mudou ⇒ caches que dependem dele (basic/placar) se refazem pelo -nt; o carimbo garante
[[ "$lstate" != - ]] && { mkdir -p "$CONTESTSDIR/$contest/var"; : > "$CONTESTSDIR/$contest/var/.score-dirty"; }
audit_log_to "$contest" logout-all "scope=${scope:--} competitors=$nc staff=$ns login=$lstate"
le=false; _login_enabled && le=true
ok_json '{logged_out:true, scope:$sc, competitors:$c, staff:$s, login_enabled:$le}' \
  --arg sc "${scope:-}" --argjson c "$nc" --argjson s "$ns" --argjson le "$le"
