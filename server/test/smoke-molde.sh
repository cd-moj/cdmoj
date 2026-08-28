#!/bin/bash
# smoke-molde.sh — o worker persistente (molde.sh) pelo PROTOCOLO, sem o shim C:
# falamos com ele por pipes exatamente como o moj-molde-shim falaria. O que se prova:
#   1. requisições sequenciais no MESMO worker (o modo de vida do molde);
#   2. isolamento: fail/exit contido; PARAMS re-parseado; env de requisição NÃO vaza
#      p/ a seguinte (CONTEST_HOST/HTTP_AUTHORIZATION ausentes = ausentes de verdade);
#   3. corpo via arquivo (read_body enxerga stdin com EOF);
#   4. reciclagem (MOLDE_MAX_REQS) com saída limpa.
# O shim C é provado pelo --selftest do build da imagem e pelo diferencial em produção.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../api/v1"
W="$(mktemp -d)"; MPID=""
trap 'rm -rf "$W"; [[ -n "$MPID" ]] && kill "$MPID" 2>/dev/null' EXIT
pass=0; failn=0
ok(){ echo "  ok: $1"; pass=$((pass+1)); }
bad(){ echo "  FALHOU: $1"; failn=$((failn+1)); }

: > "$W/body"
coproc MOLDE { MOLDE_WDIR="$W" MOLDE_MAX_REQS=6 bash molde.sh 2>"$W/molde.err"; }
# coproc nomeado ⇒ o bash põe o pid em MOLDE_PID.
# ⚠ fds de coproc SÃO FECHADOS em subshells ($(…)) — a pegadinha documentada no desenho do
# molde (D6): duplicamos p/ fds fixos, que subshell herda. É o mesmo motivo pelo qual os
# coprocs de jq do molde (fase 2) ancoram em fds ≥10. E o MOLDE_PID é DESFEITO pelo bash
# quando o coproc morre (reciclagem) — guardamos a cópia nossa antes.
exec {CTL}>&"${MOLDE[1]}" {ST}<&"${MOLDE[0]}"
MPID="$MOLDE_PID"

req(){ # req VAR=VAL... — manda records + despacho, espera done, ecoa o rc
  local kv
  for kv in "$@"; do printf '%s\0' "$kv" >&"$CTL"; done
  printf '\0' >&"$CTL"
  local done_msg
  IFS= read -r -d '' -u "$ST" done_msg || { echo "EOF"; return 1; }
  echo "${done_msg#done }"
}

echo "== req 1: rota raiz"
: > "$W/body"
rc="$(req PATH_INFO=/ REQUEST_METHOD=GET QUERY_STRING=)"
head -1 "$W/resp.out" | grep -q "Status: 200" && ok "Status 200 (rc=$rc)" || bad "resp: $(head -1 "$W/resp.out")"
grep -q '"name":"MOJ API"' "$W/resp.out" && ok "corpo da raiz" || bad "corpo: $(tail -1 "$W/resp.out")"

echo "== req 2: 404 (fail/exit contido) e QUERY_STRING nova"
: > "$W/body"
rc="$(req PATH_INFO=/nao/existe REQUEST_METHOD=GET QUERY_STRING=x=1)"
grep -q "route_notfound" "$W/resp.out" && ok "404 no subshell, worker vivo" || bad "resp2: $(tail -1 "$W/resp.out")"

echo "== req 3: env de requisição NÃO vaza (CONTEST_HOST setado…)"
: > "$W/body"
rc="$(req PATH_INFO=/index/contests REQUEST_METHOD=GET QUERY_STRING= CONTEST_HOST=zz-fake)"
grep -q "contest_isolated" "$W/resp.out" && ok "CONTEST_HOST ativo na req 3 (403 do gate)" || bad "esperava contest_isolated: $(tail -1 "$W/resp.out")"

echo "== req 4: …e a requisição seguinte SEM CONTEST_HOST não herda o gate"
: > "$W/body"
rc="$(req PATH_INFO=/index/contests REQUEST_METHOD=GET QUERY_STRING=)"
grep -q '"success":true' "$W/resp.out" && ok "req seguinte livre do CONTEST_HOST anterior" || bad "vazou: $(tail -1 "$W/resp.out")"

echo "== req 5: corpo chega pelo arquivo (read_body)"
printf '{"whatever":1}' > "$W/body"
rc="$(req PATH_INFO=/auth/login REQUEST_METHOD=POST QUERY_STRING= CONTENT_TYPE=application/json)"
grep -qE '"(success|error)"' "$W/resp.out" && ok "POST processou o corpo (login falha educadamente)" || bad "resp5: $(tail -1 "$W/resp.out")"

echo "== req 6 + reciclagem (MOLDE_MAX_REQS=6): worker sai LIMPO após o done"
: > "$W/body"
rc="$(req PATH_INFO=/ REQUEST_METHOD=GET QUERY_STRING=)"
[[ "$rc" == 0 ]] && ok "req 6 respondida" || bad "rc=$rc"
sleep 0.3
if kill -0 "$MPID" 2>/dev/null; then bad "worker deveria ter reciclado"; else ok "reciclou (saiu) após K requisições"; fi
MPID=""

echo
echo "RESULT: $pass passed, $failn failed"
(( failn == 0 ))
