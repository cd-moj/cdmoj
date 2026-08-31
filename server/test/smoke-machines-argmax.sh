#!/bin/bash
# smoke-machines-argmax.sh — /contest/admin/machines com mapa GRANDE (>128 KiB).
# Incidente 2026-08-31 (treino): o handler passava o mapa inteiro por --argjson DEPOIS do
# emit_json — o exec estourava ARG_MAX ("jq: Argument list too long") e o admin via
# "Resposta inválida do servidor" (200 com corpo vazio). As DUAS armadilhas documentadas
# da casa juntas. Agora sai por ok_json_slurp; este teste fixa o caso oversized.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
C="$FIX/mx"; mkdir -p "$C/var" "$C/users"
NOW=$(date +%s)
printf 'CONTEST_ID=mx\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x col#pa A A col#pa )\n' \
  "$((NOW-3600))" "$((NOW+3600))" > "$C/conf"
mkdir -p "$C/users/mx.admin"
jq -cn '{login:"mx.admin", fullname:"Admin", password:"x"}' > "$C/users/mx.admin/account.json"
printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' mx mx.admin mx.admin "$NOW" > "$SESS/t-adm"

# access.log TSV (epoch login ip ua_b64) com 1.200 logins × UA de ~200 chars ⇒ mapa >>128KiB
UA_B64="$(printf 'Mozilla/5.0 (X11; MaratonaLinux %0.s' {1..6}; printf ') sede-teste-oversized-uaua')"
UA_B64="$(printf '%s' "$UA_B64" | base64 -w0)"
for (( i=0; i<1200; i++ )); do
  printf '%s\t%s\t10.0.%d.%d\t%s\n' "$((NOW-1000))" "$(printf 'teamov%04d' "$i")" "$((i/250))" "$((i%250))" "$UA_B64"
done > "$C/var/access.log"

OUT="$(PATH_INFO=/contest/admin/machines REQUEST_METHOD=GET QUERY_STRING="contest=mx" \
  HTTP_AUTHORIZATION="Bearer t-adm" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>/dev/null)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"

PASS=0; FAIL=0
if [[ -n "$BODY" ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: corpo VAZIO (a assinatura do ARG_MAX)" >&2; fi
if jq -e '.success == true and (.by_login | length) == 1200' <<<"$BODY" >/dev/null 2>&1; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FALHOU: resposta não parseia/incompleta: $(head -c 120 <<<"$BODY")" >&2; fi
n=$(( $(printf '%s' "$BODY" | wc -c) ))
if (( n > 131072 )); then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FALHOU: fixture pequeno demais ($n bytes) — não exercita o teto" >&2; fi

echo "smoke-machines-argmax: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
