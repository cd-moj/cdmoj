#!/bin/bash
# smoke-team-logo-nginx.sh — MÍDIA DE TIME no nginx (05/11/2026; moj-app.conf.in "MÍDIA DE TIME" + o bloco de mesmo nome
# nos dois conf.d). O placar de 500+ times rebaixava cada brasão a cada minuto, um bash por pedido no balde do /submit.
# Garante:
#   · o BRASÃO válido sai do DISCO pelo nginx (image/png, ETag, 304), com cache imutável quando a URL leva `v`;
#   · TODO o resto cai no bash (@moj_media), que segue sendo a autoridade: argumento fora da lista de caracteres
#     (ponto/hífen no começo, %, /), host de OUTRO contest (o contest_mismatch), arquivo ausente, argumento faltando;
#   · foto, música e o padrão vão ao bash pela zona PRÓPRIA de mídia, com o freio do treino valendo no site principal;
#   · o bloco "MÍDIA DE TIME" é o MESMO nos dois templates do conf.d (só um deles é instalado).
# Com `nginx` no PATH sobe um nginx de teste (porta alta, tudo em tmp) com o snippet e o bloco REAIS renderizados; cada
# `fastcgi_pass` vira um `return` que ecoa a rota — é como se vê que o pedido caiu no bash. Sem nginx, só os templates.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"     # .../cdmoj
E="$ROOT/server/etc/nginx"; TPL="$E/moj-app.conf.in"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: S=${S:-} ${B:-}"; ((fail++)); fi; }
blk(){ sed -n '/^# >>> MÍDIA DE TIME/,/^# <<< MÍDIA DE TIME/p' "$1"; }

echo "== templates =="
ck "o bloco existe no moj-prod.conf.in"                 '[[ "$(blk "$E/moj-prod.conf.in" | grep -c "moj_logo_file\|zone=moj_media")" -ge 2 ]]'
ck "…e é IGUAL no moj-prod-http.conf.in"                '[[ "$(blk "$E/moj-prod.conf.in")" == "$(blk "$E/moj-prod-http.conf.in")" ]]'
ck "o snippet serve o brasão do disco e cai no bash"    'grep -q "location = /api/v1/contest/team-logo" "$TPL" && grep -q "try_files     \$moj_logo_file @moj_media;" "$TPL"'
ck "@moj_media: zona própria, SEM o breaker do contest" '[[ "$(sed -n "/^location @moj_media {/,/^}/p" "$TPL" | grep -c "limit_conn              moj_media\|moj-breaker-contest")" == 1 ]] && sed -n "/^location @moj_media {/,/^}/p" "$TPL" | grep -q "limit_conn              moj_media"'

if ! command -v nginx >/dev/null 2>&1; then
  echo "  (nginx ausente — pulando o teste de servidor)"
  echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
fi

echo "== nginx de teste =="
T="$(mktemp -d)"; PORT=$(( 20000 + RANDOM % 20000 ))
trap 'nginx -p "$T" -c "$T/nginx.conf" -s stop >/dev/null 2>&1; rm -rf "$T"' EXIT
mkdir -p "$T/logs" "$T/run" "$T/wr/run" "$T/wr/contests/prova-x/users/time1" "$T/wr/contests/prova-x/users/time2" \
         "$T/wr/contests/prova-x/users/.removed-users/velho" "$T/wr/contests/outra/users/t9" "$T/wr/segredo"
ln -s "$ROOT" "$T/wr/cdmoj"
printf '\x89PNG\r\n\x1a\nbrasao-time1' > "$T/wr/contests/prova-x/users/time1/logo.png"
printf '\x89PNG\r\n\x1a\nvelho'        > "$T/wr/contests/prova-x/users/.removed-users/velho/logo.png"
printf '\x89PNG\r\n\x1a\nt9'           > "$T/wr/contests/outra/users/t9/logo.png"
printf 'SEGREDO\n'                     > "$T/wr/segredo/logo.png"
# o snippet REAL: includes de /etc/nginx fora (não existem aqui); cada fastcgi_pass ecoa a rota e a location
sed "s#@WORKROOT@#$T/wr#g; s#@ROUTER@#/nao/usado#g; /include[[:space:]]\+\/etc\/nginx\/moj-/d" "$TPL" \
  | awk '/^location @moj_media \{/{m=1} /^\}/{m=0}
         /fastcgi_pass/{ sub(/fastcgi_pass.*/, (m ? "return 200 \"bash-media $uri?$args\\n\";" : "return 200 \"bash-geral $uri?$args\\n\";")) }
         {print}' > "$T/app.conf"
cat > "$T/nginx.conf" <<EOF
worker_processes 1; pid $T/run/nginx.pid; error_log $T/logs/error.log;
events { worker_connections 64; }
http {
  include /etc/nginx/mime.types; access_log off;
  client_body_temp_path $T/run/b; proxy_temp_path $T/run/p; fastcgi_temp_path $T/run/f; uwsgi_temp_path $T/run/u; scgi_temp_path $T/run/s;
  map \$host \$moj_contest_host { default ""; ~^(?<cid>[a-z0-9][a-z0-9._-]*)\.(?:moj\.test)\$ \$cid; }
  map \$moj_contest_host \$moj_site_conn { "" "site"; default ""; }
  map \$moj_contest_host \$moj_shed_file { "" "$T/shed"; default "/nonexistent"; }
  map \$arg_id \$moj_legacy_probid { default ""; }
  limit_conn_zone \$moj_site_conn zone=moj_site:1m;
  limit_conn_status 429;
$(blk "$E/moj-prod.conf.in")
  server { listen 127.0.0.1:$PORT; server_name moj.test ~^[a-z0-9][a-z0-9._-]*\.moj\.test\$; include $T/app.conf; }
}
EOF
if ! nginx -p "$T" -c "$T/nginx.conf" 2>"$T/start.err"; then
  ck "nginx de teste subiu" 'false'; sed 's/^/    /' "$T/start.err" | head -8
  echo ""; echo "RESULT: $pass passed, $fail failed"; exit 1
fi
# req <host> <caminho+query> [cabeçalho extra] -> H (cabeçalhos) e B (corpo); S = status
req(){ local h="$1" p="$2"; shift 2
  : > "$T/b"; : > "$T/h"; curl -g -s --max-time 5 -D "$T/h" -o "$T/b" -H "Host: $h" "$@" "http://127.0.0.1:$PORT$p"
  H="$(tr -d '\r' < "$T/h")"; B="$(cat "$T/b")"; S="$(sed -n '1s/^HTTP[^ ]* \([0-9]*\).*/\1/p' <<<"$H")"; }
hd(){ sed -n "s/^$1: //Ip" <<<"$H" | head -1; }
L='/api/v1/contest/team-logo'

echo "== o brasão válido sai do disco =="
req moj.test "$L?contest=prova-x&user=time1"
ck "200 com o arquivo, sem bash"                        '[[ "$S" == 200 && "$B" == *brasao-time1 && "$B" != bash* ]]'
ck "Content-Type image/png"                             '[[ "$(hd Content-Type)" == image/png ]]'
ck "ETag e Last-Modified (validadores)"                 '[[ -n "$(hd ETag)" && -n "$(hd Last-Modified)" ]]'
ck "sem v: público, 10 min"                             '[[ "$(hd Cache-Control)" == "public, max-age=600" ]]'
ET="$(hd ETag)"
req moj.test "$L?contest=prova-x&user=time1" -H "If-None-Match: $ET"
ck "If-None-Match → 304 (com o Cache-Control)"          '[[ "$S" == 304 && -z "$B" && "$(hd Cache-Control)" == "public, max-age=600" ]]'
req moj.test "$L?contest=prova-x&user=time1&v=1793025188123"
ck "com v: imutável por um ano"                         '[[ "$S" == 200 && "$(hd Cache-Control)" == "public, max-age=31536000, immutable" ]]'
req prova-x.moj.test "$L?contest=prova-x&user=time1&v=1"
ck "no subdomínio DO contest: do disco"                 '[[ "$S" == 200 && "$B" == *brasao-time1 ]]'

echo "== todo o resto cai no bash (a autoridade) =="
fell(){ req "$1" "$2"; [[ "$S" == 200 && "$B" == "bash-media $L?"* ]]; }
ck "time sem brasão"                                    'fell moj.test "$L?contest=prova-x&user=time2"'
ck "login que não existe"                               'fell moj.test "$L?contest=prova-x&user=ninguem"'
ck "subdomínio de OUTRO contest (contest_mismatch)"     'fell outra.moj.test "$L?contest=prova-x&user=time1"'
ck "contest com ponto no começo (..)"                   'fell moj.test "$L?contest=..&user=time1"'
ck "login com ponto no começo (.removed-users)"         'fell moj.test "$L?contest=prova-x&user=.removed-users"'
ck "login com hífen no começo"                          'fell moj.test "$L?contest=prova-x&user=-time1"'
ck "barra codificada no login (%2F)"                    'fell moj.test "$L?contest=prova-x&user=..%2F..%2Fsegredo"'
ck "barra crua no contest"                              'fell moj.test "$L?contest=prova-x/users/time1/../../..&user=x"'
ck "ponto codificado (%2e%2e)"                          'fell moj.test "$L?contest=%2e%2e&user=segredo"'
ck "byte nulo codificado"                               'fell moj.test "$L?contest=prova-x&user=time1%00"'
ck "sem o user"                                         'fell moj.test "$L?contest=prova-x"'
ck "sem o contest"                                      'fell moj.test "$L?user=time1"'
ck "a query segue inteira até o bash"                   '[[ "$B" == "bash-media $L?user=time1" ]]'
ck "pipe cru não forja o separador da chave do map"    'fell moj.test "$L?contest=prova-x|&user=time1" && fell moj.test "$L?contest=prova-x&user=time1|prova-x"'
req moj.test "$L?contest=prova-x&user=..%2F..%2Fsegredo"
ck "…e nada de fora do contests/ vaza"                  '[[ "$B" != *SEGREDO* ]]'

echo "== foto, música e o padrão: bash pela zona de mídia =="
for r in team-photo team-music placeholder; do
  req moj.test "/api/v1/contest/$r?contest=prova-x&user=time1&thumb=1"
  ck "$r → @moj_media com a query"                     '[[ "$B" == "bash-media /api/v1/contest/$r?contest=prova-x&user=time1&thumb=1" ]]'
done
req prova-x.moj.test "/api/v1/contest/team-photo?contest=prova-x&user=time1"
ck "…também no subdomínio"                              '[[ "$B" == bash-media* ]]'
req moj.test "/api/v1/contest/team-photos?contest=prova-x"
ck "rota vizinha (team-photos) segue na /api/v1/ geral"  '[[ "$B" == bash-geral* ]]'
req moj.test "/api/v1/contest/score?contest=prova-x"
ck "o resto da API segue na /api/v1/ geral"             '[[ "$B" == bash-geral* ]]'

echo "== freio do treino (moj-shed-treino) =="
touch "$T/shed"
req moj.test "/api/v1/contest/team-photo?contest=prova-x&user=time1"
ck "site principal: mídia no bash → 503"                '[[ "$S" == 503 ]]'
req prova-x.moj.test "/api/v1/contest/team-photo?contest=prova-x&user=time1"
ck "subdomínio de contest: não olha o freio"            '[[ "$S" == 200 && "$B" == bash-media* ]]'
req moj.test "$L?contest=prova-x&user=time1"
ck "o brasão do disco não passa pelo bash: segue 200"   '[[ "$S" == 200 && "$B" == *brasao-time1 ]]'
rm -f "$T/shed"

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
