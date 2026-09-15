# lib/contest-gate.sh — controle de acesso por FASE do contest + papel.
# Sourced pelos handlers de problemas/submissão (router já carregou auth.sh, então
# is_judge/is_staff/is_mon e SESSION_LOGIN estão disponíveis).
#
# Regra (forçada pela API; o frontend só espelha):
#   .admin/.judge  -> veem problemas e SUBMETEM a qualquer momento (antes/durante/depois).
#   .staff/.cstaff -> NUNCA veem problemas nem submetem (staff opera a impressão;
#                     cstaff = chefe de sede, só observa/credencia).
#   .mon           -> submetem só DURANTE a janela (como o normal), mas ficam FORA do placar
#                     (sc_is_real_user já descarta *.mon das estatísticas/placar).
#   usuário normal -> só vê os problemas DEPOIS do início; só submete DURANTE a janela.

# time_override_end <contest> <login> -> ecoa o `end` (epoch) da 1ª regra de
# contests/<c>/time-overrides.json cujo regex casa com o login; vazio se nenhuma.
# Prorrogação de vigência POR SEDE/GRUPO (ex.: queda de energia numa sede — só aqueles
# times ganham minutos). Formato: [{regex, end, reason?}, …] — 1ª que casa vence.
# ATENÇÃO jq: `.regex` PRECISA ser bindado ANTES do test ($l|test(.regex) leria .regex
# de $l — ver a armadilha de contexto de args do jq); try/catch protege de regex inválido.
time_override_end() {
  local f="$CONTESTSDIR/$1/time-overrides.json"
  [[ -s "$f" && -n "${2:-}" ]] || return 0
  jq -r --arg l "$2" '
    first(.[]? | (.regex // "") as $rr | (.end) as $e
          | select($rr != "" and ($e|type=="number") and (try ($l | test($rr)) catch false))
          | $e) // empty' "$f" 2>/dev/null
}

# contest_end_effective <contest> <login> -> fim EFETIVO (epoch; 0 = sem limite):
# CONTEST_END do conf, PRORROGADO pela regra do time-overrides.json que casar (o override
# só ESTENDE — nunca encurta — e só vale quando há um fim definido no conf).
contest_end_effective() {
  local CONTEST_START=0 CONTEST_END=0 oend
  source "$CONTESTSDIR/$1/conf" 2>/dev/null
  [[ "$CONTEST_END" =~ ^[0-9]+$ ]] || CONTEST_END=0
  oend="$(time_override_end "$1" "${2:-}")"
  [[ "$oend" =~ ^[0-9]+$ ]] && (( CONTEST_END > 0 && oend > CONTEST_END )) && CONTEST_END=$oend
  printf '%s' "$CONTEST_END"
}

# contest_end_all <contest> -> fim p/ TODO MUNDO (epoch; 0 = sem fim definido): CONTEST_END
# do conf estendido pelo MAIOR `end` válido de time-overrides.json. É o gate da CERIMÔNIA
# de revelação por sede (.cstaff): sede prorrogada segura a revelação de todas até a
# prorrogação acabar. Conservador de propósito: uma regra cujo regex não casa ninguém
# ainda estende o fim-para-todos (preferível a vazar resultado com gente competindo).
# Espelha contest_end_effective: o override só ESTENDE, e só quando há fim no conf.
contest_end_all() {
  local CONTEST_START=0 CONTEST_END=0 mx f="$CONTESTSDIR/$1/time-overrides.json"
  source "$CONTESTSDIR/$1/conf" 2>/dev/null
  [[ "$CONTEST_END" =~ ^[0-9]+$ ]] || CONTEST_END=0
  if [[ -s "$f" ]] && (( CONTEST_END > 0 )); then
    mx="$(jq -r '[.[]? | select((.regex//"") != "" and (.end|type=="number")) | .end] | max // empty' "$f" 2>/dev/null)"
    [[ "$mx" =~ ^[0-9]+$ ]] && (( mx > CONTEST_END )) && CONTEST_END=$mx
  fi
  printf '%s' "$CONTEST_END"
}

# contest_over_for_all <contest> : 0 se o contest TERMINOU para todas as sedes/grupos.
# Sem fim definido (CONTEST_END=0) nunca termina — cerimônia indisponível.
contest_over_for_all() {
  local e; e="$(contest_end_all "$1")"
  [[ "$e" =~ ^[0-9]+$ ]] && (( e > 0 && EPOCHSECONDS > e ))
}

# --- DESCONGELAR o placar: só a partir do fim geral + 1 min (pedido do Ribas, 2026-09-14) ---
# "Destravar" o freeze = FREEZE_TIME passar de >0 para 0/apagado. Quatro caminhos fazem isso
# (Encerrar evento, promoção de rodada, "Descongelar tudo" da cerimônia, edição do freeze na
# Central/Regras/config) e a regra vale p/ TODOS: nunca antes de contest_end_all + 60 s — o
# último segundo de prova (inclusive de sede prorrogada) ainda aceita submissão, e o placar
# congelado é o que protege a cerimônia. Mudar o freeze para OUTRO valor >0 segue livre.
FREEZE_RELEASE_GRACE="${FREEZE_RELEASE_GRACE:-60}"
# freeze_release_at <contest> -> epoch a partir do qual pode descongelar (0 = sem fim definido)
freeze_release_at() {
  local e; e="$(contest_end_all "$1")"
  [[ "$e" =~ ^[0-9]+$ ]] && (( e > 0 )) || { printf 0; return 0; }
  printf '%s' $(( e + FREEZE_RELEASE_GRACE ))
}
# freeze_release_ok <contest> : 0 se já pode descongelar
freeze_release_ok() {
  local at; at="$(freeze_release_at "$1")"
  (( at == 0 || EPOCHSECONDS >= at ))
}
# freeze_release_guard <contest> — p/ handlers: se há freeze em vigor e ainda não é hora,
# 409 freeze_locked (mensagem com a hora local do contest). Sem freeze em vigor: passa.
freeze_release_guard() {
  local cur; cur="$(conf_value "$1" FREEZE_TIME)"; cur="${cur//[^0-9]/}"
  [[ -n "$cur" ]] && (( cur > 0 )) || return 0
  freeze_release_ok "$1" && return 0
  fail 409 "O placar só pode ser descongelado a partir de $(fmt_epoch "$(freeze_release_at "$1")" '%d/%m %H:%M' "$1") (fim da prova para todas as sedes + 1 min)" "freeze_locked"
}

# freeze_change_guard <contest> <novo-FREEZE_TIME> — p/ handlers que EDITAM o freeze: barra
# (409 freeze_locked) toda mudança que DESCONGELA antes da hora — novo = 0 (apagar) ou, com o
# freeze JÁ EM VIGOR (0 < atual <= agora), novo no futuro/no fim (o placar voltaria a mostrar o
# que estava escondido). Mover o freeze ANTES de ele entrar em vigor segue livre. Comparação
# numérica ("00" é zero). Sem freeze no conf: passa.
freeze_change_guard() {
  local cur new="${2:-0}"; cur="$(conf_value "$1" FREEZE_TIME)"; cur="${cur//[^0-9]/}"; new="${new//[^0-9]/}"
  [[ -n "$cur" ]] && (( cur > 0 )) || return 0
  [[ -n "$new" ]] || new=0
  (( new == 0 )) && { freeze_release_guard "$1"; return 0; }
  (( cur <= EPOCHSECONDS && new > EPOCHSECONDS )) || return 0     # não descongela: livre
  freeze_release_ok "$1" && return 0
  fail 409 "O placar está congelado e só pode ser descongelado a partir de $(fmt_epoch "$(freeze_release_at "$1")" '%d/%m %H:%M' "$1") (fim da prova para todas as sedes + 1 min) — mover o freeze para depois de agora o descongelaria" "freeze_locked"
}

# contest_phase <contest> -> ecoa: before | running | ended  (compara EPOCH com START e o
# fim EFETIVO do login da sessão — prorrogação por sede vale aqui, e portanto no /submit;
# START/END==0 = sem limite naquele extremo). Roda em subshell ao ser capturado, então o
# `source` do conf não vaza variáveis para o chamador.
contest_phase() {
  local CONTEST_START=0 CONTEST_END=0 now="$EPOCHSECONDS"
  source "$CONTESTSDIR/$1/conf" 2>/dev/null
  [[ "$CONTEST_START" =~ ^[0-9]+$ ]] || CONTEST_START=0
  CONTEST_END="$(contest_end_effective "$1" "${SESSION_LOGIN:-}")"
  if   (( CONTEST_START > 0 && now <  CONTEST_START )); then printf before
  elif (( CONTEST_END   > 0 && now >  CONTEST_END   )); then printf ended
  else printf running; fi
}

# can_see_problems <contest> : 0 se o usuário logado pode ver os enunciados AGORA.
can_see_problems() {
  is_judge && return 0                       # .admin/.judge: sempre
  { is_staff || is_cstaff || is_animeitor; } && return 1   # staff/sede/telão: nunca
  [[ "$(contest_phase "$1")" != before ]]   # demais: só após o início
}

# can_submit <contest> : 0 se o usuário logado pode submeter AGORA.
can_submit() {
  is_judge && return 0                       # .admin/.judge: sempre
  { is_staff || is_cstaff || is_animeitor; } && return 1   # staff/sede/telão: nunca
  [[ "$(contest_phase "$1")" == running ]]   # normal/.mon: só durante a janela
}
