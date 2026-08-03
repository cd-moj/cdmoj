# GET/POST /treino/contest-registration?contest=<c>   (Bearer do TREINO)
#
# INSCRIÇÃO do próprio usuário num contest que usa as contas do Treino Livre
# (USERS_FROM=treino): individual ou em TIME de até REG_TEAM_MAX contas EXISTENTES.
# Motor em lib/registration.sh; a porta do contest (janela + roster) é aplicada no
# handlers/auth/login.sh.
#
# POR QUE AQUI e não dentro do contest: o token é POR ORIGEM — `<cid>.moj…` tem outro
# localStorage e não enxerga a sessão do treino. Quem inscreve é o site principal, com a
# identidade do treino; o contest só confere o roster na hora de entrar.
#
# GET  -> {enabled, contest, contest_name, start_time, end_time, window:{state,opens_at,
#          closes_at,late_until}, team_max, teams_allowed, me:{kind,…}, team, invites[], totals}
# POST {contest, action, …}:
#   register                      — entra como INDIVIDUAL
#   cancel                        — desfaz (individual) ou sai do time
#   team-create   {name}          — cria o time e vira capitão
#   team-invite   {login}         — capitão convida uma conta do treino
#   team-accept   {team}          — convidado aceita (desfaz a inscrição individual dele)
#   team-decline  {team}          — convidado recusa
#   team-leave                    — membro sai (capitão passa a capitania; último dissolve)
#   team-dissolve                 — capitão desfaz o time
#   team-rename   {name}          — capitão troca o NOME (o login do time não muda)
require_auth_contest treino
# o contest pode vir na QUERY (?contest=) ou no CORPO — o front manda no corpo, junto da ação.
# read_body lê o stdin UMA vez: por isso ele vem antes de tudo que precisa do contest.
body=""; [[ "$REQUEST_METHOD" == POST ]] && body="$(read_body)"
contest="$(param contest)"
if [[ -z "$contest" && -n "$body" ]]; then contest="$(jq -r '.contest // empty' <<<"$body" 2>/dev/null)"; fi
[[ -n "$contest" ]] || fail 400 "Informe o contest" "contest_missing"
require_contest "$contest"
[[ "$contest" == treino ]] && fail 400 "O treino não tem inscrição" "contest_invalid"

source "$_DIR/lib/users.sh"
source "$_DIR/lib/cohorts.sh"
source "$_DIR/lib/registration.sh"

cdir="$CONTESTSDIR/$contest"
# contest SUPER SECRETO não existe para quem está de fora (nem p/ dizer "não pode")
( SECRET=""; source "$cdir/conf" 2>/dev/null; [[ "$SECRET" == 1 ]] ) \
  && fail 404 "Contest não encontrado" "contest_notfound"
# só faz sentido em contest que compartilha as contas do treino: é a conta do treino que
# está se inscrevendo
[[ "$(reg_source_of "$contest")" == treino ]] \
  || fail 409 "Este contest não usa as contas do Treino Livre" "not_shared"

me="$SESSION_LOGIN"
is_reserved_role_login "$me" && fail 403 "Conta de papel não se inscreve como competidor" "role_account"

_emit(){  # estado completo, p/ o front redesenhar com UMA chamada
  local nm st et s
  IFS=$'\x01' read -r nm st et < <( CONTEST_NAME=""; CONTEST_START=""; CONTEST_END=""
    source "$cdir/conf" 2>/dev/null
    printf '%s\x01%s\x01%s' "${CONTEST_NAME:-$contest}" "${CONTEST_START:-0}" "${CONTEST_END:-0}" )
  [[ "$st" =~ ^[0-9]+$ ]] || st=0; [[ "$et" =~ ^[0-9]+$ ]] || et=0
  # monta ANTES de responder: jq que falha depois do header vira 200 com corpo vazio (mudo)
  s="$(reg_status_json "$contest" "$me")"
  [[ -n "$s" ]] || fail 500 "Falha ao montar a inscrição" "reg_render_failed"
  ok_json '{enabled:$en, contest:$c, contest_name:$n, start_time:$st, end_time:$et} + $s' \
    --arg c "$contest" --arg n "$nm" --argjson st "$st" --argjson et "$et" \
    --argjson en "$(reg_enabled "$contest" && echo true || echo false)" \
    --argjson s "$s"
}

[[ "$REQUEST_METHOD" == POST ]] || { _emit; exit 0; }

reg_enabled "$contest" || fail 409 "Este contest não usa inscrição" "registration_off"
jq -e . >/dev/null 2>&1 <<<"$body" || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // empty' <<<"$body")"
[[ -n "$action" ]] || fail 400 "Informe a ação" "action_missing"

wstate="$(reg_window_state "$contest")"
# recusar convite não depende da janela (é só limpar a caixa de entrada); o resto sim
if [[ "$action" != team-decline ]]; then
  case "$wstate" in
    open|late) ;;
    soon)   fail 403 "As inscrições ainda não abriram" "registration_not_open" ;;
    *)      fail 403 "As inscrições estão encerradas" "registration_closed" ;;
  esac
fi

# uma trava por contest: dois membros aceitando ao mesmo tempo não podem estourar o time
mkdir -p "$cdir/var"
exec 9>"$(reg_lock_file "$contest")" || fail 500 "Falha ao obter lock" "lock_fail"
flock 9

_err(){ # <código> — mensagem amigável p/ cada recusa do motor
  case "$1" in
    already_registered) fail 409 "Você já está inscrito" "$1" ;;
    in_team|already_in_team) fail 409 "Você já está num time deste contest" "$1" ;;
    not_registered)     fail 409 "Você não está inscrito" "$1" ;;
    teams_disabled)     fail 409 "Este contest não aceita times" "$1" ;;
    bad_name)           fail 400 "Nome de time inválido (2 a 48 caracteres)" "$1" ;;
    name_taken)         fail 409 "Já existe um time com esse nome" "$1" ;;
    no_team)            fail 409 "Você não está num time" "$1" ;;
    not_captain)        fail 403 "Só o capitão do time faz isso" "$1" ;;
    team_full)          fail 409 "O time já está cheio (contando os convites pendentes)" "$1" ;;
    already_invited)    fail 409 "Essa pessoa já foi convidada" "$1" ;;
    self_invite)        fail 400 "Você já está no time" "$1" ;;
    no_invite)          fail 404 "Não há convite desse time p/ você" "$1" ;;
    slug_failed)        fail 409 "Não consegui gerar um identificador p/ esse nome" "$1" ;;
    *)                  fail 500 "Falha na inscrição (${1:-?})" "${1:-reg_failed}" ;;
  esac
}
# RUNOUT em vez de stdout: `_run … >/dev/null` engoliria também o JSON de erro do `fail`
_run(){ RUNOUT="$("$@")" || _err "$RUNOUT"; }

case "$action" in
  register)      _run reg_register_individual "$contest" "$me"
                 audit_log_to "$contest" reg-register "login=$me" ;;
  cancel)        _run reg_cancel "$contest" "$me"
                 audit_log_to "$contest" reg-cancel "login=$me" ;;
  team-create)   name="$(jq -r '.name // empty' <<<"$body")"
                 _run reg_team_create "$contest" "$me" "$name"; t="$RUNOUT"
                 audit_log_to "$contest" reg-team-create "team=$t captain=$me" ;;
  team-invite)   who="$(jq -r '.login // empty' <<<"$body")"
                 valid_id "$who" || fail 400 "Login inválido" "login_invalid"
                 user_exists treino "$who" || fail 404 "Não existe conta no Treino Livre com esse login" "user_notfound"
                 is_reserved_role_login "$who" && fail 400 "Conta de papel não entra em time" "role_account"
                 _run reg_team_invite "$contest" "$me" "$who"
                 audit_log_to "$contest" reg-team-invite "captain=$me invited=$who" ;;
  team-accept)   t="$(jq -r '.team // empty' <<<"$body")"
                 valid_id "$t" || fail 400 "Time inválido" "team_invalid"
                 _run reg_team_accept "$contest" "$me" "$t"
                 audit_log_to "$contest" reg-team-accept "team=$t login=$me" ;;
  team-decline)  t="$(jq -r '.team // empty' <<<"$body")"
                 valid_id "$t" || fail 400 "Time inválido" "team_invalid"
                 reg_team_decline "$contest" "$me" "$t" ;;
  team-leave)    _run reg_team_leave "$contest" "$me"
                 audit_log_to "$contest" reg-team-leave "login=$me" ;;
  team-dissolve) _run reg_team_dissolve "$contest" "$me"
                 audit_log_to "$contest" reg-team-dissolve "captain=$me" ;;
  team-rename)   name="$(jq -r '.name // empty' <<<"$body")"
                 _run reg_team_rename "$contest" "$me" "$name"
                 audit_log_to "$contest" reg-team-rename "captain=$me name=$name" ;;
  *)             fail 400 "Ação desconhecida" "action_invalid" ;;
esac

flock -u 9
_emit
