# lib/team-host.sh — TIME SÓ PELO ENDEREÇO DO PRÓPRIO CONTEST (16/10/2026, pedido do Ribas).
#
# Numa máquina de prova travada (o firewall do Maratona Linux filtra por NOME), o time ainda chegava ao MOJ pelo IP cru
# (https://177.70.23.195/contest/?c=OUTRO) ou pelo host base (moj.naquadah.com.br/contest/?c=OUTRO) e logava em OUTRO
# contest para pegar informação. A regra: conta de TIME (todo login que não é de papel) de um contest que não é o
# treino só LOGA e só USA o contest quando a requisição chega pelo subdomínio dele (<id>.moj.naquadah.com.br). Quem diz
# por onde a requisição chegou é o nginx: `CONTEST_HOST` = o id do subdomínio, VAZIO no host base e no IP (é o mesmo
# sinal do isolamento por subdomínio do router.sh).
#   · vale SEMPRE (TEAM_HOST_LOCK=1, etc/common.conf); 0 desliga e `observe` só registra. O arquivo
#     $RUNDIR/team-host-lock (uma palavra: 0 | observe) só AFROUXA, sem restart — é o botão de emergência;
#   · conta de papel (.admin, .judge…) e o treino ficam de fora; o logout sempre passa (router.sh);
#   · id que não pode ser subdomínio (ponto, maiúscula, >63) fica ISENTO: não há endereço p/ onde mandar o time;
#   · cada recusa vai ao admin-audit.log do contest (team-host-block), no máx. 1 linha a cada 5 min por
#     contest+login+via — o laço de um script não inunda o audit.
# ⚠ Não é fronteira dura: `curl -H 'Host: X.moj…' https://IP/` chega como subdomínio X. O que prende a MÁQUINA ao
# contest é a trava de sede por IP (lib/site-lock.sh); as duas se completam.
# O porteiro espelha a regra (DECLINA a sessão de time fora do subdomínio; o bash responde e registra).

# th_subdomainable <id> — o id pode ser um rótulo de DNS sob o certificado curinga?
th_subdomainable(){ [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,62}$ ]]; }

# contest_public_url <id> — o endereço que o time tem de usar: https://<id>.<host do MOJ_PUBLIC_BASE>/contest/
# (id que não pode ser subdomínio: o endereço clássico no host base).
contest_public_url(){
  local id="$1" base="${MOJ_PUBLIC_BASE%/}" scheme rest hp
  scheme="${base%%://*}"; rest="${base#*://}"; hp="${rest%%/*}"
  if th_subdomainable "$id"; then printf '%s://%s.%s/contest/' "$scheme" "$id" "$hp"
  else printf '%s/contest/?c=%s' "$base" "$id"; fi
}

# th_mode_to <var> — 0 | observe | 1. O env manda; o arquivo de override só afrouxa (env 0 é desligado de vez, o que
# mantém os testes herméticos).
th_mode_to(){
  local -n _thm="$1"; local f=""
  case "${TEAM_HOST_LOCK:-1}" in 0|off|n|no|false) _thm=0; return 0;; observe) _thm=observe;; *) _thm=1;; esac
  [[ -f "$RUNDIR/team-host-lock" ]] && read -r f < "$RUNDIR/team-host-lock" 2>/dev/null
  case "$f" in 0|off) _thm=0;; observe) _thm=observe;; esac
  return 0
}

# _sess_peek <arquivo> <var_contest> <var_login> [var_actor] — lê a sessão SEM processo novo (source numa função, com
# os campos LOCAIS: nada vaza p/ quem chamou; o %q sai como no load_session). Campo novo de sessão = local aqui também.
_sess_peek(){
  local -n _spc="$2" _spl="$3"
  local CONTEST="" LOGIN="" USERFULLNAME="" LOGINAT="" ACTOR="" IP="" UA_B64="" MKEY=""
  source "$1" 2>/dev/null
  _spc="$CONTEST"; _spl="$LOGIN"
  if [[ -n "${4:-}" ]]; then local -n _spa="$4"; _spa="$ACTOR"; fi
  return 0
}

# th_record <contest> <login> <via> [ator] [modo] — a trilha da recusa (ou da observação), com teto.
th_record(){
  local c="$1" l="$2" via="$3" a="${4:-}" m="${5:-1}" d f last="" act=team-host-block host ipf
  d="$RUNDIR/team-host"; [[ -d "$d" ]] || mkdir -p "$d" 2>/dev/null
  f="$d/${c}_${l//[^A-Za-z0-9._@#+-]/_}_$via"
  [[ -f "$f" ]] && read -r last < "$f" 2>/dev/null
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  (( EPOCHSECONDS - last >= 300 )) || return 0
  printf '%s' "$EPOCHSECONDS" > "$f" 2>/dev/null
  [[ "$m" == observe ]] && act=team-host-observe
  host="${HTTP_HOST:-}"; host="${host//[^A-Za-z0-9.:_-]/}"
  ipf="${REMOTE_ADDR:-}"; ipf="${ipf//[^0-9a-fA-F.:]/}"
  SESSION_LOGIN="$l" audit_log_to "$c" "$act" \
    "via=$via host=${host:--} ip=${ipf:--} route=${PATH_INFO:--} login=$l${a:+ actor=$a}"
  return 0
}

# th_refuse <contest> <login> <via> [ator] — registra e, valendo a regra, responde 403 host_required (com a URL certa
# na mensagem também: CLI antiga só mostra error.message).
th_refuse(){
  local c="$1" l="$2" via="$3" a="${4:-}" m="" url
  th_mode_to m
  [[ "$m" == 0 ]] && return 0
  th_record "$c" "$l" "$via" "$a" "$m"
  [[ "$m" == observe ]] && return 0
  url="$(contest_public_url "$c")"
  FAIL_EXTRA="$(jq -cn --arg u "$url" --arg c "$c" '{url:$u, contest:$c}')" \
    fail 403 "Os times deste contest só entram pelo endereço dele: $url" "host_required"
}

# th_guard — POR REQUISIÇÃO (router.sh). Zero processo no caminho feliz: o token sai do cabeçalho por nameref e a
# sessão é lida por `source` numa função. Só o caminho da recusa paga processo.
th_guard(){
  case "${TEAM_HOST_LOCK:-1}" in 0|off|n|no|false) return 0;; esac
  local tok="" c="" l="" a=""
  _bearer_token_to tok
  [[ -n "$tok" ]] && valid_id "$tok" && [[ -f "$SESSIONDIR/$tok" ]] || return 0
  _sess_peek "$SESSIONDIR/$tok" c l a
  [[ -n "$c" && -n "$l" && "$c" != treino && "${CONTEST_HOST:-}" != "$c" ]] || return 0
  is_reserved_role_login "$l" && return 0
  th_subdomainable "$c" && [[ -f "$CONTESTSDIR/$c/conf" ]] || return 0   # contest apagado: o 401 é do handler
  _session_account_alive "$c" "$l" || return 0                            # sessão morta: o 401 de sempre
  th_refuse "$c" "$l" session "$a"
}

# th_login_check <contest> <login-do-time> [ator] — a porta do /auth/login (depois da senha e do alias de time).
th_login_check(){
  local c="$1" u="$2" a="${3:-}"
  case "${TEAM_HOST_LOCK:-1}" in 0|off|n|no|false) return 0;; esac
  [[ "$c" != treino && "${CONTEST_HOST:-}" != "$c" ]] || return 0
  is_reserved_role_login "$u" && return 0
  th_subdomainable "$c" || return 0
  th_refuse "$c" "$u" login "$a"
}
