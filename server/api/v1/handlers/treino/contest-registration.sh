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
#   register      {univ?, ai?, flag?} — entra como INDIVIDUAL (a meta pode vir junto)
#   individual-meta {univ?, ai?, flag?} — inscrito individual declara/edita universidade
#                                    ("[UNIV] Nome" no placar), uso de IA e bandeira —
#                                    paridade com o team-meta do capitão
#   cancel                        — desfaz (individual) ou sai do time
#   team-create   {name}          — cria o time e vira capitão
#   team-invite   {login}         — capitão convida uma conta do treino
#   team-accept   {team}          — convidado aceita (desfaz a inscrição individual dele)
#   team-decline  {team}          — convidado recusa
#   team-leave                    — membro sai (capitão passa a capitania; último dissolve)
#   team-dissolve                 — capitão desfaz o time
#   team-rename   {name}          — capitão troca o NOME (o login do time não muda)
#   team-meta     {univ?, ai?, flag?} — capitão declara universidade (o placar exibe
#                                    "[UNIV] Nome" + coluna de escola), uso de IA (yes|no|"")
#                                    e a BANDEIRA (país ISO-2 ou estado "br-xx")
#   team-photo    {image_b64}      — capitão sobe a foto do time (aparece no placar; máx ~4MB,
#                                    redimensionada e sem metadados)
#
# MODO DE PARTICIPAÇÃO É DEFINITIVO: depois de inscrito (individual OU time), o competidor não
# cancela nem troca de modo pela API pública (403 mode_locked) — mudança é com a ORGANIZAÇÃO
# (painel Pessoas › Inscrições). Evita o vaivém individual↔time na véspera e o buraco
# cancelar+reinscrever. As funções da lib seguem permissivas: o admin usa as mesmas.
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
    mode_locked)        fail 403 "Sua forma de participação já está definida — para mudar (ou sair), fale com a organização" "mode_locked" ;;
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
    flag_invalid)       fail 400 "Bandeira inválida — use o código do país (ex.: br, ar) ou do estado (ex.: br-sc)" "$1" ;;
    *)                  fail 500 "Falha na inscrição (${1:-?})" "${1:-reg_failed}" ;;
  esac
}
# RUNOUT em vez de stdout: `_run … >/dev/null` engoliria também o JSON de erro do `fail`
_run(){ RUNOUT="$("$@")" || _err "$RUNOUT"; }

case "$action" in
  register)      # univ/IA/bandeira podem vir junto (o form manda tudo de uma vez, como no
                 # time) — a flag é validada ANTES de inscrever (400 depois da mutação
                 # deixaria a pessoa inscrita e o retry daria already_registered)
                 u="$(jq -r '.univ // ""' <<<"$body")"; a="$(jq -r '.ai // ""' <<<"$body")"
                 fl="$(jq -r '.flag // ""' <<<"$body")"
                 case "$a" in yes|no|"") ;; *) a="";; esac
                 flchk="${fl,,}"; flchk="${flchk//_/-}"
                 [[ -z "$flchk" || "$flchk" =~ ^[a-z]{2}(-[a-z]{2})?$ ]] || _err flag_invalid
                 _run reg_register_individual "$contest" "$me"
                 [[ -n "$u$a$fl" ]] && reg_individual_meta "$contest" "$me" "$u" "$a" "$fl" >/dev/null
                 audit_log_to "$contest" reg-register "login=$me univ=$u ai=$a flag=$fl" ;;
  individual-meta)
                 u="$(jq -r '.univ // ""' <<<"$body")"; a="$(jq -r '.ai // ""' <<<"$body")"
                 fl="$(jq -r '.flag // ""' <<<"$body")"
                 case "$a" in yes|no|"") ;; *) fail 400 "ai deve ser yes|no" "ai_invalid";; esac
                 _run reg_individual_meta "$contest" "$me" "$u" "$a" "$fl"
                 audit_log_to "$contest" reg-individual-meta "login=$me univ=$u ai=$a flag=$fl" ;;
  cancel)        reg_is_registered "$contest" "$me" && _err mode_locked
                 _run reg_cancel "$contest" "$me"
                 audit_log_to "$contest" reg-cancel "login=$me" ;;
  team-create)   [[ "$(reg_kind_of "$contest" "$me")" == individual ]] && _err mode_locked
                 name="$(jq -r '.name // empty' <<<"$body")"
                 _run reg_team_create "$contest" "$me" "$name"; t="$RUNOUT"
                 # univ/IA podem vir junto da criação (o form manda tudo de uma vez)
                 u="$(jq -r '.univ // ""' <<<"$body")"; a="$(jq -r '.ai // ""' <<<"$body")"
                 fl="$(jq -r '.flag // ""' <<<"$body")"
                 case "$a" in yes|no|"") ;; *) a="";; esac
                 [[ -n "$u$a$fl" ]] && reg_team_meta "$contest" "$me" "$u" "$a" "$fl" >/dev/null
                 audit_log_to "$contest" reg-team-create "team=$t captain=$me univ=$u ai=$a flag=$fl" ;;
  team-invite)   who="$(jq -r '.login // empty' <<<"$body")"
                 valid_id "$who" || fail 400 "Login inválido" "login_invalid"
                 user_exists treino "$who" || fail 404 "Não existe conta no Treino Livre com esse login" "user_notfound"
                 is_reserved_role_login "$who" && fail 400 "Conta de papel não entra em time" "role_account"
                 _run reg_team_invite "$contest" "$me" "$who"
                 audit_log_to "$contest" reg-team-invite "captain=$me invited=$who" ;;
  team-accept)   [[ "$(reg_kind_of "$contest" "$me")" == individual ]] && _err mode_locked
                 t="$(jq -r '.team // empty' <<<"$body")"
                 valid_id "$t" || fail 400 "Time inválido" "team_invalid"
                 _run reg_team_accept "$contest" "$me" "$t"
                 audit_log_to "$contest" reg-team-accept "team=$t login=$me" ;;
  team-decline)  t="$(jq -r '.team // empty' <<<"$body")"
                 valid_id "$t" || fail 400 "Time inválido" "team_invalid"
                 reg_team_decline "$contest" "$me" "$t" ;;
  team-leave|team-dissolve)
                 _err mode_locked ;;   # sair/desfazer = mudar o modo; só a organização (admin)
  team-rename)   name="$(jq -r '.name // empty' <<<"$body")"
                 _run reg_team_rename "$contest" "$me" "$name"
                 audit_log_to "$contest" reg-team-rename "captain=$me name=$name" ;;
  team-meta)     u="$(jq -r '.univ // ""' <<<"$body")"; a="$(jq -r '.ai // ""' <<<"$body")"
                 fl="$(jq -r '.flag // ""' <<<"$body")"
                 case "$a" in yes|no|"") ;; *) fail 400 "ai deve ser yes|no" "ai_invalid";; esac
                 _run reg_team_meta "$contest" "$me" "$u" "$a" "$fl"
                 audit_log_to "$contest" reg-team-meta "captain=$me univ=$u ai=$a flag=$fl" ;;
  team-photo)    t="$(reg_team_of "$contest" "$me")"
                 [[ -n "$t" ]] || fail 409 "Você não está num time" "no_team"
                 reg_get "$contest" | jq -e --arg t "$t" --arg l "$me" '.teams[$t].captain == $l' >/dev/null 2>&1 \
                   || fail 403 "Só o capitão do time envia a foto" "not_captain"
                 img="$(jq -r '.image_b64 // empty' <<<"$body")"
                 [[ -n "$img" ]] || fail 400 "Imagem ausente" "img_missing"
                 img="${img#data:*;base64,}"
                 (( ${#img} <= 5500000 )) || fail 413 "Imagem muito grande (máx ~4MB)" "img_large"
                 out="$CONTESTSDIR/$contest/users/$t/photo.png"
                 mkdir -p "$(dirname "$out")"
                 tmpimg="$(mktemp)"
                 printf '%s' "$img" | base64 -d > "$tmpimg" 2>/dev/null \
                   || { rm -f "$tmpimg"; fail 400 "Base64 inválido" "img_b64"; }
                 # mesma disciplina da foto de perfil: reprocessa (mata payload não-imagem),
                 # tira metadados; aqui SEM crop quadrado (é foto de equipe), só teto 900px
                 if convert "$tmpimg" -auto-orient -strip -resize "900x900>" "png:$out.tmp" 2>/dev/null; then
                   mv -f "$out.tmp" "$out"; rm -f "$tmpimg"; _score_dirty "$contest"
                 else rm -f "$tmpimg" "$out.tmp"; fail 400 "Não foi possível processar a imagem" "img_bad"; fi
                 audit_log_to "$contest" reg-team-photo "team=$t by=$me" ;;
  *)             fail 400 "Ação desconhecida" "action_invalid" ;;
esac

flock -u 9
_emit
