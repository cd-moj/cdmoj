#!/bin/bash
# Contest SUPER SECRETO (conf SECRET=1): fora das listagens públicas (home/arquivo/status),
# placar e visual (balloons/regions/teams-meta) exigem sessão DO contest; tela de login (basic)
# continua pública; settings marca/desmarca; export/mine preservam a visão do criador.
# E a MÍDIA DE TIME (team-photo/team-music/team-logo/placeholder) obedece ao mesmo gate — o que
# faltava aqui em 2026-08-24, quando a galeria do telão apareceu vazia num contest secreto: as 4
# rotas viram 401 e `<img src>`/`<audio src>` não mandam `Authorization` (o front passou a
# buscá-las com Bearer e virar blob:, ver web/shared/media-auth.js).
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
T="$FIX/treino"; mkdir -p "$T/var/jsons"
printf 'CONTEST_ID=treino\nCONTEST_TYPE=lista-publica\nUSER_STORE=v2\n' > "$T/conf"
fx_user "$T" boss.admin p "Boss"
fx_user "$T" regular s "Regular"
printf '{"threshold":0,"allow":["regular"],"deny":[]}' > "$T/var/contest-perms.json"
printf 'CONTEST=treino\nLOGIN=regular\nUSERFULLNAME=Regular\nLOGINAT=1\n' > "$SESS/reg"
printf '%s' '{"id":"bankprob","title":"Banco","tags":[],"statement_html_b64":"PGgxPm9pPC9oMT4="}' > "$T/var/jsons/bankprob.json"
printf '%s' '{"problems":[{"id":"bankprob","title":"Banco","owner":"x","collaborators":[],"public":true}]}' > "$T/var/problem-owners.json"
NOW="$(date +%s)"; FUT=$(( NOW + 100000 ))
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="${5:-}" HTTP_AUTHORIZATION="Bearer ${4:-}" \
    CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" bash "$ROUTER" <<<"${3:-}" 2>&1)"
  BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
# corpo BINÁRIO (webp/mp3/png) não passa por `$(…)`: o bash corta no NUL e ainda escreve
# "ignored null byte in input", que envenenaria o $OUT. Captura por PIPE (molde do callf do
# smoke-animeitor.sh) e olha só o CABEÇALHO.
callh(){ local f; f="$(mktemp)"; PATH_INFO="$1" REQUEST_METHOD=GET QUERY_STRING="${3:-}" \
    HTTP_AUTHORIZATION="Bearer ${2:-}" CONTESTSDIR="$FIX" SESSIONDIR="$SESS" RUNDIR="$FIX/run" \
    bash "$ROUTER" </dev/null 2>/dev/null | cat > "$f"
  OUT="$(head -c 400 "$f" | tr -d '\000')"; BODY=''; rm -f "$f"; }
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:200}"; ((fail++)); fi; }

# um contest SECRETO e um VISÍVEL (mesma janela aberta)
call /treino/contest-create/create POST "{\"id\":\"sec-c\",\"name\":\"Prova Secreta\",\"mode\":\"icpc\",\"secret\":true,\"start\":$((NOW-100)),\"end\":$FUT,\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"B\"}]}" reg
[[ "$(jq -r .contest_id <<<"$BODY")" == sec-c ]] || { echo "SETUP FAIL: $BODY"; exit 1; }
call /treino/contest-create/create POST "{\"id\":\"vis-c\",\"name\":\"Prova Visivel\",\"mode\":\"icpc\",\"start\":$((NOW-100)),\"end\":$FUT,\"problems\":[{\"bank_id\":\"bankprob\",\"name\":\"B\"}]}" reg
fx_user "$FIX/sec-c" aluno1 s "A"     # sessão só vale p/ quem TEM conta no contest (lib/auth.sh)
fx_user "$FIX/vis-c" aluno2 s "B"
printf 'CONTEST=sec-c\nLOGIN=aluno1\nUSERFULLNAME=A\nLOGINAT=1\n' > "$SESS/sal"
printf 'CONTEST=sec-c\nLOGIN=regular.admin\nUSERFULLNAME=Adm\nLOGINAT=1\n' > "$SESS/sadm"
printf 'CONTEST=vis-c\nLOGIN=aluno2\nUSERFULLNAME=B\nLOGINAT=1\n' > "$SESS/valu"

echo "== criação com secret:true =="
ck "conf tem SECRET=1"          'grep -q "^SECRET=1" "$FIX/sec-c/conf"'
ck "visível NÃO tem SECRET"     '! grep -q "^SECRET=" "$FIX/vis-c/conf"'

echo "== listagens públicas =="
call /index/contests GET '' '' ''
ck "home não lista o secreto"   '[[ "$(jq -r "[.open[].id, .upcoming[].id, .closed.items[].id]|index(\"sec-c\")" <<<"$BODY")" == null ]]'
ck "home lista o visível"       '[[ "$(jq -r "[.open[].id]|index(\"vis-c\")" <<<"$BODY")" != null ]]'
mkdir -p "$FIX/sec-c/users/aluno1" "$FIX/vis-c/users/aluno2"
printf '0:bankprob:C:Not Answered Yet:0:s1\n' > "$FIX/sec-c/users/aluno1/history"
printf '0:bankprob:C:Not Answered Yet:0:s2\n' > "$FIX/vis-c/users/aluno2/history"
call /index/status GET '' '' ''
ck "status não expõe o secreto" '[[ "$(jq -r "[.queue.lists[].contest]|index(\"sec-c\")" <<<"$BODY")" == null ]]'
ck "status lista o visível"     '[[ "$(jq -r "[.queue.lists[].contest]|index(\"vis-c\")" <<<"$BODY")" != null ]]'
ck "total conta os dois"        '[[ "$(jq -r .queue.total_pending <<<"$BODY")" == 2 ]]'

echo "== placar e visual exigem sessão do contest =="
for ep in score balloons regions teams-meta; do
  call "/contest/$ep" GET '' '' 'contest=sec-c'
  ck "$ep sem token 401"        '[[ "$OUT" == *"Status: 401"* ]]'
done
call /contest/score GET '' valu 'contest=sec-c'
ck "sessão de OUTRO contest 401" '[[ "$OUT" == *"Status: 401"* ]]'
call /contest/score GET '' sal 'contest=sec-c'
ck "aluno do contest vê o placar" '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/balloons GET '' sal 'contest=sec-c'
ck "balloons com sessão 200"    '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/score GET '' '' 'contest=vis-c'
ck "visível segue público"      '[[ "$OUT" == *"Status: 200"* ]]'

echo "== mídia do time é PÚBLICA, mesmo em contest secreto =="
# Decisão de 2026-08-24: a foto e a música existem para ir ao TELÃO, e o telão é um sistema
# EXTERNO (o Animeitor) que busca sem sessão. O gate protegia pouco e atrapalhava muito — com
# ele nem o `<img>` do próprio MOJ funcionava, porque tag de mídia não manda `Authorization`.
# ⚠ Este bloco afirma o AFROUXAMENTO; o de baixo afirma o que ele NÃO pode ter afrouxado junto.
# foto/música do time caem no PADRÃO DE FÁBRICA (server/etc/team-placeholder.*) quando o time não
# mandou a sua — nenhum binário precisa ser fabricado aqui. Só o brasão dá 404 sem arquivo.
mkdir -p "$FIX/sec-c/users/aluno1"; printf 'x' > "$FIX/sec-c/users/aluno1/logo.png"
MEDIA=( 'team-photo:contest=sec-c&user=aluno1'
        'team-photo:contest=sec-c&user=aluno1&thumb=1'
        'team-music:contest=sec-c&user=aluno1'
        'team-logo:contest=sec-c&user=aluno1'
        'placeholder:contest=sec-c'
        'placeholder:contest=sec-c&kind=music' )
for m in "${MEDIA[@]}"; do
  ep="${m%%:*}"; qs="${m#*:}"; lbl="$ep${qs#contest=sec-c&user=aluno1}"
  callh "/contest/$ep" '' "$qs"
  ck "$lbl SEM token 200"       '[[ "$OUT" == *"Status: 200"* ]]'
  callh "/contest/$ep" sal "$qs"
  ck "$lbl com sessão 200"      '[[ "$OUT" == *"Status: 200"* ]]'
done
callh /contest/team-photo valu 'contest=sec-c&user=aluno1'
ck "foto c/ sessão de OUTRO contest 200" '[[ "$OUT" == *"Status: 200"* ]]'
# a doutrina "nunca 404" continua valendo
callh /contest/team-photo '' 'contest=sec-c&user=aluno1'
ck "foto do contest é a padrão"  '[[ "$OUT" == *"X-MOJ-Photo: placeholder"* ]]'
callh /contest/team-music '' 'contest=sec-c&user=aluno1'
ck "música do contest é a padrão" '[[ "$OUT" == *"X-MOJ-Music: placeholder"* ]]'

echo "== …e o afrouxamento PARA na mídia: o placar e o visual seguem trancados =="
# É a linha que não se atravessa. As cinco rotas abaixo compartilham o MESMO gate que as quatro
# de mídia perderam — se alguém "simplificar" o require_not_secret_or_auth, é aqui que quebra.
for ep in score teams teams-meta balloons regions; do
  call "/contest/$ep" GET '' '' 'contest=sec-c'
  ck "$ep segue 401 sem sessão"  '[[ "$OUT" == *"Status: 401"* ]]'
done

echo "== tela de login continua funcional =="
call /contest/basic GET '' '' 'contest=sec-c'
ck "basic público com secret:true" '[[ "$(jq -r .secret <<<"$BODY")" == true && "$(jq -r .contest_name <<<"$BODY")" == "Prova Secreta" ]]'

echo "== settings marca/desmarca =="
call /contest/admin/settings GET '' sadm 'contest=sec-c'
ck "settings GET secret:true"   '[[ "$(jq -r .secret <<<"$BODY")" == true ]]'
call /contest/admin/settings POST '{"secret":false}' sadm 'contest=sec-c'
ck "desmarcou"                  '[[ "$(jq -r .saved <<<"$BODY")" == true ]] && ! grep -q "^SECRET=" "$FIX/sec-c/conf"'
call /index/contests GET '' '' ''
ck "desmarcado volta à home"    '[[ "$(jq -r "[.open[].id]|index(\"sec-c\")" <<<"$BODY")" != null ]]'
call /contest/score GET '' '' 'contest=sec-c'
ck "placar volta a ser público" '[[ "$OUT" == *"Status: 200"* ]]'
callh /contest/team-photo '' 'contest=sec-c&user=aluno1'
ck "foto volta a ser pública"   '[[ "$OUT" == *"Status: 200"* ]]'
call /contest/admin/settings POST '{"secret":true}' sadm 'contest=sec-c'
ck "marcou de novo"             'grep -q "^SECRET=1" "$FIX/sec-c/conf"'

echo "== criador continua vendo (mine/export) =="
call /treino/contest-create/mine GET '' reg ''
ck "mine lista o secreto"       '[[ "$(jq -r "[.contests[].id]|index(\"sec-c\")" <<<"$BODY")" != null ]]'
call /treino/contest-create/export GET '' reg 'id=sec-c'
ck "export carrega secret:true" '[[ "$(jq -r .secret <<<"$BODY")" == true ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
