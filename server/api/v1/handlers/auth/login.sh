# POST /auth/login?contest=<id>   body: {username, password}
require_method POST
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"

body="$(read_body)"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "Invalid JSON body" "bad_json"
u="$(jq -r '.username // empty' <<<"$body")"
p="$(jq -r '.password // empty' <<<"$body")"
[[ -n "$u" && -n "$p" ]] || fail 400 "Missing credentials" "creds_missing"

verify_password "$contest" "$u" "$p" || fail 401 "Wrong user or password" "bad_creds"

# conta GERIDA com expiração vencida não entra (docs/CONTAS-GERIDAS.md); 1 jq só p/ quem
# tem .managed.expires_at — custo desprezível no caminho quente
_mexp="$(account_field "$contest" "$u" '.managed.expires_at')"; _mexp="${_mexp//[^0-9]/}"
[[ -n "$_mexp" ]] && (( _mexp < EPOCHSECONDS )) \
  && fail 403 "Conta expirada — fale com o responsável que a criou" "account_expired"

# Gate por USER-AGENT. Racional: o browser da máquina de prova manda um UA único; só quem tem
# aquele UA loga. O esperado é POR SEDE — a imagem de cada sede carrega um pedaço do próprio
# login do time (teambrspso001 -> "brspso") —, com override por sede e lista de isentos:
# lib/ua-gate.sh resolve tudo e cai no LOGIN_UA_SUBSTRING legado quando não há ua-gate.json.
# Papéis privilegiados seguem isentos (precisam entrar para configurar).
source "$_LIBDIR/ua-gate.sh"
ug_ok "$contest" "$u" "${HTTP_USER_AGENT:-}" \
  || fail 403 "Login bloqueado: este navegador/máquina não está autorizado para o contest (sede errada?)" "ua_gate"

# --- A PORTA DO CONTEST (é a API que corta; o countdown do front é só conveniência) ------
# LOGIN_ENABLED/LOGIN_START_TIME existiam só no conf e no desenho da tela — quem chamasse a
# API direto entrava assim mesmo. Agora valem aqui, junto do roster de inscritos
# (lib/registration.sh). Conta de PAPEL nunca é barrada: o organizador precisa entrar antes
# de todo mundo (e p/ configurar a prova).
source "$_LIBDIR/registration.sh"
if ! is_reserved_role_login "$u"; then
  # \x01 como separador: campo vazio no meio DESLOCA os seguintes quando o IFS é tab (ver CLAUDE.md)
  _dc="$( ( LOGIN_ENABLED=""; LOGIN_START_TIME=""; source "$CONTESTSDIR/$contest/conf" 2>/dev/null
            printf '%s\x01%s' "${LOGIN_ENABLED:-}" "${LOGIN_START_TIME:-}" ) )"
  IFS=$'\x01' read -r _le _ls <<<"$_dc"
  [[ "$_le" == n ]] && fail 403 "O acesso a este contest está fechado" "login_disabled"
  [[ "$_ls" =~ ^[0-9]+$ ]] && (( EPOCHSECONDS < _ls )) \
    && fail 403 "O acesso a este contest ainda não abriu" "login_not_open"
  # reg_gate_active: no AQUECIMENTO a porta fica aberta (qualquer conta da fonte entra e brinca);
  # a inscrição só é exigida quando a PROVA entra no ar. Quem passou pelo aquecimento sem se
  # inscrever é varrido na promoção (reg_sweep_unregistered) — sessão não expira sozinha.
  if reg_gate_active "$contest" && ! reg_is_registered "$contest" "$u"; then
    case "$(reg_window_state "$contest")" in
      open|late) fail 403 "Você não está inscrito neste contest — a inscrição ainda está aberta na página do contest" "not_registered" ;;
      soon)      fail 403 "As inscrições deste contest ainda não abriram" "registration_not_open" ;;
      *)         fail 403 "As inscrições deste contest estão encerradas" "registration_closed" ;;
    esac
  fi
fi

# --- ALIAS DE TIME: o membro autentica com a credencial DELE e a sessão vira a do TIME ----
# O competidor é o time (uma linha no placar, um balão, uma fila de impressão); a pessoa fica
# registrada como ATOR, p/ o organizador saber quem estava no teclado.
actor=""
if reg_enabled "$contest"; then
  _team="$(reg_team_of "$contest" "$u")"
  if [[ -n "$_team" ]] && user_exists "$contest" "$_team"; then actor="$u"; u="$_team"; fi
fi

name="$(user_fullname "$contest" "$u")"
tok="$(create_session "$contest" "$u" "$name" "$actor")"
# log de acesso (tab-sep: epoch, login, ip, ua_b64[, ator]) — a 5ª coluna só existe em sessão
# de time; os leitores (access-log, machines, audit) cortam em $1..$4 e a ignoram.
mkdir -p "$CONTESTSDIR/$contest/var"
printf '%s\t%s\t%s\t%s%s\n' "$EPOCHSECONDS" "$u" "$(client_ip)" \
  "$(printf '%s' "${HTTP_USER_AGENT:-}" | base64 -w0)" "${actor:+$'\t'$actor}" \
  >> "$CONTESTSDIR/$contest/var/access.log" 2>/dev/null || true
# Contest (≠ treino): a resposta leva o kit da submissão OFFLINE do moj-comp — hora do
# servidor (a CLI mede o desvio do relógio local), a chave PÚBLICA do contest e um beacon
# de tempo assinado (piso do carimbo offline). Ver lib/contest-offline.sh e docs/API.md.
# Falha de openssl degrada p/ a resposta clássica (offline indisponível, login normal).
if [[ "$contest" != treino ]]; then
  source "$_LIBDIR/contest-offline.sh"
  _opub=""; _obeacon=""
  _opubf="$(offline_ensure_keys "$contest" 2>/dev/null)" && _opub="$(cat "$_opubf" 2>/dev/null)"
  [[ -n "$_opub" ]] && _obeacon="$(SESSION_LOGIN="$u" offline_beacon "$contest" "$u" 2>/dev/null)"
  if [[ -n "$_opub" && -n "$_obeacon" ]]; then
    ok_json '{token:$t, logged_in:true, username:$u, name:$n, contest:$c,
              server_utc:$st, offline_pubkey_pem:$pk, beacon:$b}
             + (if $ac == "" then {} else {actor:$ac, is_team:true} end)' \
      --arg t "$tok" --arg u "$u" --arg n "$name" --arg c "$contest" --arg ac "$actor" \
      --argjson st "$EPOCHSECONDS" --arg pk "$_opub" --arg b "$_obeacon"
    exit 0
  fi
fi
# `actor` só aparece em sessão de TIME: o cliente mostra "fulano · competindo por <time>"
ok_json '{token:$t, logged_in:true, username:$u, name:$n, contest:$c, server_utc:$st}
         + (if $ac == "" then {} else {actor:$ac, is_team:true} end)' \
  --arg t "$tok" --arg u "$u" --arg n "$name" --arg c "$contest" --arg ac "$actor" \
  --argjson st "$EPOCHSECONDS"
