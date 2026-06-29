# lib/contest-gate.sh — controle de acesso por FASE do contest + papel.
# Sourced pelos handlers de problemas/submissão (router já carregou auth.sh, então
# is_judge/is_staff/is_mon e SESSION_LOGIN estão disponíveis).
#
# Regra (forçada pela API; o frontend só espelha):
#   .admin/.judge  -> veem problemas e SUBMETEM a qualquer momento (antes/durante/depois).
#   .staff         -> NUNCA veem problemas nem submetem (operam só a impressão).
#   .mon           -> veem o placar/submissões, mas NÃO submetem (observador).
#   usuário normal -> só vê os problemas DEPOIS do início; só submete DURANTE a janela.

# contest_phase <contest> -> ecoa: before | running | ended  (compara EPOCH com START/END
# do conf; START/END==0 = sem limite naquele extremo). Roda em subshell ao ser capturado,
# então o `source` do conf não vaza variáveis para o chamador.
contest_phase() {
  local CONTEST_START=0 CONTEST_END=0 now="$EPOCHSECONDS"
  source "$CONTESTSDIR/$1/conf" 2>/dev/null
  [[ "$CONTEST_START" =~ ^[0-9]+$ ]] || CONTEST_START=0
  [[ "$CONTEST_END"   =~ ^[0-9]+$ ]] || CONTEST_END=0
  if   (( CONTEST_START > 0 && now <  CONTEST_START )); then printf before
  elif (( CONTEST_END   > 0 && now >  CONTEST_END   )); then printf ended
  else printf running; fi
}

# can_see_problems <contest> : 0 se o usuário logado pode ver os enunciados AGORA.
can_see_problems() {
  is_judge && return 0           # .admin/.judge: sempre
  is_staff && return 1           # .staff: nunca
  [[ "$(contest_phase "$1")" != before ]]   # demais: só após o início
}

# can_submit <contest> : 0 se o usuário logado pode submeter AGORA.
can_submit() {
  is_judge && return 0                       # .admin/.judge: sempre
  { is_staff || is_mon; } && return 1        # .staff/.mon: nunca
  [[ "$(contest_phase "$1")" == running ]]   # normal: só durante a janela
}
