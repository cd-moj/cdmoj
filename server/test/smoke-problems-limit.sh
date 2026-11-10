#!/bin/bash
# smoke-problems-limit.sh — balde PRÓPRIO da autoria no nginx (10/11/2026; bloco "AUTORIA" dos dois moj-prod*.conf.in +
# `location /api/v1/problems/` do moj-app.conf.in): 6 em voo por SESSÃO (token; sem token, o IP) e 12 no TOTAL.
# Com `nginx` e `python3` no PATH sobe um nginx de teste com o snippet e o bloco REAIS e troca o `fastcgi_pass` da
# autoria por um upstream LENTO (1,5 s por pedido), p/ os pedidos ficarem em voo juntos; sem nginx, só os templates.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"     # .../cdmoj
E="$ROOT/server/etc/nginx"; TPL="$E/moj-app.conf.in"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${R:-}"; ((fail++)); fi; }
blk(){ sed -n '/^# >>> AUTORIA/,/^# <<< AUTORIA/p' "$1"; }
loc(){ sed -n '/^location \/api\/v1\/problems\/ {/,/^}/p' "$TPL"; }

echo "== templates =="
ck "o bloco existe no moj-prod.conf.in (3 zonas)"   '[[ "$(blk "$E/moj-prod.conf.in" | grep -c "zone=moj_problems_key:\|zone=moj_problems_ip:\|zone=moj_problems:")" == 3 ]]'
ck "…e é IGUAL no moj-prod-http.conf.in"            '[[ "$(blk "$E/moj-prod.conf.in")" == "$(blk "$E/moj-prod-http.conf.in")" ]]'
ck "a location da autoria usa as três zonas e o prazo do corpo" 'loc | grep -q "limit_conn moj_problems_key 6;" && loc | grep -q "limit_conn moj_problems_ip 8;" && loc | grep -q "limit_conn moj_problems 12;" && loc | grep -q "client_body_timeout 15s;"'
ck "…e segue FORA do moj_site e do breaker"         '! loc | grep -q "moj_site\|moj-breaker-contest"'

if ! command -v nginx >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "  (nginx/python3 ausente — pulando o teste de servidor)"
  echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
fi

echo "== nginx de teste =="
T="$(mktemp -d)"; PORT=$(( 20000 + RANDOM % 20000 )); UP=$(( PORT + 1 ))
trap 'nginx -p "$T" -c "$T/nginx.conf" -s stop >/dev/null 2>&1; [[ -n "${PYPID:-}" ]] && kill "$PYPID" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/logs" "$T/run"
python3 -I - "$UP" >/dev/null 2>&1 <<'PY' &
import sys, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(1.5); self.send_response(200); self.send_header('Content-Length', '3'); self.end_headers(); self.wfile.write(b'ok\n')
    def log_message(self, *a): pass
ThreadingHTTPServer.request_queue_size = 128
ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
PYPID=$!
# o snippet REAL: includes de /etc/nginx fora; o fastcgi_pass da AUTORIA vira o upstream lento, os outros um return
sed "s#@WORKROOT@#$T#g; s#@ROUTER@#/nao/usado#g; /include[[:space:]]\+\/etc\/nginx\/moj-/d" "$TPL" \
  | awk -v up="$UP" '/^location \/api\/v1\/problems\/ \{/{m=1} /^\}/{m=0}
         /fastcgi_pass/{ if (m) sub(/fastcgi_pass.*/, "proxy_pass http://127.0.0.1:" up ";"); else sub(/fastcgi_pass.*/, "return 200 \"bash\\n\";") }
         /fastcgi_split_path_info/{ next } {print}' > "$T/app.conf"
cat > "$T/nginx.conf" <<EOF
worker_processes 1; pid $T/run/nginx.pid; error_log $T/logs/error.log;
events { worker_connections 256; }
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
$(sed -n '/^# >>> MÍDIA DE TIME/,/^# <<< MÍDIA DE TIME/p' "$E/moj-prod.conf.in" | sed "s#@WORKROOT@#$T#g")
  server { listen 127.0.0.1:$PORT; server_name moj.test; include $T/app.conf; }
}
EOF
for _ in $(seq 50); do (exec 3<>"/dev/tcp/127.0.0.1/$UP") 2>/dev/null && break; sleep 0.1; done
if nginx -p "$T" -c "$T/nginx.conf" 2>"$T/start.err"; then
  # rajada: N pedidos JUNTOS, cada um com o token que a função dá; conta os códigos
  burst(){ local n="$1" mk="$2" i pids=(); rm -f "$T"/c.*
    for (( i=0; i<n; i++ )); do
      curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "Host: moj.test" $($mk "$i") \
        "http://127.0.0.1:$PORT/api/v1/problems/tl?id=x" > "$T/c.$i" & pids+=($!)
    done; wait "${pids[@]}"   # só os curl: um `wait` nu esperaria o upstream de fundo p/ sempre
    R="200=$(cat "$T"/c.* | grep -o 200 | wc -l) 429=$(cat "$T"/c.* | grep -o 429 | wc -l)"; }
  one(){ echo "-H Authorization:Bearer-um"; }
  each(){ echo "-H Authorization:Bearer-t$1 --interface 127.0.0.$(( 1 + $1 % 3 ))"; }   # 3 IPs de origem (o loopback é /8)
  eachip1(){ echo "-H Authorization:Bearer-u$1"; }
  anon(){ :; }
  burst 9 one;   ck "mesma sessão, 9 juntos: 6 passam e 3 levam 429"     '[[ "$R" == "200=6 429=3" ]]'
  burst 5 one;   ck "mesma sessão, 5 juntos (o editor abrindo): nenhum 429" '[[ "$R" == "200=5 429=0" ]]'
  burst 15 each; ck "15 sessões em 3 IPs: o teto global segura 12"     '[[ "$R" == "200=12 429=3" ]]'
  burst 10 eachip1; ck "10 sessões do MESMO IP: o teto por IP segura 8" '[[ "$R" == "200=8 429=2" ]]'
  # teto por IP: 12 conexões de um IP (cada uma com a sua chave de sessão) não ocupam o total
  head -c 20000 /dev/zero > "$T/big"; sl=()
  for (( i=0; i<12; i++ )); do
    curl -s -o /dev/null --max-time 8 --interface 127.0.0.2 -H "Host: moj.test" -H "Authorization: Bearer-s$i" \
      --limit-rate 100 --data-binary @"$T/big" "http://127.0.0.1:$PORT/api/v1/problems/tl?id=x" & sl+=($!)
  done
  sleep 2
  R="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --interface 127.0.0.3 -H 'Host: moj.test' -H 'Authorization: Bearer-autor' "http://127.0.0.1:$PORT/api/v1/problems/tl?id=x")"
  ck "12 conexões de um IP: o autor de outro IP passa" '[[ "$R" == 200 ]]'
  R="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 --interface 127.0.0.2 -H 'Host: moj.test' -H 'Authorization: Bearer-outro' "http://127.0.0.1:$PORT/api/v1/problems/tl?id=x")"
  ck "…e o IP delas está no teto (429)" '[[ "$R" == 429 ]]'
  kill "${sl[@]}" 2>/dev/null; wait "${sl[@]}" 2>/dev/null
  burst 8 anon;  ck "sem token: o balde é o IP (6)"                       '[[ "$R" == "200=6 429=2" ]]'
  R="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: moj.test' "http://127.0.0.1:$PORT/api/v1/auth/status")"
  ck "o resto da API não passa pela zona da autoria"      '[[ "$R" == 200 ]]'
else
  ck "nginx de teste subiu" 'false'; sed 's/^/    /' "$T/start.err" | head -5
fi

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
