#!/bin/bash
# smoke-robots.sh — o /robots.txt sai POR HOST (30/10/2026): o web/ é o mesmo em todo host, então o nginx
# (server/etc/nginx/moj-app.conf.in, `location = /robots.txt`) entrega no subdomínio de contest o
# web/robots-contest.txt ("Disallow: /") e no site principal o web/robots.txt (só a API fora).
# Com `nginx` no PATH, sobe um nginx de teste (porta alta, tudo em tmp) com o snippet renderizado e pede o
# /robots.txt nos dois hosts; sem nginx, confere só os arquivos e o template.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"     # .../cdmoj
W="$ROOT/web"; TPL="$ROOT/server/etc/nginx/moj-app.conf.in"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1"; ((fail++)); fi; }

echo "== arquivos e template =="
ck "web/robots.txt: todos os robôs, só a API fora" 'grep -qx "User-agent: \*" "$W/robots.txt" && [[ "$(grep -c "^Disallow:" "$W/robots.txt")" == 1 ]] && grep -qx "Disallow: /api/" "$W/robots.txt"'
ck "web/robots-contest.txt: nada a ler"            'grep -qx "User-agent: \*" "$W/robots-contest.txt" && grep -qx "Disallow: /" "$W/robots-contest.txt"'
ck "template troca o arquivo pelo host de contest" 'grep -q "location = /robots.txt" "$TPL" && grep -q "if (\$moj_contest_host != \"\") { rewrite ^ /robots-contest.txt last; }" "$TPL"'

if ! command -v nginx >/dev/null 2>&1; then
  echo "  (nginx ausente — pulando o teste de servidor)"
else
  echo "== nginx de teste: o /robots.txt de cada host =="
  T="$(mktemp -d)"; PORT=$(( 20000 + RANDOM % 20000 ))
  trap 'nginx -p "$T" -c "$T/nginx.conf" -s stop >/dev/null 2>&1; rm -rf "$T"' EXIT
  mkdir -p "$T/logs" "$T/run"
  # só o que o teste precisa do moj.conf: o map do host de contest e um server que inclui o snippet
  sed "s#@WORKROOT@#${ROOT%/cdmoj}#g; s#@ROUTER@#/nao/usado#g; /include \/etc\/nginx\/moj-/d" "$TPL" > "$T/app.conf"
  cat > "$T/nginx.conf" <<EOF
worker_processes 1; pid $T/run/nginx.pid; error_log $T/logs/error.log;
events { worker_connections 16; }
http {
  include /etc/nginx/mime.types; access_log off;
  client_body_temp_path $T/run/b; proxy_temp_path $T/run/p; fastcgi_temp_path $T/run/f; uwsgi_temp_path $T/run/u; scgi_temp_path $T/run/s;
  map \$host \$moj_contest_host { default ""; ~^(?<cid>[a-z0-9][a-z0-9._-]*)\.(?:moj\.test)\$ \$cid; }
  map \$moj_contest_host \$moj_site_conn { "" "site"; default ""; }
  map \$moj_contest_host \$moj_shed_file { "" "$T/shed"; default "/nonexistent"; }
  map \$arg_id \$moj_legacy_probid { default ""; }
  limit_conn_zone \$moj_site_conn zone=moj_site:1m;
  server { listen 127.0.0.1:$PORT; server_name moj.test ~^[a-z0-9][a-z0-9._-]*\.moj\.test\$; include $T/app.conf; }
}
EOF
  if nginx -p "$T" -c "$T/nginx.conf" 2>"$T/start.err"; then
    get(){ curl -s --max-time 5 -H "Host: $1" "http://127.0.0.1:$PORT$2"; }
    ck "site principal: Disallow: /api/"            '[[ "$(get moj.test /robots.txt | grep "^Disallow:")" == "Disallow: /api/" ]]'
    ck "subdomínio de contest: Disallow: /"         '[[ "$(get prova-x.moj.test /robots.txt | grep "^Disallow:")" == "Disallow: /" ]]'
    ck "…e o resto do estático segue servido lá"    '[[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Host: prova-x.moj.test" "http://127.0.0.1:$PORT/shared/ui.css")" == 200 ]]'
  else
    ck "nginx de teste subiu" 'false'; sed 's/^/    /' "$T/start.err" | head -5
  fi
fi

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
