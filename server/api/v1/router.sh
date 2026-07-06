#!/bin/bash
# MOJ API v1 — front controller único (rodado via fcgiwrap atrás do nginx).
# Despacha PATH_INFO -> handlers/<segmentos>.sh. Handlers são "sourced" (rodam
# no mesmo shell, com lib/* e PARAMS já carregados) e usam $REQUEST_METHOD.
#
# Teste local (sem nginx):
#   PATH_INFO=/treino/problem QUERY_STRING='id=moj-problems#olamundo' \
#   REQUEST_METHOD=GET bash router.sh

_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$_DIR/lib/common.sh"
source "$_DIR/lib/params.sh"
source "$_DIR/lib/auth.sh"
source "$_DIR/lib/worker-auth.sh"
source "$_DIR/lib/bot-auth.sh"
source "$_DIR/lib/profile.sh"
source "$_DIR/lib/users.sh"
source "$_DIR/lib/verdict.sh"
source "$_DIR/lib/telegram.sh"
source "$_DIR/lib/alerts.sh"

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

handler="$HANDLERS$_safe.sh"
[[ -f "$handler" ]] || fail 404 "No such route: $route" "route_notfound"
source "$handler"
