#!/bin/bash
# smoke-machines-suggest.sh — a SUGESTÃO de substring do gate no painel Máquinas (/contest/admin/machines).
# TCP 2026 (03/10/2026): 8 s por abertura (um `base64 -d` por UA e um `grep` por substring candidata — 4.753 processos
# com 43 UAs únicos, porque machine_id+MAC tornam cada UA único) e a sugestão saía inútil
# (") Gecko/20100101 Firefox/140.13.0" casa qualquer Firefox). Prende: imagens por sede do mlinux ⇒ prefixo comum
# das imagens cortado num separador; imagem única ⇒ "MLinux/<imagem>/"; navegadores comuns ⇒ maior substring comum;
# e o tempo com 60 UAs únicos.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
C="$FIX/ms"; mkdir -p "$C/var" "$C/users/ms.admin"; NOW=$EPOCHSECONDS
printf 'CONTEST_ID=ms\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nPROBS=( x col#pa A A col#pa )\n' $((NOW-3600)) $((NOW+3600)) > "$C/conf"
jq -cn '{login:"ms.admin", fullname:"Admin", password:"x"}' > "$C/users/ms.admin/account.json"
printf 'CONTEST=ms\nLOGIN=ms.admin\nLOGINAT=1\n' > "$SESS/t-adm"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: got [$SUG] em ${MS}ms"; ((fail++)); fi; }
mid(){ printf '%032x' "$1"; }
log(){ # <login> <ua>
  printf '%s\t%s\t10.0.0.%d\t%s\n' $((NOW-600)) "$1" $((RANDOM%250)) "$(printf '%s' "$2" | base64 -w0)" >> "$C/var/access.log"; }
get(){ local t0=$EPOCHREALTIME; OUT="$(PATH_INFO=/contest/admin/machines REQUEST_METHOD=GET QUERY_STRING=contest=ms \
    HTTP_AUTHORIZATION="Bearer t-adm" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" bash "$ROUTER" 2>/dev/null)"
  MS=$(( (${EPOCHREALTIME/./} - ${t0/./}) / 1000 )); SUG="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}' | jq -r .ua_suggestion)"; }
FF='Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.13.0'

echo "== imagens por sede (cl.tcp.2026.<sede>), 60 UAs únicos =="
: > "$C/var/access.log"; i=0
for s in uach utfsm uta ucm uvm pucv; do for k in $(seq 1 10); do i=$((i+1))
  log "team${s}$(printf %03d $k)" "$FF MLinux/cl.tcp.2026.$s/$(mid $i)/$((1000+i))/aa:bb:cc:00:00:$(printf %02x $i)"; done; done
get
ck "prefixo comum das imagens, cortado no separador" '[[ "$SUG" == "MLinux/cl.tcp.2026." ]]'
ck "rápido (< 2 s; eram 8 s em produção)"            '(( MS < 2000 ))'

echo "== imagem única =="
: > "$C/var/access.log"
for k in 1 2 3; do log "teamx00$k" "$FF MLinux/26lc/$(mid $k)/$((50+k))"; done
get
ck "MLinux/<imagem>/"                                '[[ "$SUG" == "MLinux/26lc/" ]]'

echo "== navegadores comuns (sem mlinux) =="
: > "$C/var/access.log"
log teama001 "Mozilla/5.0 (X11; Linux) MOJBOX-sala-7 Chrome/120"; log teama002 "Mozilla/5.0 (Windows) MOJBOX-sala-7 Firefox/119"
get
ck "maior substring comum"                           '[[ "$SUG" == ") MOJBOX-sala-7 " ]]'
log teama003 "curl/8.0"
get
ck "nada em comum (≥ 8): vazia"                      '[[ -z "$SUG" ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
