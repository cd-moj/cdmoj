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
  { is_staff || is_cstaff; } && return 1     # .staff/.cstaff: nunca
  [[ "$(contest_phase "$1")" != before ]]   # demais: só após o início
}

# can_submit <contest> : 0 se o usuário logado pode submeter AGORA.
can_submit() {
  is_judge && return 0                       # .admin/.judge: sempre
  { is_staff || is_cstaff; } && return 1     # .staff/.cstaff: nunca
  [[ "$(contest_phase "$1")" == running ]]   # normal/.mon: só durante a janela
}
