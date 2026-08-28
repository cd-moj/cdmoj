#!/bin/bash
# molde.sh — worker bash PERSISTENTE da API (o "molde"): sourceia as libs UMA vez e atende
# requisições em loop, cada uma num subshell `( . router.sh )`. É o lado bash do par com o
# moj-molde-shim (server/molde/moj-molde-shim.c), que fala FastCGI com o nginx e conversa
# conosco por um protocolo mínimo:
#
#   stdin  (fd0)  ← controle: por requisição, N records "CHAVE=VALOR\0" + um record vazio
#                   ("\0") que despacha. EOF = shim morreu ⇒ saímos.
#   stdout (fd1)  → status: "done <rc>\0" ao fim de cada requisição. NUNCA leva corpo.
#   $MOLDE_WDIR/body     ← corpo da requisição (arquivo: EOF garantido p/ o `cat -` do
#                          read_body; corpo de 1 GB não passa pela RAM do shell).
#   $MOLDE_WDIR/resp.out → resposta CGI COMPLETA (Status:/headers/corpo), escrita pelo
#                          subshell; o shim a streama pro nginx após o "done".
#
# POR QUE SUBSHELL (não negociável — apurado em 28/08/2026): `fail` dá exit; 40+ handlers
# armam `trap ... EXIT`; 15+ abrem `exec 9>lock` sem fechar (flock solta no fim do subshell);
# 2 pontos fazem `set +o noglob` sem restaurar. Tudo isso só é inofensivo porque o subshell
# MORRE ao fim da requisição — o pai fica pristine para sempre.
#
# Higiene de vida longa: stderr do worker vai para ARQUIVO (o shim redireciona; pipe de
# stderr cheio já travou worker de fcgiwrap — outage documentado no CLAUDE.md); reciclamos
# a cada MOLDE_MAX_REQS requisições (saída limpa; o shim respawna em ~5 ms); variáveis de
# requisição só existem dentro do subshell (env do pai nunca é tocado).
set -u
if [[ "${BASH_SOURCE[0]}" == /* ]]; then _DIR="${BASH_SOURCE[0]%/*}"
else _DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi
cd "$_DIR"
source "$_DIR/lib/sources.sh"
MOJ_LIBS_LOADED=1
: "${MOLDE_WDIR:?molde.sh precisa de MOLDE_WDIR}"
: "${MOLDE_MAX_REQS:=500}"
_n=0

# As 15 variáveis do contrato CGI (as mesmas do fastcgi_param do nginx). Records de chave
# fora desta lista são IGNORADOS (o shim é quem manda, mas defesa em profundidade: o corpo
# de controle nunca vira export arbitrário no ambiente).
declare -A _CGI_OK=([SCRIPT_FILENAME]=1 [PATH_INFO]=1 [REQUEST_METHOD]=1 [QUERY_STRING]=1
  [CONTENT_TYPE]=1 [CONTENT_LENGTH]=1 [HTTP_AUTHORIZATION]=1 [HTTP_USER_AGENT]=1
  [HTTP_X_FORWARDED_FOR]=1 [HTTP_X_REAL_IP]=1 [REMOTE_ADDR]=1 [SERVER_PROTOCOL]=1
  [GATEWAY_INTERFACE]=1 [CONTEST_HOST]=1 [HTTP_ACCEPT_ENCODING]=1)

while :; do
  # --- lê uma requisição do canal de controle ------------------------------
  declare -A _E=()
  _got=0
  while IFS= read -r -d '' _kv; do
    [[ -z "$_kv" ]] && { _got=1; break; }
    _k="${_kv%%=*}"
    [[ -n "${_CGI_OK[$_k]:-}" ]] && _E[$_k]="${_kv#*=}"
  done
  (( _got )) || exit 0                     # EOF no meio = shim morreu; morremos juntos
  # --- roda a requisição num subshell --------------------------------------
  (
    for _k in "${!_E[@]}"; do export "$_k=${_E[$_k]}"; done
    # chave ausente na requisição NÃO pode herdar valor de fora (CONTEST_HOST do subdomínio
    # anterior viraria 403 espúrio; HTTP_AUTHORIZATION alheio seria vazamento de sessão) —
    # o shim sempre manda as 15, mas o unset é a rede: o que não veio, não existe.
    for _k in "${!_CGI_OK[@]}"; do [[ -n "${_E[$_k]+x}" ]] || unset "$_k"; done
    builtin cd "$_DIR"                     # requisição anterior pode ter feito cd (subshell…
    source "$_DIR/router.sh"               # …morre, mas o nosso pwd é restaurado por via das dúvidas)
  ) < "$MOLDE_WDIR/body" > "$MOLDE_WDIR/resp.out" 2>> "$MOLDE_WDIR/stderr.log"
  _rc=$?
  printf 'done %d\0' "$_rc"
  unset _E
  (( ++_n >= MOLDE_MAX_REQS )) && exit 0   # reciclagem: saída LIMPA entre requisições
done
