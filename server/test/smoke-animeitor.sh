#!/bin/bash
# Papel .animeitor (mesa do telão): não submete; placar SEMPRE descongelado; estatísticas;
# fora do placar/times/etiquetas; fotos dos times em WEBP e MÚSICAS em MP3 (galeria, upload,
# remoção, padrão de fábrica, pacote .zip); e o WEBCAST — chaves por visão de coorte e a rota
# SEM SESSÃO que devolve o pacote no formato do BOCA (contest/runs/time/version/icpc, campos
# separados por 0x1C).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; TMP="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS" "$TMP"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"

NOW="$EPOCHSECONDS"; START=$(( NOW - 7200 )); FREEZE=$(( NOW - 3600 )); END=$(( NOW + 3600 ))
C="$FIX/an"; mkdir -p "$C/var"
{ printf 'CONTEST_ID=an\nCONTEST_TYPE=icpc\nCONTEST_NAME=Prova\\ Animeitor\n'
  printf 'CONTEST_START=%s\nCONTEST_END=%s\nFREEZE_TIME=%s\nPENALTY_MINUTES=20\n' "$START" "$END" "$FREEZE"
  printf "PROBS=( x col#pa Alfa A col#pa x col#pb Beta B col#pb )\n"; } > "$C/conf"
fx_user "$C" an.admin p "Admin"
fx_user "$C" telao.animeitor p "Mesa do Telão"
fx_user "$C" an.staff p "Staff"
fx_user "$C" norte.cstaff p "Chefe de Sede Norte"
fx_user "$C" time-a a "Time Alfa"
fx_user "$C" time-b b "Time Beta"
jq -c '.team={name:"Time Alfa",univ_short:"UFRJ",flag:"br-rj",region:"Norte"}' "$C/users/time-a/account.json" > "$C/t" && mv "$C/t" "$C/users/time-a/account.json"
jq -c '.team={name:"Time Beta",univ_short:"UFSC",flag:"br-sc",region:"Sul"}' "$C/users/time-b/account.json" > "$C/t" && mv "$C/t" "$C/users/time-b/account.json"
# escopo do chefe de sede pelo token `region:` (o mesmo staff-filters da fila/etiquetas/cerimônia)
mkdir -p "$C/print-requests"
printf '%s' '{"norte.cstaff":["region:Norte"]}' > "$C/print-requests/staff-filters.json"

# time-a: AC pré-freeze em A + AC PÓS-freeze em B (o pós só aparece no placar descongelado)
{ printf '10:col#pa:C:Accepted,100p:%s:s1\n' $(( START + 600 ))
  printf '70:col#pb:C:Accepted,100p:%s:s2\n' $(( FREEZE + 60 )); } > "$C/users/time-a/history"
# time-b: um de cada veredicto que o webcast tem de mapear (N / X / ? )
{ printf '15:col#pa:C:Wrong,60p. Pontos | 30 | 0 |:%s:s3\n' $(( START + 900 ))
  printf '20:col#pa:C:Compilation Error:%s:s4\n' $(( START + 1200 ))
  printf '25:col#pb:C:Not Answered Yet:%s:s5\n' $(( START + 1500 )); } > "$C/users/time-b/history"
# conta de PAPEL com history: não pode virar time no placar
printf '5:col#pa:C:Accepted,100p:%s:s9\n' $(( START + 300 )) > "$C/users/telao.animeitor/history"
touch "$C/var/.score-dirty"

mktok(){ printf 'CONTEST=%q\nLOGIN=%q\nUSERFULLNAME=%q\nLOGINAT=%q\n' an "$1" "$1" "$NOW" > "$SESS/$2"; }
mktok an.admin adm; mktok telao.animeitor ani; mktok an.staff stf; mktok time-b tb
mktok norte.cstaff cst

call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="${2:-GET}" QUERY_STRING="${4:-}" \
    HTTP_AUTHORIZATION="${3:+Bearer $3}" REMOTE_ADDR=127.0.0.9 \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SCOREDIR="$ROOT/score" bash "$ROUTER" <<<"${5:-}" 2>/dev/null)"
  HEAD="$(printf '%s' "$OUT" | awk '{print} /^\r?$/{exit}')"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
# separa o corpo BINÁRIO do cabeçalho CGI (binário: nada de sed/grep no meio do zip)
unhead(){ python3 -c 'import sys
d=open(sys.argv[1],"rb").read(); i=d.index(b"\r\n\r\n")+4
open(sys.argv[2],"wb").write(d[i:])' "$1" "$2"; }
# ⚠ a captura vai por PIPE (`| cat > arquivo`), não por redirecionamento direto: com stdout em
# ARQUIVO o bash bufferiza os printf do cabeçalho e o `zip`/`tar` filho escreve ANTES deles — o
# corpo sai embaralhado. Em produção o stdout é o pipe do fcgiwrap, que é o que isto imita.
callf(){ PATH_INFO="$1" REQUEST_METHOD="${2:-GET}" QUERY_STRING="${4:-}" \
    HTTP_AUTHORIZATION="${3:+Bearer $3}" REMOTE_ADDR=127.0.0.9 \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" SCOREDIR="$ROOT/score" bash "$ROUTER" <<<"${5:-}" 2>/dev/null \
    | cat > "$6"; }
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

echo "== papel: não submete, vê tudo que é de placar =="
call /submit POST ani 'contest=an' '{"problem":"col#pa","lang":"c","source":"aW50IG1haW4oKXt9"}'
ck "animeitor: submit 403"        'grep -q "submit_forbidden" <<<"$BODY"'
call /contest/offline-submit POST ani 'contest=an' '{"packets":[]}'
ck "animeitor: offline-submit 403" 'grep -q "submit_forbidden" <<<"$BODY"'
call /contest/score GET ani 'contest=an'
ck "placar DESCONGELADO p/ animeitor" 'grep -q ":time-a:" <<<"$BODY" && grep -qE "1/(6[0-9]|[0-9]{2,3})" <<<"$BODY"'
ANI_BOARD="$BODY"
call /contest/score GET tb 'contest=an'
ck "usuário comum recebe congelado"   '[[ "$BODY" != "$ANI_BOARD" ]]'
call /contest/score GET ani 'contest=an&view=public'
ck "view=public força congelado"      '[[ "$BODY" != "$ANI_BOARD" ]]'
call /contest/statistics GET ani 'contest=an'
ck "estatísticas liberadas"           'grep -q "\"totals\"" <<<"$BODY"'
call /contest/navbuttons GET ani 'contest=an'
ck "navbuttons próprios"              'grep -q "/contest/animeitor/" <<<"$BODY" && ! grep -q "Clarification" <<<"$BODY"'
call /auth/status GET ani 'contest=an'
ck "auth/status: is_animeitor"        'grep -q "\"is_animeitor\":true" <<<"$BODY"'

echo "== não é competidor =="
ck "fora do placar"                   '! grep -q "telao.animeitor" <<<"$ANI_BOARD"'
call /contest/teams GET ani 'contest=an'
ck "fora do diretório de times"       '! grep -q "telao.animeitor" <<<"$BODY"'
call /contest/badges GET adm 'contest=an'
ck "fora das etiquetas"               '! grep -q "telao.animeitor" <<<"$BODY"'

echo "== fotos (webp) =="
# PNG de 1x1 (o servidor converte p/ webp)
PNG1='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
call /contest/animeitor/photo POST ani 'contest=an' "{\"login\":\"time-a\",\"file_b64\":\"$PNG1\"}"
ck "upload grava WEBP"      'grep -q "\"saved\":true" <<<"$BODY" && [[ -s "$C/users/time-a/photo.webp" ]] && [[ ! -e "$C/users/time-a/photo.png" ]]'
ck "arquivo é webp de fato" '[[ "$(file --mime-type -b "$C/users/time-a/photo.webp")" == image/webp ]]'
callf /contest/team-photo GET '' 'contest=an&user=time-a' '' "$TMP/p1.bin"
ck "team-photo serve image/webp" 'head -c 120 "$TMP/p1.bin" | grep -q "Content-Type: image/webp"'
# legado: um photo.png que NÃO passou pela conversão continua servido
printf '%s' "$PNG1" | base64 -d > "$C/users/time-b/photo.png"
callf /contest/team-photo GET '' 'contest=an&user=time-b' '' "$TMP/p2.bin"
ck "legado png ainda servido"    'head -c 120 "$TMP/p2.bin" | grep -q "Content-Type: image/png"'
call /contest/animeitor/photos GET ani 'contest=an'
ck "galeria conta as duas"       'grep -q "\"with_photo\":2" <<<"$BODY" && grep -q "\"format\":\"webp\"" <<<"$BODY"'
ck "galeria não lista papel"     '! grep -q "telao.animeitor" <<<"$BODY"'
# a galeria é a tela de 1000+ times: precisa do mtime (cache-buster do <img>) e da sede/coorte
ck "galeria traz mtime e sede"   'grep -qE "\"mtime\":[0-9]{6}" <<<"$BODY" && grep -q "\"region\":" <<<"$BODY" && grep -q "\"cohort\":" <<<"$BODY"'
ck "galeria: 1 item por time"    '[[ "$(jq -r ".teams|length" <<<"$BODY")" == "$(jq -r .total <<<"$BODY")" ]]'

echo "== miniatura (a galeria não baixa a foto de 1000px) =="
ck "miniatura nasce no upload"   '[[ -s "$C/users/time-a/photo.thumb.webp" ]]'
ck "miniatura é MENOR que a foto" '[[ "$(stat -c %s "$C/users/time-a/photo.thumb.webp")" -le "$(stat -c %s "$C/users/time-a/photo.webp")" ]]'
callf /contest/team-photo GET '' 'contest=an&user=time-a&thumb=1' '' "$TMP/p3.bin"
ck "thumb=1 serve image/webp"    'head -c 160 "$TMP/p3.bin" | grep -q "Content-Type: image/webp" && head -c 160 "$TMP/p3.bin" | grep -q "max-age=86400"'
rm -f "$C/users/time-b/photo.thumb.webp"
callf /contest/team-photo GET '' 'contest=an&user=time-b&thumb=1' '' "$TMP/p4.bin"
ck "legado gera miniatura na 1ª leitura" '[[ -s "$C/users/time-b/photo.thumb.webp" ]]'
ck "sem thumb continua a foto cheia" 'true'  # coberto acima (image/webp + max-age=60)
callf /contest/animeitor/photos-zip GET ani 'contest=an' '' "$TMP/fotos.bin"
unhead "$TMP/fotos.bin" "$TMP/fotos.zip"
ck "pacote tem fotos/<login> + índice" 'unzip -Z1 "$TMP/fotos.zip" 2>/dev/null | grep -q "fotos/time-a.webp" && unzip -Z1 "$TMP/fotos.zip" | grep -q "teams.csv"'
ck "pacote NÃO leva miniatura"   '! unzip -Z1 "$TMP/fotos.zip" 2>/dev/null | grep -q "thumb"'
ck "índice casa foto e time"     'unzip -p "$TMP/fotos.zip" teams.csv | grep -q "\"time-a\",\"Time Alfa\",\"UFRJ\",\"\",\"br-rj\",\"time-a.webp\""'
call /contest/animeitor/photo POST ani 'contest=an' '{"action":"delete","login":"time-a"}'
ck "remoção apaga foto e miniatura" '[[ ! -e "$C/users/time-a/photo.webp" && ! -e "$C/users/time-a/photo.thumb.webp" ]]'

echo "== foto PADRÃO (time sem foto não dá mais 404) =="
# neste ponto do fixture: time-a SEM foto (removida acima) e time-b com o photo.png legado
callf /contest/team-photo GET '' 'contest=an&user=time-a' '' "$TMP/np.bin"
ck "sem foto → 200 com a padrão" 'head -c 200 "$TMP/np.bin" | grep -q "Status: 200" && head -c 200 "$TMP/np.bin" | grep -q "X-MOJ-Photo: placeholder"'
callf /contest/team-photo GET '' 'contest=an&user=time-a&thumb=1' '' "$TMP/npt.bin"
ck "padrão também em miniatura"  'head -c 200 "$TMP/npt.bin" | grep -q "X-MOJ-Photo: placeholder" && [[ "$(stat -c %s "$TMP/npt.bin")" -lt "$(stat -c %s "$TMP/np.bin")" ]]'
callf /contest/team-photo GET '' 'contest=an&user=time-b' '' "$TMP/nb.bin"
ck "quem TEM foto não recebe padrão" '! head -c 200 "$TMP/nb.bin" | grep -q "X-MOJ-Photo"'
callf /contest/placeholder GET '' 'contest=an' '' "$TMP/ph.bin"
ck "/contest/placeholder é público" 'head -c 200 "$TMP/ph.bin" | grep -q "Content-Type: image/webp"'
call /contest/animeitor/placeholder GET ani 'contest=an'
ck "GET diz que é a de fábrica"  'grep -q "\"custom\":false" <<<"$BODY"'
call /contest/animeitor/placeholder POST ani 'contest=an' "{\"file_b64\":\"$PNG1\"}"
ck "troca a padrão do contest"   'grep -q "\"custom\":true" <<<"$BODY" && [[ -s "$C/placeholder.webp" && -s "$C/placeholder.thumb.webp" ]]'
callf /contest/team-photo GET '' 'contest=an&user=time-a' '' "$TMP/np2.bin"
ck "quem não tem foto já recebe a nova" '[[ "$(stat -c %s "$TMP/np2.bin")" != "$(stat -c %s "$TMP/np.bin")" ]]'
call /contest/animeitor/photos GET ani 'contest=an'
ck "listagem informa a padrão"   'grep -q "\"placeholder\":{\"custom\":true" <<<"$BODY"'
ck "has_photo NÃO vira true"     '[[ "$(jq -r ".teams[]|select(.login==\"time-a\")|.has_photo" <<<"$BODY")" == false ]]'
call /contest/animeitor/placeholder POST ani 'contest=an' '{"action":"reset"}'
ck "reset volta à de fábrica"    'grep -q "\"custom\":false" <<<"$BODY" && [[ ! -e "$C/placeholder.webp" && ! -e "$C/placeholder.thumb.webp" ]]'
call /contest/animeitor/placeholder GET tb 'contest=an'
ck "competidor não gere a padrão" 'grep -q "animeitor_required" <<<"$BODY"'

echo "== música do time (mp3) =="
# MP3 mínimo de verdade (8 quadros MPEG1 layer III): o servidor valida pelo MIME, não pela
# extensão — é o que impede um .mp3 que na verdade é outra coisa de entrar no telão.
{ for _i in 1 2 3 4 5 6 7 8; do printf '\xff\xfb\x90\x00'; head -c 413 /dev/zero; done; } > "$TMP/tiny.mp3"
MP3="$(base64 -w0 "$TMP/tiny.mp3")"
call /contest/animeitor/music POST ani 'contest=an' "{\"login\":\"time-a\",\"file_b64\":\"$MP3\"}"
ck "upload grava music.mp3"      'grep -q "\"saved\":true" <<<"$BODY" && [[ -s "$C/users/time-a/music.mp3" ]]'
ck "arquivo é audio/mpeg"        '[[ "$(file --mime-type -b "$C/users/time-a/music.mp3")" == audio/mpeg ]]'
call /contest/animeitor/music POST ani 'contest=an' "{\"login\":\"time-b\",\"file_b64\":\"$PNG1\"}"
ck "não-mp3 é RECUSADO"          'grep -q "music_bad" <<<"$BODY" && [[ ! -e "$C/users/time-b/music.mp3" ]]'
call /contest/animeitor/music POST ani 'contest=an' "{\"login\":\"telao.animeitor\",\"file_b64\":\"$MP3\"}"
ck "conta de papel não tem música" 'grep -q "role_account" <<<"$BODY"'
callf /contest/team-music GET '' 'contest=an&user=time-a' '' "$TMP/m1.bin"
ck "team-music serve audio/mpeg"  'head -c 200 "$TMP/m1.bin" | grep -q "Content-Type: audio/mpeg" && head -c 200 "$TMP/m1.bin" | grep -q "Content-Length: 3336"'
ck "quem TEM música não leva padrão" '! head -c 200 "$TMP/m1.bin" | grep -q "X-MOJ-Music"'
callf /contest/team-music GET '' 'contest=an&user=time-b' '' "$TMP/m2.bin"
ck "sem música → 200 com a padrão" 'head -c 200 "$TMP/m2.bin" | grep -q "Status: 200" && head -c 200 "$TMP/m2.bin" | grep -q "X-MOJ-Music: placeholder"'
call /contest/animeitor/photos GET ani 'contest=an'
ck "galeria conta a música"      '[[ "$(jq -r .with_music <<<"$BODY")" == 1 ]]'
ck "galeria traz has_music/bytes" '[[ "$(jq -r ".teams[]|select(.login==\"time-a\")|.has_music" <<<"$BODY")" == true ]] && [[ "$(jq -r ".teams[]|select(.login==\"time-a\")|.music_bytes" <<<"$BODY")" == 3336 ]]'
ck "quem não tem: has_music false" '[[ "$(jq -r ".teams[]|select(.login==\"time-b\")|.has_music" <<<"$BODY")" == false ]]'

echo "== música PADRÃO =="
callf /contest/placeholder GET '' 'contest=an&kind=music' '' "$TMP/phm.bin"
ck "placeholder?kind=music público" 'head -c 200 "$TMP/phm.bin" | grep -q "Content-Type: audio/mpeg"'
call /contest/animeitor/placeholder GET ani 'contest=an'
ck "GET traz foto E música"      '[[ "$(jq -r .custom <<<"$BODY")" == false ]] && [[ "$(jq -r .music.custom <<<"$BODY")" == false ]] && [[ "$(jq -r .music.bytes <<<"$BODY")" -gt 0 ]]'
call /contest/animeitor/placeholder POST ani 'contest=an' "{\"kind\":\"music\",\"file_b64\":\"$MP3\"}"
ck "troca a música padrão"       '[[ "$(jq -r .music.custom <<<"$BODY")" == true ]] && [[ -s "$C/placeholder.mp3" ]]'
ck "trocar música não mexe na foto" '[[ "$(jq -r .custom <<<"$BODY")" == false ]] && [[ ! -e "$C/placeholder.webp" ]]'
call /contest/animeitor/placeholder POST ani 'contest=an' "{\"kind\":\"music\",\"file_b64\":\"$PNG1\"}"
ck "padrão: não-mp3 recusado"    'grep -q "music_bad" <<<"$BODY"'
callf /contest/team-music GET '' 'contest=an&user=time-b' '' "$TMP/m3.bin"
ck "quem não tem já recebe a nova" '[[ "$(stat -c %s "$TMP/m3.bin")" != "$(stat -c %s "$TMP/m2.bin")" ]]'
call /contest/animeitor/placeholder POST ani 'contest=an' '{"kind":"music","action":"reset"}'
ck "reset volta à de fábrica"    '[[ "$(jq -r .music.custom <<<"$BODY")" == false ]] && [[ ! -e "$C/placeholder.mp3" ]]'
call /contest/animeitor/placeholder POST ani 'contest=an' '{"kind":"video"}'
ck "kind inválido → 422"         'grep -q "kind_invalid" <<<"$BODY"'
call /contest/animeitor/music POST tb 'contest=an' "{\"login\":\"time-b\",\"file_b64\":\"$MP3\"}"
ck "competidor: 403 na música"   'grep -q "animeitor_required" <<<"$BODY"'
# o envio em LOTE manda o nome do arquivo como login (fulano.mp3 -> fulano)
call /contest/animeitor/music POST ani 'contest=an' "{\"login\":\"Time-A.MP3\",\"file_b64\":\"$MP3\"}"
ck "lote: nome do arquivo vira login" 'grep -q "\"login\":\"time-a\"" <<<"$BODY"'

echo "== pacote: todo time tem arquivo =="
callf /contest/animeitor/photos-zip GET ani 'contest=an' '' "$TMP/f2.bin"
unhead "$TMP/f2.bin" "$TMP/f2.zip"
ck "padrão na raiz do pacote"    'unzip -Z1 "$TMP/f2.zip" 2>/dev/null | grep -qx "placeholder.webp"'
ck "time SEM foto tem arquivo"   'unzip -Z1 "$TMP/f2.zip" | grep -q "fotos/time-a.webp"'
ck "time COM foto mantém a dele" 'unzip -Z1 "$TMP/f2.zip" | grep -q "fotos/time-b.png"'
ck "CSV marca padrao=true"       'unzip -p "$TMP/f2.zip" teams.csv | grep -q "^\"time-a\",.*,\"time-a.webp\",true,"'
ck "CSV marca padrao=false"      'unzip -p "$TMP/f2.zip" teams.csv | grep -q "^\"time-b\",.*,\"time-b.png\",false,"'
# MÚSICA no pacote: só quem mandou a sua (a padrão vai UMA vez na raiz — copiar 5 MB por time
# daria pacote de gigabytes numa prova de 1000)
ck "música do time no pacote"    'unzip -Z1 "$TMP/f2.zip" | grep -q "musicas/time-a.mp3"'
ck "quem não tem música: SEM arquivo" '! unzip -Z1 "$TMP/f2.zip" | grep -q "musicas/time-b"'
ck "música padrão na raiz"       'unzip -Z1 "$TMP/f2.zip" | grep -qx "placeholder.mp3"'
ck "CSV: colunas de música"      'unzip -p "$TMP/f2.zip" teams.csv | head -1 | grep -q "musica,musica_padrao$"'
ck "CSV: quem tem música"        'unzip -p "$TMP/f2.zip" teams.csv | grep -q "\"time-a.mp3\",false$"'
ck "CSV: quem toca a padrão"     'unzip -p "$TMP/f2.zip" teams.csv | grep -q "^\"time-b\",.*,\"\",true$"'

echo "== webcast: chaves =="
call /contest/animeitor/webcast POST ani 'contest=an' '{"action":"create","view":"public","label":"telao"}'
KEY="$(jq -r '.key // empty' <<<"$BODY" 2>/dev/null)"
ck "cria chave mojwc_"           '[[ "$KEY" == mojwc_* ]]'
ck "webcast.json é 600"          '[[ "$(stat -c %a "$C/webcast.json")" == 600 ]]'
call /contest/animeitor/webcast POST ani 'contest=an' '{"action":"create","view":"nao-existe"}'
ck "visão inexistente → 422"     'grep -q "view_invalid" <<<"$BODY"'

echo "== webcast: o pacote (formato BOCA) =="
callf /contest/webcast GET '' "contest=an&key=$KEY" '' "$TMP/wc.bin"      # SEM Authorization
head -c 200 "$TMP/wc.bin" > "$TMP/wc.head"
ck "rota pública responde zip"   'grep -q "Content-Type: application/zip" "$TMP/wc.head"'
unhead "$TMP/wc.bin" "$TMP/wc.zip"
ck "5 arquivos do protocolo"     '[[ "$(unzip -Z1 "$TMP/wc.zip" 2>/dev/null | sort | tr "\n" " ")" == "contest icpc runs time version " ]]'
ck "version = 1.0"               '[[ "$(unzip -p "$TMP/wc.zip" version)" == "1.0" ]]'
ck "time é minuto inteiro"       '[[ "$(unzip -p "$TMP/wc.zip" time)" =~ ^[0-9]+$ ]]'
unzip -p "$TMP/wc.zip" contest > "$TMP/contest"
ck "contest: separador 0x1C"     '[[ "$(grep -c $'"'"'\x1c'"'"' "$TMP/contest")" -ge 4 ]]'
ck "contest: nome na 1ª linha"   '[[ "$(sed -n 1p "$TMP/contest")" == "Prova Animeitor" ]]'
L2_WANT=$'180\x1c180\x1c60\x1c20'      # duração 180 min, freeze aos 60, penalidade 20
ck "contest: duração/freeze/pen" '[[ "$(sed -n 2p "$TMP/contest")" == "$L2_WANT" ]]'
ck "contest: nTimes e nProblemas" '[[ "$(sed -n 3p "$TMP/contest")" == $'"'"'2\x1c2'"'"' ]]'
ck "contest: linha de time"      'grep -q $'"'"'^time-a\x1cUFRJ\x1cTime Alfa$'"'"' "$TMP/contest"'
ck "contest: rodapé 1/1 e nprob/Y" 'grep -q $'"'"'^1\x1c1$'"'"' "$TMP/contest" && grep -q $'"'"'^2\x1cY$'"'"' "$TMP/contest"'
unzip -p "$TMP/wc.zip" runs > "$TMP/runs"
ck "runs: AC pós-freeze VAI no pacote" 'grep -q $'"'"'\x1ctime-a\x1cB\x1cY$'"'"' "$TMP/runs"'
ck "runs: WA vira N"             'grep -q $'"'"'\x1ctime-b\x1cA\x1cN$'"'"' "$TMP/runs"'
ck "runs: CE vira X"             'grep -q $'"'"'\x1ctime-b\x1cA\x1cX$'"'"' "$TMP/runs"'
ck "runs: pendente vira ?"       'grep -q $'"'"'\x1ctime-b\x1cB\x1c?$'"'"' "$TMP/runs"'
ck "runs: id sequencial"         '[[ "$(cut -d$'"'"'\x1c'"'"' -f1 "$TMP/runs" | tr "\n" " ")" == "1 2 3 4 5 " ]]'
ck "runs: conta de papel fora"   '! grep -q "telao.animeitor" "$TMP/runs"'

echo "== webcast: gates =="
call /contest/webcast GET '' 'contest=an&key=mojwc_errada'
ck "chave errada → 404"          'grep -q "Status: 404" <<<"$OUT"'
ck "recusa vai p/ o log"         'grep -q "mojwc_errada" "$C/var/webcast-denied.log"'
ID="$(jq -r '.keys[0].id' "$C/webcast.json")"
call /contest/animeitor/webcast POST ani 'contest=an' "{\"action\":\"revoke\",\"id\":\"$ID\"}"
call /contest/webcast GET '' "contest=an&key=$KEY"
ck "chave revogada → 404"        'grep -q "Status: 404" <<<"$OUT"'
call /contest/animeitor/photos GET tb 'contest=an'
ck "competidor: 403 nas rotas"   'grep -q "animeitor_required" <<<"$BODY"'
call /contest/animeitor/webcast GET stf 'contest=an'
ck "staff: 403 nas rotas"        'grep -q "animeitor_required" <<<"$BODY"'
call /contest/animeitor/photos GET adm 'contest=an'
ck "admin também entra"          'grep -q "\"teams\"" <<<"$BODY"'

echo "== .cstaff: o telão RECORTADO na sede dele =="
# neste ponto: time-a (sede Norte) tem música e NÃO tem foto; time-b (sede Sul) tem photo.png
# legado e nenhuma música. O escopo do norte.cstaff é `region:Norte` ⇒ só time-a.
call /contest/animeitor/photos GET cst 'contest=an'
ck "cstaff entra na galeria"      'grep -q "\"teams\"" <<<"$BODY" && grep -q "\"scoped\":true" <<<"$BODY"'
ck "cstaff vê SÓ a sede dele"     '[[ "$(jq -r .total <<<"$BODY")" == 1 ]] && [[ "$(jq -r ".teams[0].login" <<<"$BODY")" == time-a ]]'
call /contest/animeitor/photos GET ani 'contest=an'
ck "animeitor segue vendo tudo"   '[[ "$(jq -r .total <<<"$BODY")" == 2 ]] && grep -q "\"scoped\":false" <<<"$BODY"'
call /contest/animeitor/photo POST cst 'contest=an' "{\"login\":\"time-a\",\"file_b64\":\"$PNG1\"}"
ck "cstaff sobe foto da sede"     'grep -q "\"saved\":true" <<<"$BODY" && [[ -s "$C/users/time-a/photo.webp" ]]'
call /contest/animeitor/photo POST cst 'contest=an' "{\"login\":\"time-b\",\"file_b64\":\"$PNG1\"}"
ck "foto fora da sede → 403"      'grep -q "staff_scope" <<<"$BODY"'
call /contest/animeitor/music POST cst 'contest=an' "{\"login\":\"time-b\",\"file_b64\":\"$MP3\"}"
ck "música fora da sede → 403"    'grep -q "staff_scope" <<<"$BODY" && [[ ! -e "$C/users/time-b/music.mp3" ]]'
call /contest/animeitor/music POST cst 'contest=an' '{"action":"delete","login":"time-b"}'
ck "delete fora da sede → 403"    'grep -q "staff_scope" <<<"$BODY"'
call /contest/animeitor/music POST cst 'contest=an' "{\"login\":\"time-a\",\"file_b64\":\"$MP3\"}"
ck "música da sede: pode"         'grep -q "\"saved\":true" <<<"$BODY"'
call /contest/animeitor/placeholder GET cst 'contest=an'
ck "cstaff VÊ o padrão"           'grep -q "\"custom\"" <<<"$BODY" && grep -q "\"music\"" <<<"$BODY"'
call /contest/animeitor/placeholder POST cst 'contest=an' "{\"file_b64\":\"$PNG1\"}"
ck "cstaff NÃO troca o padrão"    'grep -q "animeitor_required" <<<"$BODY" && [[ ! -e "$C/placeholder.webp" ]]'
call /contest/animeitor/webcast GET cst 'contest=an'
ck "cstaff não vê as chaves"      'grep -q "animeitor_required" <<<"$BODY"'
call /contest/animeitor/webcast POST cst 'contest=an' '{"action":"create","view":"public"}'
ck "cstaff não cria chave"        'grep -q "animeitor_required" <<<"$BODY"'
callf /contest/animeitor/photos-zip GET cst 'contest=an' '' "$TMP/f3.bin"
unhead "$TMP/f3.bin" "$TMP/f3.zip"
ck "pacote do cstaff: só a sede"  'unzip -Z1 "$TMP/f3.zip" | grep -q "fotos/time-a.webp" && ! unzip -Z1 "$TMP/f3.zip" | grep -q "time-b"'
ck "CSV do cstaff: 1 time"        '[[ "$(unzip -p "$TMP/f3.zip" teams.csv | tail -n +2 | wc -l)" == 1 ]]'
ck "pacote do cstaff leva padrão" 'unzip -Z1 "$TMP/f3.zip" | grep -qx "placeholder.webp"'
call /contest/navbuttons GET cst 'contest=an'
ck "cstaff tem botão do telão"    'grep -q "/contest/animeitor/" <<<"$BODY"'
call /contest/animeitor/photos GET stf 'contest=an'
ck ".staff puro continua fora"    'grep -q "animeitor_required" <<<"$BODY"'
# escopo que não casa NINGUÉM tem de dar ZERO (o rc do staff_visible_logins é que manda; tratar
# "lista vazia" como "sem filtro" abriria o contest inteiro ao chefe de sede)
printf '%s' '{"norte.cstaff":["region:Inexistente"]}' > "$C/print-requests/staff-filters.json"
call /contest/animeitor/photos GET cst 'contest=an'
ck "escopo sem casamento → zero" '[[ "$(jq -r .total <<<"$BODY")" == 0 ]] && grep -q "\"scoped\":true" <<<"$BODY"'
call /contest/animeitor/photo POST cst 'contest=an' "{\"login\":\"time-a\",\"file_b64\":\"$PNG1\"}"
ck "e nada de escrever nesse caso" 'grep -q "staff_scope" <<<"$BODY"'
printf '%s' '{"norte.cstaff":["region:Norte"]}' > "$C/print-requests/staff-filters.json"

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
