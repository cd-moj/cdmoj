# lib/worker-auth.sh — autenticação de WORKER (juiz) na API.
#
# Os juízes NÃO usam sessão de usuário; eles mandam um token COMPARTILHADO com
# prefixo `mojw_` no header `Authorization: Bearer mojw_<segredo>`. O prefixo
# evita qualquer colisão com tokens de sessão de usuário (lib/auth.sh / $SESSIONDIR).
# O segredo fica em $WORKER_TOKEN_FILE (espelhado de judge/etc/worker.token no NFS,
# modo 600). Reaproveita _bearer_token() de lib/auth.sh.

: "${RUNDIR:=/home/ribas/moj/run}"
: "${WORKER_TOKEN_FILE:=$RUNDIR/secrets/worker.token}"

# comparação em tempo ~constante (não vaza tamanho/posição por timing).
_worker_token_eq() {  # _worker_token_eq <esperado> <recebido>
  local a="$1" b="$2" i d=0
  [[ ${#a} -eq ${#b} ]] || d=1
  local n=${#a}; (( ${#b} > n )) && n=${#b}
  for (( i=0; i<n; i++ )); do [[ "${a:i:1}" == "${b:i:1}" ]] || d=1; done
  return $d
}

# require_worker — exige Bearer mojw_<token> válido; senão responde e encerra.
require_worker() {
  local got expected
  got="$(_bearer_token 2>/dev/null)"
  [[ "$got" == mojw_* ]] || fail 401 "Worker token required" "worker_unauth"
  [[ -s "$WORKER_TOKEN_FILE" ]] || fail 503 "Worker auth not configured" "worker_noconf"
  expected="$(< "$WORKER_TOKEN_FILE")"
  _worker_token_eq "$expected" "$got" || fail 401 "Invalid worker token" "worker_badtoken"
  WORKER_HOST="$(param host 2>/dev/null)"; [[ -n "$WORKER_HOST" ]] || WORKER_HOST=""
  return 0
}
