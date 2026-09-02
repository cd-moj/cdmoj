#!/bin/bash
# MOJ API v1 — front controller único (rodado via fcgiwrap atrás do nginx).
# Despacha PATH_INFO -> handlers/<segmentos>.sh. Handlers são "sourced" (rodam
# no mesmo shell, com lib/* e PARAMS já carregados) e usam $REQUEST_METHOD.
#
# Teste local (sem nginx):
#   PATH_INFO=/treino/problem QUERY_STRING='id=moj-problems#olamundo' \
#   REQUEST_METHOD=GET bash router.sh

# caminho absoluto (é sempre o caso sob nginx/fcgiwrap: SCRIPT_FILENAME é absoluto) resolve
# por expansão do bash — o readlink+dirname+subshell custava 3 processos em TODA requisição.
# O caminho antigo fica de reserva p/ invocação relativa (testes, linha de comando).
if [[ "${BASH_SOURCE[0]}" == /* && "${BASH_SOURCE[0]}" != *"/./"* && "${BASH_SOURCE[0]}" != *"/../"* ]]; then
  _DIR="${BASH_SOURCE[0]%/*}"
else
  _DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
fi
# Guarda de idempotência (molde): no worker persistente as libs já foram sourceadas UMA vez
# pelo pai (molde.sh seta MOJ_LIBS_LOADED) e cada requisição roda `( . router.sh )` num
# subshell — re-sourcear aqui jogaria fora o ganho (~5 ms). No caminho clássico (fcgiwrap,
# standalone, o setsid de contest/problems.sh) a variável não existe e nada muda.
if [[ -z "${MOJ_LIBS_LOADED:-}" ]]; then
  source "$_DIR/lib/sources.sh"      # a lista única do prelúdio (compartilhada com molde.sh)
  MOJ_LIBS_LOADED=1
fi
# POR REQUISIÇÃO (não pode ficar atrás da guarda): o params.sh parseia no load; no molde o
# load aconteceu com QUERY_STRING vazio. Idempotente no caminho clássico (mesmo QUERY_STRING).
PARAMS=(); _parse_query "${QUERY_STRING:-}"

HANDLERS="$_DIR/handlers"
REQUEST_METHOD="${REQUEST_METHOD:-GET}"
PATH_INFO="${PATH_INFO:-/}"

# CORS / preflight (mesma origem em produção; útil em dev)
if [[ "$REQUEST_METHOD" == OPTIONS ]]; then
  printf 'Status: 204 No Content\r\n'
  printf 'Access-Control-Allow-Origin: *\r\n'
  printf 'Access-Control-Allow-Headers: Authorization, Content-Type\r\n'
  printf 'Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n\r\n'
  exit 0
fi

route="${PATH_INFO#/}"; route="${route%/}"
if [[ -z "$route" ]]; then ok_json '{name:"MOJ API", version:"v1"}'; exit 0; fi

# sanitiza cada segmento (sem traversal); monta caminho do handler
IFS='/' read -r -a _seg <<< "$route"
_safe=""
for s in "${_seg[@]}"; do
  [[ "$s" =~ ^[A-Za-z0-9_-]+$ ]] || fail 404 "No such route" "route_invalid"
  _safe="$_safe/$s"
done

# Isolamento por subdomínio: se a requisição chegou por <ID>.moj... o nginx injeta
# CONTEST_HOST (não vem do cliente). Nesse modo só rotas DAQUELE contest são acessíveis
# — nada de treino, índice, admin global ou outro contest. Defesa em profundidade
# (o frontend também redireciona), para o cenário "máquina de prova travada no contest".
if [[ -n "${CONTEST_HOST:-}" ]] && valid_id "$CONTEST_HOST"; then
  case "${_seg[0]}" in
    auth|contest|submit|submission) ;;   # rotas pertinentes ao contest
    *) fail 403 "Recurso fora do contest '$CONTEST_HOST' (ambiente isolado)" "contest_isolated" ;;
  esac
  _qc="${PARAMS[contest]:-}"
  [[ -z "$_qc" || "$_qc" == "$CONTEST_HOST" ]] || fail 403 "Acesso a outro contest bloqueado" "contest_mismatch"
fi

# TRAVA DE SEDE POR IP (lib/site-lock.sh): a máquina de prova só enxerga o IP do MOJ, mas
# `curl --resolve` chega ao site base pelo mesmo IP — o subdomínio o cliente escolhe. Se o
# IP de origem foi reivindicado por um contest com SITE_LOCK (login de competidor de lá),
# qualquer pedido a OUTRO alvo leva 403 site_locked, exceto sessão de conta de PAPEL e o
# logout. Custa um [[ -f ]] p/ IP não preso; auditado (com teto) quando bloqueia.
_slip="$(client_ip)"
if [[ -n "$_slip" && -f "$(sl_file "$_slip")" ]]; then
  _sltgt="${CONTEST_HOST:-${PARAMS[contest]:-}}"
  _slby="$(sl_check "$_slip" "$_sltgt")"
  if [[ -n "$_slby" && "${_seg[0]}/${_seg[1]:-}" != auth/logout ]]; then
    _sllg=""; _sltok="$(_bearer_token)"
    if [[ -n "$_sltok" ]] && valid_id "$_sltok" && [[ -f "$SESSIONDIR/$_sltok" ]]; then
      _sllg="$( LOGIN=""; source "$SESSIONDIR/$_sltok" 2>/dev/null; printf '%s' "$LOGIN" )"
    fi
    if ! is_reserved_role_login "$_sllg"; then
      sl_record_block "$_slby" "$_slip" "$_sltgt" "${PATH_INFO:-}" "$_sllg"
      fail 403 "Esta rede está presa ao contest '$_slby' durante a prova (só ele é acessível daqui)" "site_locked"
    fi
  fi
fi

handler="$HANDLERS$_safe.sh"
[[ -f "$handler" ]] || fail 404 "No such route: $route" "route_notfound"
source "$handler"
