#!/bin/bash
# smoke-team-media-nginx.sh — MÍDIA DE TIME no nginx (05/11/2026; moj-app.conf.in "MÍDIA DE TIME" + o bloco de mesmo nome
# nos dois conf.d). O placar de 500+ times rebaixava cada brasão a cada minuto, um bash por pedido no balde do /submit.
# Garante:
#   · o BRASÃO válido sai do DISCO pelo nginx (image/png, ETag, 304), com cache imutável quando a URL leva `v`;
#   · a FOTO também: photo.webp › photo.png legado (a ordem do tp_file), `thumb` não vazio = só a photo.thumb.webp, e o
#     cache do bash (miniatura 1 dia, foto 1 min, imutável com `v`);
#   · e a MÚSICA: music.mp3 (audio/mpeg, Range/206), 1 min sem `v`, imutável com ele;
#   · e o PADRÃO (rota /contest/placeholder e time sem foto/música): o do contest › o de fábrica do checkout, na ordem do
#     tp_placeholder/tm_placeholder, com X-MOJ-Photo/X-MOJ-Music e 1 min — só com o contest EXISTENTE (o conf);
#   · TODO o resto cai no bash (@moj_media), que segue sendo a autoridade: argumento fora da lista de caracteres
#     (ponto/hífen no começo, %, /, `..`), host de OUTRO contest (o contest_mismatch), contest sem conf, a miniatura que
#     o bash gera (a foto do time existe), o brasão ausente, argumento faltando, `kind` codificado;
#   · o que cai no bash vai pela zona PRÓPRIA de mídia, com o freio do treino valendo no site principal;
#   · o bloco "MÍDIA DE TIME" é o MESMO nos dois templates do conf.d (só um deles é instalado).
# Com `nginx` no PATH sobe um nginx de teste (porta alta, tudo em tmp) com o snippet e o bloco REAIS renderizados; cada
# `fastcgi_pass` vira um `return` que ecoa a rota — é como se vê que o pedido caiu no bash. Sem nginx, só os templates.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"     # .../cdmoj
E="$ROOT/server/etc/nginx"; TPL="$E/moj-app.conf.in"
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: S=${S:-} ${B:-}"; ((fail++)); fi; }
blk(){ sed -n '/^# >>> MÍDIA DE TIME/,/^# <<< MÍDIA DE TIME/p' "$1"; }

echo "== templates =="
ck "o bloco existe no moj-prod.conf.in"                 '[[ "$(blk "$E/moj-prod.conf.in" | grep -c "moj_logo_file\|moj_photo_file\|zone=moj_media")" -ge 3 ]]'
ck "…e é IGUAL no moj-prod-http.conf.in"                '[[ "$(blk "$E/moj-prod.conf.in")" == "$(blk "$E/moj-prod-http.conf.in")" ]]'
ck "o snippet serve o brasão do disco e cai no bash"    'grep -q "location = /api/v1/contest/team-logo" "$TPL" && grep -q "try_files     \$moj_logo_file @moj_media;" "$TPL"'
ck "…e a foto (webp › png legado › bash)"               'grep -q "location = /api/v1/contest/team-photo" "$TPL" && grep -q "try_files     \$moj_photo_file \$moj_photo_alt @moj_padrao;" "$TPL"'
ck "…e a música"                                        'grep -q "location = /api/v1/contest/team-music" "$TPL" && grep -q "try_files     \$moj_music_file @moj_padrao;" "$TPL"'
ck "…e o padrão (@moj_padrao)"                          'grep -q "location = /api/v1/contest/placeholder" "$TPL" && grep -q "try_files     \$moj_ph1 \$moj_ph2 \$moj_ph3 \$moj_ph4 @moj_media;" "$TPL"'
ck "@moj_media: zona própria, SEM o breaker do contest" '[[ "$(sed -n "/^location @moj_media {/,/^}/p" "$TPL" | grep -c "limit_conn              moj_media\|moj-breaker-contest")" == 1 ]] && sed -n "/^location @moj_media {/,/^}/p" "$TPL" | grep -q "limit_conn              moj_media"'

if ! command -v nginx >/dev/null 2>&1; then
  echo "  (nginx ausente — pulando o teste de servidor)"
  echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
fi

echo "== nginx de teste =="
T="$(mktemp -d)"; PORT=$(( 20000 + RANDOM % 20000 ))
trap 'nginx -p "$T" -c "$T/nginx.conf" -s stop >/dev/null 2>&1; rm -rf "$T"' EXIT
mkdir -p "$T/logs" "$T/run" "$T/wr/run" "$T/wr/contests/prova-x/users/time1" "$T/wr/contests/prova-x/users/time2" \
         "$T/wr/contests/prova-x/users/.removed-users/velho" "$T/wr/contests/outra/users/t9" "$T/wr/segredo" \
         "$T/wr/contests/prova-x/users/legado" "$T/wr/contests/prova-x/users/dupla" "$T/wr/contests/prova-x/users/semthumb" \
         "$T/wr/contests/custom/users/c1" "$T/wr/contests/sothumb/users/s1" "$T/wr/contests/semconf/users/x"
for c in prova-x outra custom sothumb; do printf 'CONTEST_NAME=%s\n' "$c" > "$T/wr/contests/$c/conf"; done
printf 'RIFF0000WEBPpadrao-custom'       > "$T/wr/contests/custom/placeholder.webp"
printf 'RIFF0000WEBPpadrao-custom-thumb' > "$T/wr/contests/custom/placeholder.thumb.webp"
printf 'ID3padrao-custom-musica'         > "$T/wr/contests/custom/placeholder.mp3"
printf 'RIFF0000WEBPpadrao-sothumb'      > "$T/wr/contests/sothumb/placeholder.webp"
FAB="$ROOT/server/etc"
ln -s "$ROOT" "$T/wr/cdmoj"
printf '\x89PNG\r\n\x1a\nbrasao-time1' > "$T/wr/contests/prova-x/users/time1/logo.png"
printf '\x89PNG\r\n\x1a\nvelho'        > "$T/wr/contests/prova-x/users/.removed-users/velho/logo.png"
printf '\x89PNG\r\n\x1a\nt9'           > "$T/wr/contests/outra/users/t9/logo.png"
printf 'SEGREDO\n'                     > "$T/wr/segredo/logo.png"
U="$T/wr/contests/prova-x/users"
printf 'RIFF0000WEBPfoto-time1'        > "$U/time1/photo.webp"
printf 'RIFF0000WEBPthumb-time1'       > "$U/time1/photo.thumb.webp"
printf '\x89PNG\r\n\x1a\nfoto-legado'  > "$U/legado/photo.png"
printf 'RIFF0000WEBPfoto-dupla'        > "$U/dupla/photo.webp"
printf '\x89PNG\r\n\x1a\nresiduo-dupla' > "$U/dupla/photo.png"
printf 'RIFF0000WEBPfoto-semthumb'     > "$U/semthumb/photo.webp"
printf 'ID3musica-do-time1-0123456789' > "$U/time1/music.mp3"
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
$(blk "$E/moj-prod.conf.in" | sed "s#@WORKROOT@#$T/wr#g")
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
same(){ cmp -s "$T/b" "$1"; }      # o corpo é EXATAMENTE este arquivo (binário: compara o arquivo, não a variável)
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

echo "== a foto sai do disco =="
P='/api/v1/contest/team-photo'
req moj.test "$P?contest=prova-x&user=time1"
ck "foto: o photo.webp, image/webp, sem bash"           '[[ "$S" == 200 && "$B" == *foto-time1 && "$(hd Content-Type)" == image/webp ]]'
ck "foto sem v: 1 min (o telão externo busca sem v)"    '[[ "$(hd Cache-Control)" == "public, max-age=60" && -n "$(hd ETag)" ]]'
ET="$(hd ETag)"; req moj.test "$P?contest=prova-x&user=time1" -H "If-None-Match: $ET"
ck "foto: If-None-Match → 304"                          '[[ "$S" == 304 && -z "$B" ]]'
req moj.test "$P?contest=prova-x&user=time1&thumb=1"
ck "miniatura: a photo.thumb.webp, 1 dia"               '[[ "$S" == 200 && "$B" == *thumb-time1 && "$(hd Cache-Control)" == "public, max-age=86400" ]]'
req moj.test "$P?contest=prova-x&user=time1&thumb=0"
ck "thumb=0 também é miniatura (a regra do bash: não vazio)" '[[ "$B" == *thumb-time1 ]]'
req moj.test "$P?contest=prova-x&user=time1&thumb=&v=9"
ck "thumb vazio = a foto; com v: imutável"              '[[ "$B" == *foto-time1 && "$(hd Cache-Control)" == "public, max-age=31536000, immutable" ]]'
req moj.test "$P?contest=prova-x&user=time1&thumb=1&v=9"
ck "miniatura com v: imutável"                          '[[ "$B" == *thumb-time1 && "$(hd Cache-Control)" == "public, max-age=31536000, immutable" ]]'
req moj.test "$P?contest=prova-x&user=legado"
ck "só o photo.png legado: ele, image/png"              '[[ "$S" == 200 && "$B" == *foto-legado && "$(hd Content-Type)" == image/png ]]'
req moj.test "$P?contest=prova-x&user=dupla"
ck "webp e png juntos: o webp (a ordem do tp_file)"     '[[ "$B" == *foto-dupla ]]'
req prova-x.moj.test "$P?contest=prova-x&user=time1&thumb=1"
ck "no subdomínio DO contest: do disco"                 '[[ "$S" == 200 && "$B" == *thumb-time1 ]]'
fellp(){ req "$1" "$2"; [[ "$S" == 200 && "$B" == "bash-media $P?"* ]]; }
ck "miniatura que falta: bash (ele a gera)"             'fellp moj.test "$P?contest=prova-x&user=semthumb&thumb=1"'
ck "…e nunca a foto grande no lugar dela"               '[[ "$B" != *foto-semthumb ]]'
ck "miniatura do png legado (não existe): bash"         'fellp moj.test "$P?contest=prova-x&user=legado&thumb=1"'
ck "subdomínio de OUTRO contest: bash"                  'fellp outra.moj.test "$P?contest=prova-x&user=time1"'
ck "login com ponto no começo: bash"                    'fellp moj.test "$P?contest=prova-x&user=.removed-users"'
ck "barra codificada: bash"                             'fellp moj.test "$P?contest=prova-x&user=..%2Ftime1&thumb=1"'

echo "== a música sai do disco =="
M='/api/v1/contest/team-music'
req moj.test "$M?contest=prova-x&user=time1"
ck "música: o music.mp3, audio/mpeg, Content-Length"    '[[ "$S" == 200 && "$B" == ID3musica-do-time1-0123456789 && "$(hd Content-Type)" == audio/mpeg && "$(hd Content-Length)" == 29 ]]'
ck "música sem v: 1 min (o telão externo busca sem v)"  '[[ "$(hd Cache-Control)" == "public, max-age=60" && -n "$(hd ETag)" ]]'
ET="$(hd ETag)"; req moj.test "$M?contest=prova-x&user=time1" -H "If-None-Match: $ET"
ck "música: If-None-Match → 304"                        '[[ "$S" == 304 && -z "$B" ]]'
req moj.test "$M?contest=prova-x&user=time1" -H "Range: bytes=3-8"
ck "música: Range → 206 com o pedaço"                   '[[ "$S" == 206 && "$B" == musica && "$(hd Content-Range)" == "bytes 3-8/29" ]]'
req moj.test "$M?contest=prova-x&user=time1&v=77"
ck "música com v: imutável"                             '[[ "$S" == 200 && "$(hd Cache-Control)" == "public, max-age=31536000, immutable" ]]'
req prova-x.moj.test "$M?contest=prova-x&user=time1"
ck "no subdomínio DO contest: do disco"                 '[[ "$S" == 200 && "$B" == ID3musica* ]]'
fellm(){ req "$1" "$2"; [[ "$S" == 200 && "$B" == "bash-media $M?"* ]]; }
ck "subdomínio de OUTRO contest: bash"                  'fellm outra.moj.test "$M?contest=prova-x&user=time1"'
ck "login com hífen no começo: bash"                    'fellm moj.test "$M?contest=prova-x&user=-time1"'

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

echo "== o PADRÃO sai do disco (time sem foto/música e a rota) =="
req moj.test "$P?contest=prova-x&user=time2"
ck "time sem foto: a de FÁBRICA, com X-MOJ-Photo, 1 min" '[[ "$S" == 200 ]] && same "$FAB/team-placeholder.webp" && [[ "$(hd X-MOJ-Photo)" == placeholder && -z "$(hd X-MOJ-Music)" && "$(hd Cache-Control)" == "public, max-age=60" && "$(hd Content-Type)" == image/webp ]]'
req moj.test "$P?contest=prova-x&user=time2&thumb=1&v=5"
ck "…a miniatura de fábrica; com v segue 1 min (o padrão troca)" 'same "$FAB/team-placeholder.thumb.webp" && [[ "$(hd Cache-Control)" == "public, max-age=60" ]]'
req moj.test "$P?contest=prova-x&user=ninguem"
ck "login que não existe: o padrão (como o bash)"       'same "$FAB/team-placeholder.webp"'
req moj.test "$P?contest=custom&user=c1&thumb=1"
ck "padrão do CONTEST vence o de fábrica (miniatura)"   '[[ "$B" == *padrao-custom-thumb && "$(hd X-MOJ-Photo)" == placeholder ]]'
req moj.test "$P?contest=sothumb&user=s1&thumb=1"
ck "contest só com o padrão grande: ele no lugar da miniatura" '[[ "$B" == *padrao-sothumb ]]'
req moj.test "$P?contest=prova-x&user=time1"
ck "foto do time NÃO leva X-MOJ-Photo"                  '[[ "$B" == *foto-time1 && -z "$(hd X-MOJ-Photo)" ]]'
ck "miniatura de quem TEM foto: bash, nunca o padrão"   'fellp moj.test "$P?contest=prova-x&user=semthumb&thumb=1" && fellp moj.test "$P?contest=prova-x&user=legado&thumb=1"'
ck "contest sem conf: bash (o 404 de sempre)"           'fellp moj.test "$P?contest=semconf&user=x"'
ck "contest que não existe: bash"                       'fellp moj.test "$P?contest=naoexiste&user=x"'
ck "contest com .. no meio: bash (o valid_id)"          'fellp moj.test "$P?contest=prova..x&user=x"'
ck "user com .. no meio: bash"                          'fellp moj.test "$P?contest=prova-x&user=a..b"'
ck "sem o user: bash (400)"                             'fellp moj.test "$P?contest=prova-x"'
req moj.test "$M?contest=prova-x&user=time2"
ck "time sem música: a de FÁBRICA, com X-MOJ-Music"     '[[ "$S" == 200 ]] && same "$FAB/team-placeholder.mp3" && [[ "$(hd X-MOJ-Music)" == placeholder && -z "$(hd X-MOJ-Photo)" && "$(hd Content-Type)" == audio/mpeg && "$(hd Cache-Control)" == "public, max-age=60" ]]'
req moj.test "$M?contest=prova-x&user=time2" -H "Range: bytes=0-3"
ck "…com Range (206)"                                   '[[ "$S" == 206 ]]'
req moj.test "$M?contest=custom&user=c1"
ck "música padrão do CONTEST"                           '[[ "$B" == ID3padrao-custom-musica && "$(hd X-MOJ-Music)" == placeholder ]]'
ck "música: contest sem conf = bash"                    'fellm moj.test "$M?contest=semconf&user=x"'
H0='/api/v1/contest/placeholder'
fellh(){ req "$1" "$2"; [[ "$S" == 200 && "$B" == "bash-media $H0?"* ]]; }
req moj.test "$H0?contest=prova-x"
ck "rota do padrão: a foto de fábrica, X-MOJ-Photo"     'same "$FAB/team-placeholder.webp" && [[ "$(hd X-MOJ-Photo)" == placeholder && "$(hd Cache-Control)" == "public, max-age=60" ]]'
ET="$(hd ETag)"; req moj.test "$H0?contest=prova-x" -H "If-None-Match: $ET"
ck "…e 304 com ETag"                                    '[[ "$S" == 304 ]]'
req moj.test "$H0?contest=prova-x&thumb=1"
ck "rota: miniatura de fábrica"                         'same "$FAB/team-placeholder.thumb.webp"'
req moj.test "$H0?contest=prova-x&kind=music&thumb=1"
ck "rota: kind=music = a música (thumb não importa)"    'same "$FAB/team-placeholder.mp3" && [[ "$(hd X-MOJ-Music)" == placeholder && -z "$(hd X-MOJ-Photo)" ]]'
req moj.test "$H0?contest=prova-x&kind=foto"
ck "rota: kind desconhecido = a foto (como o bash)"     'same "$FAB/team-placeholder.webp"'
req moj.test "$H0?contest=custom&kind=photo&thumb=1"
ck "rota: o padrão do CONTEST"                          '[[ "$B" == *padrao-custom-thumb ]]'
req custom.moj.test "$H0?contest=custom"
ck "rota no subdomínio DO contest: do disco"            '[[ "$B" == *padrao-custom ]]'
ck "rota: kind codificado (mu%73ic) = bash decide"      'fellh moj.test "$H0?contest=prova-x&kind=mu%73ic"'
ck "rota: kind com pipe cru = bash"                     'fellh moj.test "$H0?contest=prova-x&kind=a|b"'
ck "rota: contest sem conf / inexistente = bash"        'fellh moj.test "$H0?contest=semconf" && fellh moj.test "$H0?contest=naoexiste"'
ck "rota: sem o contest = bash (400)"                   'fellh moj.test "$H0?kind=music"'
ck "rota: subdomínio de OUTRO contest = bash"           'fellh outra.moj.test "$H0?contest=custom"'
req moj.test "/api/v1/contest/team-photos?contest=prova-x"
ck "rota vizinha (team-photos) segue na /api/v1/ geral"  '[[ "$B" == bash-geral* ]]'
req moj.test "/api/v1/contest/score?contest=prova-x"
ck "o resto da API segue na /api/v1/ geral"             '[[ "$B" == bash-geral* ]]'

echo "== freio do treino (moj-shed-treino) =="
touch "$T/shed"
req moj.test "$L?contest=prova-x&user=time2"
ck "site principal: mídia que cai no bash → 503"        '[[ "$S" == 503 ]]'
req moj.test "$H0?contest=semconf"
ck "…inclusive o padrão que cai no bash"                '[[ "$S" == 503 ]]'
req prova-x.moj.test "$L?contest=prova-x&user=time2"
ck "subdomínio de contest: não olha o freio"            '[[ "$S" == 200 && "$B" == bash-media* ]]'
req moj.test "$H0?contest=prova-x"
ck "o padrão do disco não passa pelo bash: segue 200"   '[[ "$S" == 200 ]] && same "$FAB/team-placeholder.webp"'
req moj.test "$L?contest=prova-x&user=time1"
ck "o brasão do disco não passa pelo bash: segue 200"   '[[ "$S" == 200 && "$B" == *brasao-time1 ]]'
req moj.test "/api/v1/contest/team-photo?contest=prova-x&user=time1&thumb=1"
ck "…nem a foto do disco"                               '[[ "$S" == 200 && "$B" == *thumb-time1 ]]'
req moj.test "/api/v1/contest/team-music?contest=prova-x&user=time1"
ck "…nem a música do disco"                             '[[ "$S" == 200 && "$B" == ID3musica* ]]'
rm -f "$T/shed"

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
