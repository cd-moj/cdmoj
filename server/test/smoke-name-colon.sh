#!/bin/bash
# smoke-name-colon.sh — NOME com ':' (time, escola): todo caminho que grava troca ':' por '∶' (U+2236, igual na
# tela) e avisa; senha/email seguem sem ':'. Relato do TCP 2026 (04/10/2026): `localhost:6767` era recusado no
# lote (pulado sem dizer por quê), perdia o ':' no editor de Times e no placar; `HelloWorld"(print)"` perdia as
# aspas no CSV (web — smoke-users-batch.gjs.sh). O placar e o relatório são TXT separados por ':' — é por isso.
# Roda também em locale POSIX (como a imagem de produção): `LANG= LC_ALL= bash smoke-name-colon.sh`.
set -u
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"; ROUTER="$ROOT/api/v1/router.sh"
FIX="$(mktemp -d)"; SESS="$(mktemp -d)"; trap 'rm -rf "$FIX" "$SESS"' EXIT
source "$(dirname "$(readlink -f "$0")")/fixture.sh"
export CONTESTSDIR="$FIX"
C="$FIX/nc"; mkdir -p "$C/var"; NOW="$EPOCHSECONDS"
printf 'CONTEST_ID=nc\nCONTEST_TYPE=icpc\nCONTEST_START=%s\nCONTEST_END=%s\nUSER_STORE=v2\nPROBS=( x col#pa Alfa A col#pa )\n' \
  $((NOW-3600)) $((NOW+3600)) > "$C/conf"
fx_user "$C" nc.admin p "Admin" >/dev/null
printf 'CONTEST=nc\nLOGIN=nc.admin\nLOGINAT=1\n' > "$SESS/adm"
call(){ OUT="$(PATH_INFO="$1" REQUEST_METHOD="$2" QUERY_STRING="contest=nc" HTTP_AUTHORIZATION="Bearer adm" \
    SESSIONDIR="$SESS" bash "$ROUTER" <<<"${3:-}" 2>&1)"; BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"; }
J(){ jq -r "$1" <<<"$BODY" 2>/dev/null; }
A(){ jq -r "$2" "$C/users/$1/account.json" 2>/dev/null; }
RT=$'\xe2\x88\xb6'   # '∶'
pass=0; fail=0; ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${BODY:0:220}"; ((fail++)); fi; }

echo "== user-add: o ':' do nome vira '∶' e a resposta avisa; senha/email com ':' = 422 =="
call /contest/admin/user-add POST '{"login":"t1","fullname":"localhost:6767"}'
ck "gravou com '∶'"                 '[[ "$(J .saved)" == true && "$(A t1 .fullname)" == "localhost${RT}6767" ]]'
ck "…e avisa (adjusted from→to)"    '[[ "$(J .adjusted[0].from)" == "localhost:6767" && "$(J .adjusted[0].to)" == "localhost${RT}6767" ]]'
call /contest/admin/user-add POST '{"login":"t1b","fullname":"Sem dois pontos"}'
ck "nome sem ':' não traz adjusted"  '[[ "$(J .saved)" == true && "$(J "has(\"adjusted\")")" == false ]]'
call /contest/admin/user-add POST '{"login":"t1c","password":"a:b"}'
ck "senha com ':' = 422 colon"      '[[ "$OUT" == *"Status: 422"* && "$(J .error.code)" == colon && ! -e "$C/users/t1c" ]]'
call /contest/admin/user-add POST '{"login":"t1d","fullname":"   "}'
ck "nome só de espaços = o login"   '[[ "$(A t1d .fullname)" == t1d ]]'

echo "== lote: nome ajustado + motivo ESPECÍFICO de cada pulado =="
call /contest/admin/users-bulk POST '{"users":[{"login":"t2","fullname":"HelloWorld\"(print)\""},{"login":"t3","fullname":"a:b","univ_full":"Univ: X"},{"login":"inv lido","fullname":"x"},{"login":"t4","password":"x:y"},{"login":"t5","email":"e:x"},{"login":"t2","fullname":"dup"}]}'
ck "criou t2 e t3"                  '[[ "$(J .counts.created)" == 2 ]]'
ck "aspas no nome passam intactas"  '[[ "$(A t2 .fullname)" == "HelloWorld\"(print)\"" ]]'
ck "t3: nome e escola com '∶'"      '[[ "$(A t3 .fullname)" == "a${RT}b" && "$(A t3 .team.univ_full)" == "Univ${RT} X" ]]'
ck "adjusted lista o t3"            '[[ "$(J .counts.adjusted)" == 1 && "$(J .adjusted[0].login)" == t3 && "$(J .adjusted[0].from)" == "a:b" ]]'
ck "login inválido = login_invalid" '[[ "$(J ".skipped[]|select(.login==\"inv lido\").reason")" == login_invalid ]]'
ck "senha com ':' = colon"          '[[ "$(J ".skipped[]|select(.login==\"t4\").reason")" == colon ]]'
ck "email com ':' = colon"          '[[ "$(J ".skipped[]|select(.login==\"t5\").reason")" == colon ]]'
ck "repetido = duplicate"           '[[ "$(J "[.skipped[]|select(.reason==\"duplicate\")]|length")" == 1 ]]'
call /contest/admin/users-bulk POST '{"on_existing":"update","users":[{"login":"t2","fullname":"novo:nome"},{"login":"t3","password":"p3"}]}'
ck "update: nome novo com '∶' + adjusted" '[[ "$(A t2 .fullname)" == "novo${RT}nome" && "$(J ".adjusted[0].login")" == t2 ]]'
ck "update sem nome não mexe no nome"     '[[ "$(A t3 .fullname)" == "a${RT}b" ]]'

echo "== editor de Times (admin/teams set) =="
call /contest/admin/teams POST '{"set":{"t1b":{"fullname":"x:y","univ_short":"U:1","region":"Sede: A"}}}'
ck "nome e sigla com '∶'; a sede (chave) com espaço" '[[ "$(A t1b .fullname)" == "x${RT}y" && "$(A t1b .team.univ_short)" == "U${RT}1" && "$(A t1b .team.region)" == "Sede  A" ]]'
ck "…e a resposta avisa"            '[[ "$(J .saved)" == 1 && "$(J .adjusted[0].to)" == "x${RT}y" ]]'

echo "== placar TXT: o ':' cru de dado ANTIGO sai como '∶' e as colunas não andam =="
jq '.fullname = "velho:dado"' "$C/users/t1d/account.json" > "$C/t" && mv "$C/t" "$C/users/t1d/account.json"
bash "$ROOT/score/build.sh" nc >/dev/null 2>&1; [[ -n "${KEEP:-}" ]] && cat "$C/var/placar.txt"
ck "linha do t1d com o nome com '∶'" 'grep -q "^:t1d::velho${RT}dado:" "$C/var/placar.txt"'
ck "toda linha de time com o mesmo nº de colunas" '[[ "$(grep -v "^desc:asc" "$C/var/placar.txt" | grep ":" | awk -F: "{print NF}" | sort -u | wc -l)" == 1 ]]'
ck "o nome do t1 aparece com '∶'"   'grep -q "localhost${RT}6767" "$C/var/placar.txt"'

echo "== slug SEM acento também em locale POSIX (a imagem de produção): login de conta gerida =="
# em POSIX o `iconv //TRANSLIT` dava '?' por letra acentuada: "João da Silva Ávila" virava jo.vila (lib: o mesmo
# conserto do reg_team_slug — smoke-registration, rodado com LANG= LC_ALL=, cobre o slug do time)
TR="$FIX/treino"; mkdir -p "$TR/var"; printf 'CONTEST_ID=treino\nCONTEST_END=%s\n' $((NOW+86400)) > "$TR/conf"
fx_user "$TR" chefe.admin s Chefe >/dev/null
printf 'CONTEST=treino\nLOGIN=chefe.admin\nLOGINAT=1\n' > "$SESS/tadm"
OUT="$(PATH_INFO=/treino/admin/managed-create REQUEST_METHOD=POST HTTP_AUTHORIZATION="Bearer tadm" SESSIONDIR="$SESS" \
  LANG= LC_ALL= bash "$ROUTER" <<<'{"users":[{"fullname":"João da Silva Ávila","birthdate":"2014-01-01"}]}' 2>&1)"
BODY="$(printf '%s' "$OUT" | awk 'f{print} /^\r?$/{f=1}')"
ck "conta gerida de 'João … Ávila' = joao.avila" '[[ "$(J .created[0].login)" == joao.avila ]]'

echo ""; echo "RESULT: $pass passed, $fail failed"; exit $(( fail>0?1:0 ))
